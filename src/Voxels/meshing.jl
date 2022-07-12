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
        "min=", v3i(unpacked.voxel_idx),
        "  face=", ('-', '+')[(unpacked_face.dir + 1) / 2],
                   ('X', 'Y', 'Z')[unpacked_face.axis])
end

"
Informtion about `VoxelVertex`, to be handed to the GPU.
Needs to be told which buffer the `VoxelVertex` data is coming from
    (given as its index in the `Mesh` object).
"
voxel_vertex_layout(buffer_idx::Int = 1) = [
    VertexAttribute(buffer_idx, 0, VertexData_UVector(3, UInt32))
]

"Calculates the vertices and indices needed to render the given voxel layer in the given grid"
function calculate_mesh(grid::VoxelGrid, layer::UInt8)::Tuple{Vector{VoxelVertex}, Vector{UInt32}}
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
            if grid[voxel_idx] != layer
                continue
            end

            neighbor_voxel_idx = voxel_idx
            @set! neighbor_voxel_idx[axis] += dir

            is_on_edge::Bool = !in(neighbor_voxel_idx, 1:grid_size)
            is_neighbor_free::Bool = is_on_edge || (grid[neighbor_voxel_idx] == EMPTY_VOXEL)
            if is_neighbor_free
                @bpworld_assert(length(vertices) < (typemax(UInt32) - 4),
                                "Holy crap that's a lot of vertices")
                first_idx = UInt32(length(vertices))

                a = voxel_idx
                b = @set a[axis2] += one(Int32)
                c = @set b[axis3] += one(Int32)
                d = @set a[axis3] += one(Int32)

                push!(vertices, VoxelVertex.(
                    (a, b, c, d),
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
end # calculate_mesh()