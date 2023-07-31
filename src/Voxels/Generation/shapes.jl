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
dsl_copy(s::VoxelSphere) = VoxelSphere(s.center, s.radius, s.surface_thickness, s.layer, s.invert)


@bp_enum BoxModes filled surface edges corners

struct VoxelBox{TMode<:Val} <: AbstractVoxelGenerator
    area::Box3Df
    layer::VoxelElement
    invert::Bool
end
VoxelBox(mode::E_BoxModes = BoxModes.filled
         ;
         area::Box3Df,
         layer::VoxelElement,
         invert::Bool = false) = VoxelBox{Val{mode}}(area, layer, invert)

# The type parameter is needed when Setfield invokes the default constructor.
Setfield.ConstructionBase.constructorof(T::Type{<:VoxelBox}) = T

box_mode(::VoxelBox{Val{T}}) where {T} = T

function generate!(grid::VoxelGrid, b::VoxelBox{Val{TMode}}, use_threads::Bool) where {TMode}
    # Compute the min and max voxels covered by this box.
    grid_size = vsize(grid)
    voxel_scale = convert(v3f, grid_size)
    voxel_area = Box3Df((min = min_inclusive(b.area) * voxel_scale,
                         size = size(b.area) * voxel_scale))
    voxel_min::v3f = min_inclusive(voxel_area) + @f32(0.5)
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

        # Exactly two of the following fields are required: 'min', 'max', 'center', and 'size'.
        arg_min = Ref{Any}()
        arg_max = Ref{Any}()
        arg_center = Ref{Any}()
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
        dsl_context_block(dsl_state, "'center' argument") do
            if haskey(arg_dict, :center)
                arg_center[] = convert(v3f, dsl_expression(arg_dict[:center], dsl_state))
            end
        end
        dsl_context_block(dsl_state, "'size' argument") do
            if haskey(arg_dict, :size)
                arg_size[] = convert(v3f, dsl_expression(arg_dict[:size], dsl_state))
            end
        end
        if count(isassigned, (arg_min, arg_max, arg_center, arg_size)) != 2
            error("Exactly two of the following parameters must be given to Box():",
                  " 'min', 'max', 'center', 'size'")
        end
        delete!.(Ref(arg_dict), (:min, :max, :center, :size))
        arg_bounds = if all(isassigned, (arg_min, arg_max))
                         Box((min=arg_min[], max=arg_max[]))
                     elseif all(isassigned, (arg_min, arg_size))
                         Box((min=arg_min[], size=arg_size[]))
                     elseif all(isassigned, (arg_max, arg_size))
                         Box((max=arg_max[], size=arg_size[]))
                     elseif all(isassigned, (arg_min, arg_center))
                         Box((min=arg_min[], size=2 * (arg_center[] - arg_min[])))
                     elseif all(isassigned, (arg_max, arg_center))
                         Box((max=arg_max[], size=2 * (arg_max[] - arg_center[])))
                     elseif all(isassigned, (arg_center, arg_size))
                         Box((center=arg_center[], size=arg_size[]))
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
            return VoxelBox(arg_mode[],
                            layer=arg_layer[],
                            area=arg_bounds,
                            invert=arg_invert[])
        catch e
            @error "hi"  exception=(e, catch_backtrace())
            rethrow()
        end
    end
end
dsl_copy(b::VoxelBox) = typeof(b)(b.area, b.layer, b.invert)

