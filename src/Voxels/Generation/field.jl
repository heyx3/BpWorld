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
        vert_idcs = 1:size(grid, 2)
        horz_idcs = one(v2i):vsize(grid).xy
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


#TODO: A 'VoxelContinuousField', using field value to interpolate through a "curve" of voxel elements. To do this, implement an "InterpCurve" type in B-Plus.