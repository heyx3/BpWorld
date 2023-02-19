"A sphere whose coordinates are in UV space (0 is min voxel corner, 1 is max voxel corner)."
Base.@kwdef struct VoxelSphere <: AbstractVoxelGenerator
    center::v3f
    radius::Float32

    surface_thickness::Float32 = 0 # If set to a positive value, then
                                   #    only the surface is solid.

    layer::VoxelElement
    invert::Bool = false
end

function generate!(grid::VoxelGrid, s::VoxelSphere, use_threads::Bool)
    # Handle inversion.
    local inside_val::VoxelElement,
          outside_val::VoxelElement
    if s.invert
        inside_val = EMPTY_VOXEL
        outside_val = s.layer
    else
        inside_val = s.layer
        outside_val = EMPTY_VOXEL
    end

    # Calculate whether each position is inside or outside the sphere (or its surface).
    #TODO: Precalculate this sphere's voxel bounds, to early-exit on each element.
    use_thickness::Bool = (s.surface_thickness > 0)
    function process_element(x, y, z)
        p::v3f = (v3f(x, y, z) + @f32(0.5)) / vsize(grid)
        dist_sqr = vdist_sqr(p, s.center)

        if use_thickness
            surface_dist::Float32 = abs(sqrt(dist_sqr) - s.radius)
            grid[x, y, z] = (surface_dist <= s.surface_thickness) ?
                                inside_val :
                                outside_val
        else
            max_dist_sqr = s.radius * s.radius
            grid[x, y, z] = (dist_sqr <= max_dist_sqr) ?
                                inside_val :
                                outside_val
        end
    end
    if use_threads
        vert_idcs = 1:size(grid, 2)
        horz_idcs = one(v2i):vsize(grid).xy
        Threads.@threads for z in vert_idcs
            for (x, y) in horz_idcs
                process_element(x, y, z)
            end
        end
    else
        for (x, y, z) in one(v3i):vsize(grid)
            process_element(x, y, z)
        end
    end
end

# Expose to the DSL as the function 'Sphere()'.
function dsl_call(::Val{:Sphere}, args, dsl_state::DslState)::VoxelSphere
    dsl_context_block(dsl_state, "Sphere(", args..., ")") do
        # All arguments should be provided by name.
        if !all(a -> Base.is_expr(a, :kw), args)
            error("All arguments must be provided by name (e.x. 'min = a+b')")
        end
        if !all(a -> a.args[1] isa Symbol, args)
            error("Argument names are malformed")
        end
        arg_dict = Dict{Symbol, Any}((a.args[1] => a.args[2]) for a in args)

        # There are three required fields.
        if !all(haskey.(Ref(arg_dict), (:layer, :center, :radius)))
            error("Sphere() should have exactly three arguments: 'layer', 'center', and 'radius'")
        end
        arg_layer = Ref{Any}()
        arg_center = Ref{Any}()
        arg_radius = Ref{Any}()
        dsl_context_block(dsl_state, "'layer' argument") do
            arg_layer[] = convert(VoxelElement, dsl_expression(arg_dict[:layer], dsl_state))
        end
        dsl_context_block(dsl_state, "'center' argument") do
            arg_center[] = convert(v3f, dsl_expression(arg_dict[:center], dsl_state))
        end
        dsl_context_block(dsl_state, "'radius' argument") do
            arg_radius[] = convert(Float32, dsl_expression(arg_dict[:radius], dsl_state))
        end
        for a in (:layer, :center, :radius)
            delete!(arg_dict, a)
        end

        # There are two optional fields.
        arg_invert = Ref{Bool}(false)
        arg_thickness = Ref{Float32}(0)
        dsl_context_block(dsl_state, "'invert' argument") do 
            if haskey(arg_dict, :invert)
                arg_invert[] = convert(Bool, dsl_expression(arg_dict[:invert], dsl_state))
            end
        end
        dsl_context_block(dsl_state, "'thickness' argument") do 
            if haskey(arg_dict, :thickness)
                arg_thickness[] = convert(Float32, dsl_expression(arg_dict[:thickness], dsl_state))
            end
        end
        for a in (:invert, :thickness)
            delete!(arg_dict, a)
        end

        # That should be all of the fields.
        if !isempty(arg_dict)
            error("Unexpected arguments: [ ", join(keys(arg_dict), ", "), " ]")
        end

        return VoxelSphere(center = arg_center[], radius = arg_radius[],
                           layer = arg_layer[],
                           surface_thickness = arg_thickness[],
                           invert = arg_invert[])
    end
end


@bp_enum BoxModes filled surface edges corners

Base.@kwdef struct VoxelBox{TMode<:Val} <: AbstractVoxelGenerator
    area::Box3Df
    layer::VoxelElement
    invert::Bool = false
end
@inline VoxelBox(layer, area; mode=BoxModes.filled, kw...) = VoxelBox{Val{mode}}(;
    layer=layer,
    area=area,
    kw...
)

box_mode(::VoxelBox{Val{T}}) where {T} = T