# copy() has special behavior for 'mode', and sub-properties of its 'area' property.
function dsl_copy(src::VoxelBox, changes::Dict{Any, Pair{Symbol, Any}}, dsl_state::DslState)::VoxelBox
    let dest = Ref{VoxelBox}(src)
        # Handle the special properties, and remove them from 'changes' as we go.
        dsl_context_block(dsl_state, "'mode' modification") do
            if haskey(changes, :mode)
                (modification, rhs_expr) = changes[:mode]
                delete!(changes, :mode)

                # Error-checking:
                if !isa(rhs_expr, Symbol)
                    error("'mode' argument must be one of the following: ",
                            join(Symbol.(BoxModes.instances()), ", "),
                            ". Got: ", rhs_expr)
                elseif modification != :(=)
                    error("'mode' can only be set to a value; you tried to perform '",
                            modification, "' on it")
                end

                # Parse the mode.
                new_mode::Optional{E_BoxModes} = nothing
                try
                    new_mode = BoxModes.from(Val(rhs_expr))
                catch e
                    error("Unknown voxel box mode: '", rhs_expr, "'")
                end

                # Set the mode, by making a new Box of that mode with all the same field values.
                field_values = NamedTuple()
                for f::Symbol in fieldnames(typeof(dest[]))
                    field_values = merge(field_values, tuple(f => getfield(dest[], f)))
                end
                dest[] = Setfield.setproperties(VoxelBox(new_mode, area=Box3Df(v3f(), v3f()), layer=0x0),
                                                field_values)
            end
        end
        dsl_context_block(dsl_state, "'min' modification") do
            if haskey(changes, :min)
                (modification, rhs_expr) = changes[:min]
                delete!(changes, :min)
                rhs_value = dsl_expression(rhs_expr, dsl_state)

                # Error-checking:
                if !isa(rhs_value, Union{Vec{3}, Vec{1}, Real})
                    error("The property  is being modified with ", rhs_value, ", not a number or vector")
                end

                # Arg processing:
                if rhs_value isa Vec{1}
                    rhs_value = rhs_value.xxx
                elseif rhs_value isa Real
                    rhs_value = v3f(rhs_value, rhs_value, rhs_value)
                end
                new_value = dynamic_modify(modification, min_inclusive(dest[].area), rhs_value)

                # Set the min, leaving max unchanged.
                dest[] = Setfield.setproperties(dest[], (
                    area=Box((min=new_value, max=max_inclusive(dest[].area)))
                ))
            end
        end
        dsl_context_block(dsl_state, "'max' modification") do
            if haskey(changes, :max)
                (modification, rhs_expr) = changes[:max]
                delete!(changes, :max)
                rhs_value = dsl_expression(rhs_expr, dsl_state)

                # Error-checking:
                if !isa(rhs_value, Union{Vec{3}, Vec{1}, Real})
                    error("The property is being modified with ", rhs_value, ", not a number or vector")
                end

                # Arg processing:
                if rhs_value isa Vec{1}
                    rhs_value = rhs_value.xxx
                elseif rhs_value isa Real
                    rhs_value = v3f(rhs_value, rhs_value, rhs_value)
                end
                new_value = dynamic_modify(modification, max_inclusive(dest[].area), rhs_value)

                # Set the max, leaving min unchanged.
                dest[] = Setfield.setproperties(dest[], (
                    area=Box((min=min_inclusive(dest[].area), max=new_value))
                ))
            end
        end
        dsl_context_block(dsl_state, "'center' modification") do
            if haskey(changes, :center)
                (modification, rhs_expr) = changes[:center]
                delete!(changes, :center)
                rhs_value = dsl_expression(rhs_expr, dsl_state)

                # Error-checking:
                if !isa(rhs_value, Union{Vec{3}, Vec{1}, Real})
                    error("The property is being modified with ", rhs_value, ", not a number or vector")
                end

                # Arg processing:
                if rhs_value isa Vec{1}
                    rhs_value = rhs_value.xxx
                elseif rhs_value isa Real
                    rhs_value = v3f(rhs_value, rhs_value, rhs_value)
                end
                new_value = dynamic_modify(modification, center(dest[].area), rhs_value)

                # Set the center, leaving the size unchanged.
                dest[] = Setfield.setproperties(dest[], (
                    area=Box((center=new_value, size=size(dest[].area)))
                ))
            end
        end
        dsl_context_block(dsl_state, "'size' modification") do
            if haskey(changes, :size)
                (modification, rhs_expr) = changes[:size]
                delete!(changes, :size)
                rhs_value = dsl_expression(rhs_expr, dsl_state)

                # Error-checking:
                if !isa(rhs_value, Union{Vec{3}, Vec{1}, Real})
                    error("The property is being modified with ", rhs_value, ", not a number or vector")
                end

                # Arg processing:
                if rhs_value isa Vec{1}
                    rhs_value = rhs_value.xxx
                elseif rhs_value isa Real
                    rhs_value = v3f(rhs_value, rhs_value, rhs_value)
                end
                new_value = dynamic_modify(modification, size(dest[].area), rhs_value)

                # Set the size, leaving the center unchanged.
                dest[] = Setfield.setproperties(dest[], (
                    area=Box((center=center(dest[].area), size=new_value))
                ))
            end
        end

        # Finally, handle any normal property changes.
        return invoke(dsl_copy,
                      Tuple{Any, typeof(changes), Any},
                      dest[], changes, dsl_state)
    end
end