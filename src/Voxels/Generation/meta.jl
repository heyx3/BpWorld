"
Mixes multiple sources of voxel data together.
The voxel value is chosen based on a priority ranking -- the highest-priority value is chosen.
If voxel layers have the same priority, then selection prioritizes the later children.
"
struct VoxelUnion{TChildrenTuple<:Tuple} <: AbstractVoxelGenerator
    priorities::Vector{Float32} # For each voxel layer, how important it is
    empty_priority::Float32 # Defaults to -Inf
    children::TChildrenTuple # A statically-typed tuple of each generator in this union
end
@inline function VoxelUnion(priorities::AbstractVector{<:Real},
                            children...;
                            empty_priority::Real = -Inf32)
    return VoxelUnion{typeof(children)}(
        map(Float32, priorities),
        convert(Float32, empty_priority),
        children
    )
end
prepare_generation(u::VoxelUnion, grid_size::v3u) = tuple((
    prepare_generation(child, grid_size)
        for child in u.children
)...)
function generate(u::VoxelUnion, i::v3u, p::v3f, prep_data::Tuple)
    # Get the value for each child.
    #TODO: Check that this loop gets unrolled. If not, we'll probably need a @generated instead
    children_values = tuple((
        generate(child, i, p, prep)
          for (child, prep) in zip(u.children, prep_data)
    )...)

    # Pick the highest-priority value.
    return reduce(children_values, init=zero(UInt8)) do a, b
        p_a = (a == EMPTY_VOXEL) ? u.empty_priority : u.priorities[a]
        p_b = (b == EMPTY_VOXEL) ? u.empty_priority : u.priorities[b]
        return (p_b < p_a) ? a : b
    end
end


"Outputs the value of a generator, *if* other generators would output nothing there."
struct VoxelDifference{TMain<:AbstractVoxelGenerator, TGeneratorTuple<:Tuple} <: AbstractVoxelGenerator
    main::TMain
    subtractors::TGeneratorTuple
    to_ignore::Set{UInt8} # If the 'subtractors' would output these voxel layers,
                          #    that's ignored.
end
VoxelDifference(main, to_subtract...; to_ignore = Set{UInt8}()) = VoxelDifference{typeof(main), typeof(to_subtract)}(main, to_subtract, to_ignore)
VoxelDifference(main, to_subtract::Tuple, to_ignore = Set{UInt8}()) = VoxelDifference{typeof(main), typeof(to_subtract)}(main, to_subtract, to_ignore)
prepare_generation(u::VoxelDifference, grid_size::v3u) = tuple((
    prepare_generation(child, grid_size)
        for child in tuple(u.main, u.subtractors...)
)...)
@generated function generate( u::VoxelDifference{M, S},
                              i::v3u, p::v3f,
                              prep_data::P
                            ) where {M, S<:Tuple, P<:Tuple}
    child_check_statements = [ ]
    for subtractor_idx in 1:length(S.parameters)
        child_var = Symbol(:child_val_, subtractor_idx)
        push!(child_check_statements, quote
            $child_var = generate(u.subtractors[$subtractor_idx], i, p,
                                  # Remember the first index of 'prep_data' is for 'u.main'
                                  prep_data[1 + $subtractor_idx])
            if $child_var != EMPTY_VOXEL && !in(u.to_ignore, $child_var)
                return EMPTY_VOXEL
            end
        end)
    end

    return quote
        $(child_check_statements...)
        return generate(u.main, i, p, prep_data[1])
    end
end


"
Outputs the intersection of several generators.
Voxels are only set to something non-empty when all generators would output the same value.
"
struct VoxelIntersection{TChildrenTuple<:Tuple} <: AbstractVoxelGenerator
    children::TChildrenTuple # A statically-typed tuple of each generator in this operation.
end
VoxelIntersection(children...) = VoxelIntersection{typeof(children)}(children)
prepare_generation(vi::VoxelIntersection, grid_size::v3u) = tuple((
    prepare_generation(child, grid_size)
        for child in vi.children
)...)
@generated function generate( u::VoxelIntersection{C},
                              i::v3u, p::v3f,
                              prep_data::P
                            ) where {C<:Tuple, P<:Tuple}
    output = quote end

    # Grab the first child's value.
    # Early-exit if the value is empty.
    append!(output.args, [
        :( chosen::UInt8 = generate(u.children[1], i, p, prep_data[1]) ),
        :(
            if chosen == EMPTY_VOXEL
                return EMPTY_VOXEL
            end
        )
    ])

    # Check that each child matches with it, otherwise return empty space.
    for child_idx in 2:length(C.parameters)
        push!(output.args, :(
            if chosen != generate(u.children[$child_idx], i, p, prep_data[$child_idx])
                return EMPTY_VOXEL
            end
        ))
    end

    # All children match up, so we canuse this value.
    push!(output.args, :( return chosen ))
    
    return output
end