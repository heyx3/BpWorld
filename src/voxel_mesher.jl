const VoxelGrid = Array{Bool, 3}


"
A CPU representation of the data associated with each vertex of a voxel mesh.
Note that this internal representation uses 0-based counting.
"
struct VoxelVertex
    grid_idx::Vec3{UInt32} # This vertex sits at the min corner of this voxel cell.
    face_axis_and_dir::UInt8 # First 2 bits are the axis.
                             # Third bit is the direction (0 means -1, 1 means +1).
end
@inline VoxelVertex(grid_idx::Vec3{<:Integer}, face_axis::Integer, face_dir::Signed) = VoxelVertex(
    begin; @bpworld_assert(all(grid_idx > 0)); convert(v3u, grid_idx - 1); end,
    let axis = begin; @bpworld_assert(face_axis in   1:3  ); UInt8(  face_axis - 1   ); end,
        dir  = begin; @bpworld_assert(face_dir  in (-1, 1)); UInt8((face_dir + 1) ÷ 2); end
    #begin
        axis | (dir << 2)
    end
)
Base.show(io::IO, v::VoxelVertex) = print(io,
    "min=", v3i(v.grid_idx),
    "  face=", ('-', '+')[(v.face_axis_and_dir >> 2) + 1],
               ('X', 'Y', 'Z')[(v.face_axis_and_dir & 0x03) + 1]
)

"
Informtion about `VoxelVertex`, to be handed to the GPU.
Needs to be told which buffer the `VoxelVertex` data is coming from
    (given as its index in the `Mesh` object).
"
voxel_vertex_layout(buffer_idx::Int = 1) = [
    VertexAttribute(buffer_idx, 0, VertexData_UVector(3, UInt32)),
    VertexAttribute(buffer_idx, sizeof(fieldtype(VoxelVertex, :grid_idx)),
                                VertexData_UVector(1, UInt8))
]

"Calculates the vertices and indices needed to render the given voxel grid"
function calculate_mesh(grid::VoxelGrid)::Tuple{Vector{VoxelVertex}, Vector{UInt32}}
@inbounds begin
    grid_size = v3i(size(grid))

    #TODO: Use greedy meshing to speed up
    #TODO: Pre-allocate one big matrix to generate all the data within
    #TODO: Spread across threads (after switching to the matrix approach, to avoid interference between threads)
    vertices = Vector{VoxelVertex}()
    indices = Vector{UInt32}()
    function process_slice(axis::UInt8, dir::Int8, slice::Int32)
        axis2::Int = mod1(axis+1, 3)
        axis3::Int = mod1(axis+2, 3)

        for plane_idx::v2i in 1:v2i(grid_size[axis2], grid_size[axis3])
            voxel_idx = -one(v3i)
            @set! voxel_idx[axis] = slice
            @set! voxel_idx[axis2] = plane_idx.x
            @set! voxel_idx[axis3] = plane_idx.y

            # For each filled voxel, draw its boundary with empty neighbors.
            if !grid[voxel_idx]
                continue
            end

            neighbor_voxel_idx = voxel_idx
            @set! neighbor_voxel_idx[axis] += dir

            is_on_edge::Bool = !in(neighbor_voxel_idx, 1:grid_size)
            is_neighbor_free::Bool = is_on_edge || !grid[neighbor_voxel_idx]
            if is_neighbor_free
                @bpworld_assert(length(vertices) < (typemax(UInt32) - 4),
                                "Holy crap that's a lot of vertices")
                first_idx = UInt32(length(vertices))

                a = voxel_idx
                b = @set a[axis2] += 1
                c = @set b[axis3] += 1
                d = @set a[axis3] += 1

                push!(vertices, VoxelVertex.(
                    (a, b, c,   a, c, d),
                    Ref(axis), Ref(dir)
                )...)

                push!(indices,
                      first_idx, first_idx + 0x1, first_idx + 0x2,
                      first_idx, first_idx + 0x2, first_idx + 0x3)
            end
        end
    end
    for axis in UInt8(1):UInt8(3)
        for slice::Int32 in 1:grid_size[axis]
            for dir in Int8.((-1, +1))
                process_slice(axis, dir, slice)
            end
        end
    end

    return tuple(vertices, indices)
end # @inbounds
end