"
Generates voxels by applying a `Field` over them (see the `Bplus.Fields` module),
    and counting values above 0.5 as 'solid'.

Applies multiple fields, each corresponding to a voxel type,
    from most to least important (so earlier ones override later ones).

Fields should be of type `Bplus.Fields.AbstractField{3, 1, Float32}`,
   but other float types can be automatically converted to Float32 for you.
"
struct VoxelBinaryField <: AbstractVoxelGenerator
    layers::AbstractVector{Pair{VoxelElement, Bplus.Fields.AbstractField{3, 1, Float32}}}

    function VoxelBinaryField(layers::AbstractVector{<:Pair})
        instance = new([ ])
        for (type::VoxelElement, field::AbstractField{3, 1}) in layers
            if Bplus.Fields.field_component_type(field) != Float32
                field = ConversionField(field, Float32)
            end
            push!(instance.layers, type => field)
        end
        return instance
    end
end

function generate!(voxels::VoxelGrid, field_grid::VoxelBinaryField, use_threads::Bool)
    # Generate the field data.
    voxel_grid_size = vsize(voxels)
    process_layer(layer::Pair{VoxelElement, AbstractField{3, 1, Float32}}) = tuple(
        layer[1],
        sample_field(voxel_grid_size, layer[2] ;
                     use_threading = use_threads)
    )
    field_voxels = map(field_grid.layers) do layer
        return tuple(
            layer[1]::VoxelElement,
            sample_field(voxel_grid_size, layer[2]; use_threading = use_threads)
        )
    end

    # Generate the voxel grid.
    function fill_voxel(x, y, z)
        # Look for the first voxel grid that fills this space.
        for (block_type, layer_voxels) in field_voxels
            if layer_voxels[x, y, z].x >= 0.5
                voxels[x, y, z] = block_type
                return
            end
        end
        # If we exited the loop, then none of the voxel grids are solid here.
        voxels[x, y, z] = EMPTY_VOXEL
    end
    if use_threads
        vert_idcs = 1:size(voxels, 2)
        horz_idcs = one(v2i):vsize(voxels).xy
        Threads.@threads for z in vert_idcs
            for (x, y) in horz_idcs
                fill_voxel(x, y, z)
            end
        end
    else
        for (x,y,z) in one(v3i):vsize(voxels)
            fill_voxel(x, y, z)
        end
    end
end

# Expose to the DSL as the function 'BinaryField()'.
#TODO: Support more complex syntax for multiple layers of blocks.
function dsl_call(::Val{:BinaryField}, args, dsl_state::DslState)::VoxelBinaryField
    dsl_context_block(dsl_state, "BinaryField(", args..., ")") do
        # All arguments should be provided by name.
        if !all(a -> Base.is_expr(a, :kw), args)
            error("All arguments must be provided by name (e.x. 'min = a+b')")
        end
        if !all(a -> a.args[1] isa Symbol, args)
            error("Argument names are malformed")
        end
        arg_dict = Dict{Symbol, Any}((a.args[1] => a.args[2]) for a in args)

        # There are two required fields and no optional fields.
        if length(arg_dict) != 2 || !haskey(arg_dict, :layer) || !haskey(arg_dict, :field)
            error("BinaryField() should have exactly two arguments: 'layer' and 'field'")
        end
        arg_layer = Ref{Any}()
        arg_field = Ref{Any}()
        dsl_context_block(dsl_state, "'layer' argument") do
            arg_layer[] = convert(VoxelElement, dsl_expression(arg_dict[:layer], dsl_state))
        end
        dsl_context_block(dsl_state, "'field' argument") do
            field_syntax = arg_dict[:field]
            # Is this a multi-field, or a single field?
            if Base.is_expr(field_syntax, :block)
                arg_field[] = Bplus.Fields.eval(Bplus.Fields.multi_field_macro_impl(field_syntax))
            else
                arg_field[] = Bplus.Fields.eval(Bplus.Fields.field_macro_impl(3, Symbol(Float32), field_syntax))
            end
            if !isa(arg_field[], Bplus.Fields.AbstractField{3, 1, Float32})
                error("Failed to parse field into a 3D field of scalar values.",
                      " It's a ", typeof(arg_field[]))
            end
        end

        return VoxelBinaryField([ arg_layer[] => arg_field[] ])
    end
end


#TODO: A 'VoxelContinuousField', using field value to interpolate through a "curve" of voxel elements. To do this, implement an "InterpCurve" type in B-Plus.