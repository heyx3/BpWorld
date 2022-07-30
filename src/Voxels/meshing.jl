"
A CPU representation of the data associated with each vertex of a voxel mesh.
Note that this internal representation uses 0-based counting.
"
struct VoxelVertex
    # The vertex position is given as a voxel index; it will sit at that voxel's min corner.
    # For simplicity, the voxel grid starts at 0 and so the positions are unsigned.

    # The top bit of each voxel position is used to store
    #    which axis and direction the vertex's face is facing.
    # The XY bits indicate axis (from 0 - 2).
    # The Z bit indicates direction (0 means -1, 1 means +1).

    data::Vec{3, UInt32}
end
@inline function VoxelVertex(grid_idx::Vec3{<:Integer}, face_axis::Integer, face_dir::Signed)
    @bpworld_assert(all(grid_idx > 0), "Given a negative grid position!")
    @bpworld_assert(all(grid_idx < (typemax(UInt32) >> 1)),
                    "Grid position is too big to fit into the packed data format! ", grid_idx)
    @bpworld_assert(face_axis in 1:3, "Invalid axis: ", face_axis)
    @bpworld_assert(face_dir in (-1, +1), "Invalid direction: ", face_dir)

    face_bits = UInt8(face_axis - 1)
    dir_bits = UInt8((face_dir + 1) ÷ 2);
    bits::Vec{3, UInt8} = Vec(face_bits & 0x1,
                              face_bits >> 1,
                              dir_bits)

    return VoxelVertex(Vec{3, UInt32}() do i::Int
        UInt32(grid_idx[i]) | (UInt32(bits[i]) << 31)
    end)
end
unpack_vertex(v::VoxelVertex) = (
    voxel_idx = map(u -> u & 0x7fFFffFF, v.data),
    face_axis = Int((v.data[1] >> 31) | ((v.data[2] >> 31) << 1)),
    face_dir = (Int(v.data[3] >> 31) * 2) - 1
)
Base.show(io::IO, v::VoxelVertex) = let unpacked = unpack_vertex(v)
    print(io,
        "{min=", v3i(unpacked.voxel_idx),
        "  face=", ('-', '+')[1 + ((unpacked.face_dir + 1) ÷ 2)],
                   ('X', 'Y', 'Z')[1 + unpacked.face_axis],
        "}")
end

"
Informtion about `VoxelVertex`, to be handed to the GPU.
Needs to be told which buffer the `VoxelVertex` data is coming from
    (given as its index in the `Mesh` object).
"
voxel_vertex_layout(buffer_idx::Int = 1) = [
    VertexAttribute(buffer_idx, 0, VertexData_UVector(3, UInt32))
]


"A set of buffers that can be used to mesh voxels."
mutable struct VoxelMesher
    vertex_buffer::Vector{VoxelVertex}
    index_buffer::Vector{UInt32}
    @atomic n_vertices::Int
    @atomic n_indices::Int
end
VoxelMesher() = VoxelMesher(
    Vector{VoxelVertex}(), Vector{UInt32}(),
    0, 0
)

"Calculates the vertices and indices needed to render the given voxel layer in the given grid"
function calculate_mesh(grid::VoxelGrid, layer::UInt8, mesher::VoxelMesher)
    grid_size = v3i(size(grid))

    # Pre-size the array for the worst-case scenario: every other cube being solid.
    is_odd::v3b = map(iszero, grid_size % 2)
    worst_case_grid_size = v3i() do i::Int
        grid_size[i] + Int32(is_odd[i] ? 1 : 0)
    end
    n_worst_case_cubes::Int = prod(worst_case_grid_size) ÷ 2
    n_worst_case_faces::Int = n_worst_case_cubes * 6
    resize!(mesher.vertex_buffer, n_worst_case_faces * 4)
    resize!(mesher.index_buffer, n_worst_case_faces * 6)
    println("Max buffer size is updated to ",
            Base.format_bytes(sizeof(VoxelVertex) * length(mesher.vertex_buffer)), " for vertices and ",
            Base.format_bytes(sizeof(UInt32) * length(mesher.index_buffer)), " for indices")
    @bpworld_assert(length(mesher.vertex_buffer) <= typemax(UInt32),
                    "Holy crap that's a lot of vertices")

    # Split the work across threads/tasks; use atomics for lock-free insertion of mesh data.
    @atomic mesher.n_vertices = 0
    @atomic mesher.n_indices = 0
    function process_slice(axis::UInt8, dir::Int8, slice::Int32)
        axis2::Int = mod1(axis+1, 3)
        axis3::Int = mod1(axis+2, 3)

        min_plane_idx = one(v2i)
        max_plane_idx = v2i(@inbounds grid_size.data[axis2],
                            @inbounds grid_size.data[axis3])
        for plane_idx::v2i in min_plane_idx:max_plane_idx
            voxel_idx = -one(v3i)
            @inbounds begin
                @set! voxel_idx[axis] = slice
                @set! voxel_idx[axis2] = plane_idx.x
                @set! voxel_idx[axis3] = plane_idx.y
            end

            # For each filled voxel, draw its boundary with empty neighbors.
            if (grid[voxel_idx]) != layer
                continue
            end

            neighbor_voxel_idx = voxel_idx
            @inbounds(@set! neighbor_voxel_idx[axis] += dir)

            is_on_edge::Bool = !in(neighbor_voxel_idx, 1:grid_size)
            is_neighbor_free::Bool = is_on_edge || (@inbounds(grid[neighbor_voxel_idx]) == EMPTY_VOXEL)
            if is_neighbor_free
                a = voxel_idx
                @inbounds begin
                    b = @set a[axis2] += one(Int32)
                    c = @set b[axis3] += one(Int32)
                    d = @set a[axis3] += one(Int32)
                end

                # Insert vertices.
                last_vert_idx::Int = @atomic mesher.n_vertices += 4
                @bpworld_assert(last_vert_idx <= length(mesher.vertex_buffer))
                @inbounds setindex!.(
                    Ref(mesher.vertex_buffer),
                    VoxelVertex.(
                        (a, b, c, d),
                        Ref(axis), Ref(dir)
                    ),
                    tuple(last_vert_idx - 3,
                          last_vert_idx - 2,
                          last_vert_idx - 1,
                          last_vert_idx - 0),
                )

                # Insert indices.
                last_indice_idx::Int = @atomic mesher.n_indices += 6
                @bpworld_assert(last_indice_idx <= length(mesher.index_buffer))
                @inbounds setindex!.(
                    Ref(mesher.index_buffer),
                    tuple(
                        # Remember, on the GPU they will be 0-based indices
                        last_vert_idx - 4, last_vert_idx - 3, last_vert_idx - 2,
                        last_vert_idx - 4, last_vert_idx - 2, last_vert_idx - 1
                    ),
                    tuple(
                        last_indice_idx - 5, last_indice_idx - 4, last_indice_idx - 3,
                        last_indice_idx - 2, last_indice_idx - 1, last_indice_idx
                    )
                )
            end
        end
    end

    # Dispatch a thread for every X, Y, and Z slice.
    @threads for i in 1:sum(grid_size)
        # Unpack the counter into a slice and its axis.
        (axis, slice) = if i > (grid_size[1] + grid_size[2])
            (UInt8(3), Int32(i - grid_size[1] - grid_size[2]))
        elseif i > grid_size[2]
            (UInt8(2), Int32(i - grid_size[1]))
        else
            (UInt8(1), Int32(i))
        end
        # Process both faces on this slice/axis.
        for dir in Int8.((-1, +1))
            process_slice(axis, dir, slice)
        end
    end

    return nothing
end