function generate!(grid::VoxelGrid, b::VoxelBox{Val{TMode}}, use_threads::Bool) where {TMode}
    # Compute the min and max voxels covered by this box.
    grid_size = vsize(grid)
    voxel_scale = convert(v3f, grid_size)
    voxel_area = Box3Df(b.area.min * voxel_scale,
                        b.area.size * voxel_scale)
    voxel_min::v3f = voxel_area.min + @f32(0.5)
    voxel_max::v3f = max_inclusive(voxel_area) - @f32(0.5)

    to_bounds(f::Float32) = UInt32(floor(max(@f32(0), f)))
    bounds = (map(to_bounds, voxel_min),
              map(to_bounds, voxel_max))

    function calculate_element(x, y, z)::VoxelElement
        p::v3f = (v3f(x, y, z) + @f32(0.5)) / vsize(grid)
        idx::v3u = v3u(x, y, z)

        # Handle inversion.
        local inside_val::VoxelElement,
            outside_val::VoxelElement
        if b.invert
            inside_val = EMPTY_VOXEL
            outside_val = b.layer
        else
            inside_val = b.layer
            outside_val = EMPTY_VOXEL
        end

        is_inside::Bool = all(idx >= bounds[1]) && all(idx <= bounds[2])
        if is_inside && (TMode != BoxModes.filled)
            # Count the number of axes along which the position is on the box's edge.
            # Try to induce the compiler to unroll the loop.
            n_axes_on_edge::Int = count(tuple((
                (idx[i] == bounds[1][i]) || (idx[i] == bounds[2][i])
                for i in 1:3
            )...))
            @bpworld_assert(n_axes_on_edge in 0:3, n_axes_on_edge)

            is_inside = if TMode == BoxModes.surface
                n_axes_on_edge >= 1
            elseif TMode == BoxModes.edges
                n_axes_on_edge >= 2
            elseif TMode == BoxModes.corners
                n_axes_on_edge == 3
            else
                error("Unhandled case: ", TMode)
            end
        end

        return is_inside ? inside_val : outside_val
    end

    if use_threads
        vert_idcs = 1:size(grid, 2)
        horz_idcs = one(v2i):vsize(grid).xy
        Threads.@threads for z in vert_idcs
            for (x, y) in horz_idcs
                grid[x, y, z] = calculate_element(x, y, z)
            end
        end
    else
        for (x, y, z) in one(v3i):vsize(grid)
            grid[x, y, z] = calculate_element(x, y, z)
        end
    end
end

# Expose to the DSL as the function 'Box()'.
function dsl_call(::Val{:Box}, args, dsl_state::DslState)::VoxelBox
    dsl_context_block(dsl_state, "Box(", args..., ")") do
        # All arguments should be provided by name.
        if !all(a -> Base.is_expr(a, :kw), args)
            error("All arguments must be provided by name (e.x. 'min = a+b')")
        end
        if !all(a -> a.args[1] isa Symbol, args)
            error("Argument names are malformed")
        end
        arg_dict = Dict{Symbol, Any}((a.args[1] => a.args[2]) for a in args)

        # There is one required field.
        if !haskey(arg_dict, :layer)
            error("The 'layer' argument is missing")
        end
        arg_layer = Ref{Any}()
        dsl_context_block(dsl_state, "'layer' argument") do
            arg_layer[] = convert(VoxelElement, dsl_expression(arg_dict[:layer], dsl_state))
        end
        delete!(arg_dict, :layer)

        # Exactly two of the following fields are required: 'min', 'max', and 'size'.
        arg_min = Ref{Any}()
        arg_max = Ref{Any}()
        arg_size = Ref{Any}()
        dsl_context_block(dsl_state, "'min' argument") do
            if haskey(arg_dict, :min)
                arg_min[] = convert(v3f, dsl_expression(arg_dict[:min], dsl_state))
            end
        end
        dsl_context_block(dsl_state, "'max' argument") do
            if haskey(arg_dict, :max)
                arg_max[] = convert(v3f, dsl_expression(arg_dict[:max], dsl_state))
            end
        end
        dsl_context_block(dsl_state, "'size' argument") do
            if haskey(arg_dict, :size)
                arg_size[] = convert(v3f, dsl_expression(arg_dict[:size], dsl_state))
            end
        end
        if count(isassigned, (arg_min, arg_max, arg_size)) != 2
            error("Exactly two of the following three parameters must be given to Box():",
                  " 'min', 'max', 'size'")
        end
        delete!.(Ref(arg_dict), (:min, :max, :size))
        arg_bounds = if all(isassigned, (arg_min, arg_max))
                         Box_minmax(arg_min[], arg_max[])
                     elseif all(isassigned, (arg_min, arg_size))
                         Box_minsize(arg_min[], arg_size[])
                     elseif all(isassigned, (arg_max, arg_size))
                         Box_maxsize(arg_max[], arg_size[])
                     else
                         error(arg_min, "  ", arg_max, "  ", arg_size)
                     end

        # There are two optional fields.
        arg_invert = Ref{Bool}(false)
        arg_mode = Ref{E_BoxModes}(BoxModes.filled)
        dsl_context_block(dsl_state, "'invert' argument") do 
            if haskey(arg_dict, :invert)
                arg_invert[] = convert(Bool, dsl_expression(arg_dict[:invert], dsl_state))
            end
        end
        dsl_context_block(dsl_state, "'mode' argument") do
            if haskey(arg_dict, :mode)
                if !isa(arg_dict[:mode], Symbol)
                    error("'mode' argument must be one of the following: ",
                          join(Symbol.(BoxModes.instances()), ", "),
                          ". Got: ", arg_dict[:mode])
                else
                    try
                        arg_mode[] = BoxModes.from(Val(arg_dict[:mode]))
                    catch e
                        error("Unknown voxel box mode: '", arg_mode[], "'")
                    end
                end
            end
        end
        delete!.(Ref(arg_dict), (:invert, :mode))

        # That should be all of the fields.
        if !isempty(arg_dict)
            error("Unexpected arguments: [ ", join(keys(arg_dict), ", "), " ]")
        end

        try
        return VoxelBox(arg_layer[], arg_bounds,
                        invert = arg_invert[],
                        mode = arg_mode[])
        catch e
            @error "hi"  exception=(e, catch_backtrace())
            rethrow()
        end
    end
end