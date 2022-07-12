Base.@kwdef struct VoxelSphere <: AbstractVoxelGenerator
    center::v3f
    radius::Float32

    surface_thickness::Float32 = -0.1 # If set to a positive value, then
                                      #    only the surface is solid.

    layer::UInt8
    invert::Bool = false
end
#TODO: Pregenerate this sphere's voxel bounds, to early-exit on the math.
function generate(s::VoxelSphere, i::v3u, p::v3f)
    # Handle inversion.
    local inside_val::UInt8,
          outside_val::UInt8
    if s.invert
        inside_val = EMPTY_VOXEL
        outside_val = s.layer
    else
        inside_val = s.layer
        outside_val = EMPTY_VOXEL
    end

    # Calculate whether this position is inside or outside the sphere (or its surface).
    dist_sqr = vdist_sqr(p, s.center)
    if s.surface_thickness <= 0
        max_dist_sqr = s.radius * s.radius
        return (dist_sqr <= max_dist_sqr) ? inside_val : outside_val
    else
        return (abs(sqrt(dist_sqr) - s.radius) <= s.surface_thickness) ?
                   inside_val :
                   outside_val
    end
end


@bp_enum BoxModes filled surface edges corners

Base.@kwdef struct VoxelBox{TMode<:Val} <: AbstractVoxelGenerator
    area::Box3Df
    layer::UInt8
    invert::Bool = false
end
@inline VoxelBox(layer, area; mode=BoxModes.filled, kw...) = VoxelBox{Val{mode}}(
    layer=layer,
    area=area,
    kw...
)
box_mode(::VoxelBox{Val{T}}) where {T} = T
function prepare_generation(b::VoxelBox, grid_size::v3u)::NTuple{2, v3u}
    # Compute the min and max voxels covered by this box.
    voxel_scale = convert(v3f, grid_size)
    voxel_area = Box3Df(b.area.min * voxel_scale,
                        b.area.size * voxel_scale)
    voxel_min::v3f = voxel_area.min + @f32(0.5)
    voxel_max::v3f = max_inclusive(voxel_area) - @f32(0.5)
    
    to_bounds(f::Float32) = UInt32(floor(max(@f32(0), f)))
    return (map(to_bounds, voxel_min),
            map(to_bounds, voxel_max))
end
function generate(b::VoxelBox{Val{TMode}}, idx::v3u, p::v3f, bounds::NTuple{2, v3u}) where {TMode}
    # Handle inversion.
    local inside_val::UInt8,
          outside_val::UInt8
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

#TODO: More shapes (capsule, plane, disc, grid)