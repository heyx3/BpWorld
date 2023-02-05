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


"
Outputs the intersection of several generators.
Voxels are only set to something non-empty when all generators would output the same value.
"
struct VoxelIntersection <: AbstractVoxelGenerator
    inputs::AbstractVector{AbstractVoxelGenerator}

    "There must be at least one voxel generator as input."
    VoxelIntersection(first_input::AbstractVoxelGenerator, rest_inputs::AbstractVoxelGenerator...) =
        new([ first_input, rest_inputs... ])
end

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