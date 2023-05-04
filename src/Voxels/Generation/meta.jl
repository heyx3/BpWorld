"
Mixes multiple sources of voxel data together.
Earlier sources are prioritized over later sources.
"
struct VoxelUnion <: AbstractVoxelGenerator
    inputs::Vector{AbstractVoxelGenerator}
end

function generate!(grid::VoxelGrid, u::VoxelUnion, use_threads::Bool)
    # Calculate each input's voxel grid.
    #TODO: Keep it on one giant 4D grid to streamline memory usage and simplify syntax with @view.
    input_grids = map(i -> generate(vsize(grid), i, use_threads),
                      u.inputs)

    # Calculate the output value for each voxel
    #    by finding the first non-empty input.
    function calculate_element(x, y, z)
        for input_grid in input_grids
            if input_grid[x, y, z] != EMPTY_VOXEL
                return input_grid[x, y, z]
            end
        end
        return EMPTY_VOXEL
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

# Expose it to the DSL with a "Union()" call.
function dsl_call(::Val{:Union}, args, dsl_state::DslState)::VoxelUnion
    dsl_context_block(dsl_state, "Union(", args..., ")") do
        arg_values = dsl_expression.(args, Ref(dsl_state))
        if any(arg -> !isa(arg, AbstractVoxelGenerator), arg_values)
            error("Not all arguments to 'Union()' are voxel generators: [ ",
                  join(map(=>, args, typeof.(arg_values)), ", "),
                  " ]")
        end

        return VoxelUnion(collect(AbstractVoxelGenerator, arg_values))
    end
end
dsl_copy(u::VoxelUnion) = VoxelUnion(map(dsl_copy, u.inputs))


"Outputs the value of a voxel generator, *if* other generators would output nothing there."
struct VoxelDifference <: AbstractVoxelGenerator
    main::AbstractVoxelGenerator
    subtractors::AbstractVector{AbstractVoxelGenerator}
    to_ignore::Set{UInt8} # Voxel types that do not participate in subtraction
                          #    (if subtractors output them, it's considered empty space).
end

function generate!(grid::VoxelGrid, d::VoxelDifference, use_threads::Bool)
    # Calculate each input's voxel grid.
    main_grid = generate(vsize(grid), d.main, use_threads)
    subtractor_grids = map(i -> generate(vsize(grid), i, use_threads),
                           d.subtractors)

    # Calculate the output value for each voxel.
    function calculate_element(x, y, z)
        for subtractor in subtractor_grids
            v = subtractor[x, y, z]
            if (v != EMPTY_VOXEL) && !in(v, d.to_ignore)
                return EMPTY_VOXEL
            end
        end
        return main_grid[x, y, z]
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

# Expose it to the DSL with a "Difference()" call.
function dsl_call(::Val{:Difference}, args, dsl_state::DslState)::VoxelDifference
    dsl_context_block(dsl_state, "Difference(", args..., ")") do
        # The first argument is the "main".
        # The second argument is the "subtractors".
        #    If there are multiple subtractors, it should be an array literal.
        #    For user convenience when iterating, this can be omitted and then nothing is subtracted.
        # The third argument is a set of layers to ignore, and must be named.
        if !in(length(args), 1:3)
            error("There should be two or three arguments: the base, and the subtractor(s),",
                  " and optionally a list of layers to ignore.")
        end

        arg_main = Ref{Any}()
        dsl_context_block(dsl_state, "Main Input") do
            arg_main[] = dsl_expression(args[1], dsl_state)
            if !isa(arg_main[], AbstractVoxelGenerator)
                error("Argument is not a voxel generator: ", args[1], " => ", typeof(arg_main[]))
            end
        end

        subtractors = [ ]
        dsl_context_block(dsl_state, "Subtractors Input") do
            if (length(args) > 1) && !Base.is_expr(args[2], :(=))
                if Base.is_expr(args[2], :vect)
                    append!(subtractors, dsl_expression.(args[2].args, Ref(dsl_state)))
                else
                    push!(subtractors, dsl_expression(args[2], dsl_state))
                end
            end
            if any(s -> !isa(s, AbstractVoxelGenerator), subtractors)
                error("Not all subtractors are voxel generators: ",
                        join(typeof.(subtractors), ", "))
            end
        end

        to_ignore = Set{UInt8}()
        dsl_context_block(dsl_state, "'ignore' parameter") do
            if (length(args) > 2) || Base.is_expr(args[end], :(=))
                ignore_expr = args[end]
                if !Base.is_expr(ignore_expr, :kw) || (ignore_expr.args[1] != :ignore) || !Base.is_expr(ignore_expr.args[2], :braces)
                    error("The last optional parameter should be formatted like 'ignore = { ... }'. ", sprint(io -> dump(io, ignore_expr)))
                else
                    set_elements = args[end].args[2].args
                    #TODO: Throw a more readable error if any values aren't convertible to UInt8
                    set_values = convert.(Ref(UInt8), dsl_expression.(set_elements, Ref(dsl_state)))
                    union!(to_ignore, set_values)
                end
            end
        end

        return VoxelDifference(arg_main[], subtractors, to_ignore)
    end
end
dsl_copy(d::VoxelDifference) = VoxelDifference(dsl_copy(d.main),
                                               map(dsl_copy, d.subtractors),
                                               copy(d.to_ignore))


"
Outputs the intersection of several generators.
Voxels are only set to something non-empty when all generators would output the same value.
"
struct VoxelIntersection <: AbstractVoxelGenerator
    inputs::AbstractVector{AbstractVoxelGenerator}
end
VoxelIntersection(first_input::AbstractVoxelGenerator, rest_inputs::AbstractVoxelGenerator...) =
    VoxelIntersection([ first_input, rest_inputs... ])

function generate!(grid::VoxelGrid, i::VoxelIntersection, use_threads::Bool)
    # Calculate each input's voxel grid.
    # Keep it on one giant 4D grid to streamline memory usage.
    full_input_grid = Array{VoxelElement, 4}(undef, (size(grid)..., length(i.inputs)))
    map(enumerate(i.inputs)) do input_i, input
        input_grid = @view full_input_grid[:, :, :, input_i]
        generate!(input_grid, input, use_threads)
    end

    # Calculate the output value for each voxel.
    function calculate_element(x, y, z)
        expected_input = full_input_grid[x, y, z, 1]
        other_inputs = @view full_input_grid[x, y, z, 2:end]
        if all(e -> e == expected_input, other_inputs)
            return expected_input
        else
            return EMPTY_VOXEL
        end
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

# Expose it to the DSL with a "Intersection()" call.
function dsl_call(::Val{:Intersection}, args, dsl_state::DslState)::VoxelIntersection
    dsl_context_block(dsl_state, "Intersection(", args..., ")") do
        arg_values = dsl_expression.(args, Ref(dsl_state))
        if any(arg -> !isa(arg, AbstractVoxelGenerator), arg_values)
            error("Not all arguments to 'Intersection()' are voxel generators: [ ",
                  join(map(=>, args, typeof.(arg_values)), ", "),
                  " ]")
        end

        return VoxelIntersection(collect(AbstractVoxelGenerator, arg_values))
    end
end
dsl_copy(i::VoxelIntersection) = VoxelIntersection(map(dsl_copy, i.inputs))