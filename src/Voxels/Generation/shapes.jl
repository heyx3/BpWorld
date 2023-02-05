"A sphere whose coordinates are in UV space (0 is min voxel corner, 1 is max voxel corner)."
Base.@kwdef struct VoxelSphere <: AbstractVoxelGenerator
    center::v3f
    radius::Float32

    surface_thickness::Float32 = -0.1 # If set to a positive value, then
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


@bp_enum BoxModes filled surface edges corners

Base.@kwdef struct VoxelBox{TMode<:Val} <: AbstractVoxelGenerator
    area::Box3Df
    layer::VoxelElement
    invert::Bool = false
end
@inline VoxelBox(layer, area; mode=BoxModes.filled, kw...) = VoxelBox{Val{mode}}(
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