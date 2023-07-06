using Test

using Bplus
using Bplus.Utilities, Bplus.Math

using BpWorld
using BpWorld.Utils, BpWorld.Voxels, BpWorld.Voxels.Generation


# Implement equality for voxel generators, for testing purposes.
function Base.:(==)(a::AbstractVoxelGenerator, b::AbstractVoxelGenerator)::Bool
    if typeof(a) != typeof(b)
        return false
    else
        return all(getfield(a, f) == getfield(b, f) for f in fieldnames(typeof(a)))
    end
end

macro test_dsl(description, expected, expr, exact_match...)
    exact_match = isempty(exact_match) ? true : false
    expr_expr = Expr(:quote, expr)
    return quote
        expr = $expr_expr
        actual = Base.isexpr(expr, :block) ? eval_dsl(expr) : dsl_expression(expr, DslState())
        matches = $exact_match ? (actual === $expected) : (actual == $expected)
        if matches
            @test true
        elseif actual isa DslError
            @error "Expected $($expected), got \"$(sprint(showerror, actual))\". From: $expr"
            @test false
        else
            @error "Expected $($expected), got $actual. From: $expr"
            @test false
        end
    end
end


@testset "Main" begin
    @testset "Voxel DSL expressions" begin
        @test_dsl "Literals" 0x1 0x1
        @test_dsl "Literals 2" 0.123f0 0.123f0
        @test_dsl "Vector Literals" Vec(1, 2, 3, 2, 1) { 1, 2, 3, 2, 1 }
        @test_dsl "Vector Literals 2" Vec(false, true, true) { false, true, true }

        @test_dsl "Vector appending" Vec(1, 2, 3, 4, 5, 6) { 1, { 2, 3 }, 4, 5, { 6 } }
        @test_dsl "Vector swizzling" Vec(1, 1, 3, 2, 4) { 1, 2, 3, 4 }.xxzyw

        @test_dsl "Converting literals" 0x1 UInt8(1.0)
        @test_dsl "Converting literals 2" 35.0f0 Float32(35)
        @test_dsl "Converting vector literals" Vec(3, 4) Int({ 3.0, 4.0 })
        @test_dsl "Converting vector literals 2" Vec(4.0, 1.0, -30.0) Float64({ 4, 1, -Int8(30)})
        @test_dsl "Converting vector literals to 'Float'" v4f(1, 2, 3, 4) Float({ 1, 2, 3, 4 })

        @test_dsl "Simple expressions" (1 + 3 + 5) (1 + 3 + 5)
        @test_dsl "Simple expressions 2" (1.0f0 + 3.0f0 + 5.0f0) (1.0f0 + 3.0f0 + 5.0f0)
        @test_dsl "Simple expressions 3" sin(1.0f0) sin(1.0f0)

        @test_dsl "Simple vector expressions" map(sin, Vec(3, 4, 5)) sin({ 3, 4, 5 })
        @test_dsl("Simple vector expressions 2",
                  vcross(Vec(1, 2, 3), Vec(-4, 5, 0)),
                  { 1, 2, 3 } × { -4, 5, 0 })

        @test_dsl("Nested simple expressions",
                  (1 + (2 * (4 / 7))),
                  (1 + (2 * (4 / 7))))
        @test_dsl("Nested simple expressions 2",
                  floor(sin(45.3f0) / atan(2.4136f0)),
                  floor(sin(45.3f0) / atan(2.4136f0)))
        @test_dsl("Nested vector expressions",
                  vdot(map(sin, Vec(1.0, 2.0, 4.0)) *
                         Vec(3, -4, 10),
                       vappend(-1, 2.5, -3)),
                  (sin({ 1.0, 2.0, 4.0 }) * { 3, -4, 10 }) ∘ { -1, 2.5, -3 })

        @test_dsl("Boolean expressions",
                  Vec((true & false) ⊻ true,
                      (false & true) ⊻ false,
                      (true & true) ⊻ true),
                  ({ true, false, true } & { false, true, true }) ⊻ { true, false, true })

        @test_dsl("Trivial copy()", 5, copy(5))
        @test_dsl("Trivial copy() 2", Vec(2, 3, 4, 5), copy({ 2, 3, 4, 5 }))
        @test_dsl("Trivial copy() 3", 7, copy(2 + 5))
        @test_dsl("copy() a generator with no changes",
                  VoxelSphere(center=v3f(2, 3, 4), radius=3, layer=0x7f),
                  copy(Sphere(center={2, 3, 4},
                              radius=3,
                              layer=0x7f)))
        @test_dsl("copy() a generator with no changes 2",
                  VoxelBox(BoxModes.edges,
                           area=Box((min=v3f(1, 2, 3), max=v3f(4, 6, 8))),
                           layer=0xb0),
                  copy(Box(layer=0xb0,
                           min={1, 2, 3},
                           max={4, 6, 8},
                           mode=edges)))
        @test_dsl("copy() a nested generator with no changes",
                  VoxelUnion([ VoxelBox(BoxModes.filled,
                                        area=Box((min=v3f(1, 2, 3), max=v3f(4, 6, 8))),
                                        layer=0xb0),
                               VoxelSphere(center=v3f(2, 3, 4),
                                           radius=3,
                                           layer=0x7f) ]),
                  copy(Union(
                      Box(layer=0xb0,
                          min={1, 2, 3},
                          max={4, 6, 8},
                          mode=filled),
                      Sphere(center={2, 3, 4},
                             radius=3,
                             layer=0x7f)
                  )),
                  false)

        @test_dsl("copy() with simple changes",
                  VoxelSphere(center=v3f(5, 3, 1), radius=30, layer=0xab),
                  copy(Sphere(center={5, 3, 1}, radius=10, layer=0x45),
                       radius=30,
                       layer=0xab))
        @test_dsl("copy() with simple changes 2",
                  VoxelSphere(center=v3f(5, 3, 1), radius=10, layer=0x45),
                  copy(Sphere(center={1, 5, 3}, radius=10, layer=0x45),
                       center={5, 3, 1}))
        @test_dsl("copy() with relative modifications",
                  VoxelSphere(center=(v3f(5, 6, 7) / 2), radius=(10-3.5), layer=(0x45 + 0x0a)),
                  copy(Sphere(center={5, 6, 7}, radius=10, layer=0x45),
                       center /= 2,
                       radius -= 3.5,
                       layer += 0x0a))
        @test_dsl("copy() box's special properties (min)",
                  VoxelBox(
                      area=Box((min=v3f(3, 3, 3), max=v3f(13, 15, 17))),
                      layer = 0xbe,
                      invert = false
                  ),
                  copy(Box(min={10, 11, 12}, max={13, 15, 17},
                           invert = true,
                           layer=0xff),
                       min=3,
                       layer = 0xbe,
                       invert ⊻= true))
        @test_dsl("copy() box's special properties (max, mode)",
                  VoxelBox(
                      BoxModes.corners,
                      area=Box((min=v3f(10, 11, 12), max=v3f(3, 3, 3))),
                      layer = 0x0
                  ),
                  copy(Box(min={10, 11, 12}, size={13, 15, 17}, layer=0),
                       max=3,
                       mode=corners))
        @test_dsl("copy() box's special properties (center, size)",
                  VoxelBox(
                      area=Box((center=v3f(-4, -5, -100), size=v3f(13, 15, 17))),
                      layer = 0x0
                  ),
                  copy(Box(min={10, 11, 12}, max={13, 15, 17}, layer=0),
                       center={-4, -5, -100},
                       size={13, 15, 17}))
    end

    @testset "Making Voxel Generators with the DSL" begin
        function test_generator(to_do, generator_expr, description...)
            generator = dsl_expression(generator_expr, DslState())
            if generator isa Vector
                @test false == string("Error making ", description..., ": ", generator...)
            else
                to_do(generator)
            end
        end

        test_generator(:( BinaryField(layer = 0x5, field = pos.x) ), "BinaryField") do g
            @test length(g.layers) == 1
            @test g.layers[1][1] == 0x5
            @test g.layers[1][2] isa
                    Bplus.Fields.SwizzleField{3, 1, Float32, Tuple{1},
                                              Bplus.Fields.PosField{3, Float32}}
        end
        test_generator(:( Sphere(center={1, 2, 3}, radius=5.7, layer=0x4) ), "Basic sphere") do g
            @test g.center === v3f(1, 2, 3)
            @test g.radius === convert(Float32, 5.7)
            @test g.layer === 0x4
            @test !g.invert
            @test g.surface_thickness == 0
        end
        test_generator(:( Sphere(center={3, 1, 2}, radius=15.7, layer=0xF1, invert=true, thickness=0.1) ), "Complex sphere") do g
            @test g.center === v3f(3, 1, 2)
            @test g.radius === convert(Float32, 15.7)
            @test g.layer === 0xF1
            @test g.invert
            @test g.surface_thickness === convert(Float32, 0.1)
        end
        test_generator(:( Box(layer=0x00, min={4, 5, 6}, max={7, 8, 9}) ), "Min/max box") do g
            @test g.layer === 0x00
            @test g.area === Box((min=v3f(4, 5, 6), max=v3f(7, 8, 9)))
            @test !g.invert
            @test BpWorld.Voxels.Generation.box_mode(g) ==
                      BpWorld.Voxels.Generation.BoxModes.filled
        end
        test_generator(:( Box(layer=0xAB, min={4.5, 3.7, 20}, size={99, 98, 97}) ), "Min/size box") do g
            @test g.layer === 0xAB
            @test g.area === Box((min=v3f(4.5, 3.7, 20), size=v3f(99, 98, 97)))
            @test !g.invert
            @test BpWorld.Voxels.Generation.box_mode(g) ==
                      BpWorld.Voxels.Generation.BoxModes.filled
        end
        test_generator(:( Box(layer=0x43, max={4.5, 3.7, 20}, size={99, 98, 97}, invert=(true|false), mode=edges) ), "Inverted max/size box") do g
            @test g.layer === 0x43
            @test g.area === Box((max=v3f(4.5, 3.7, 20), size=v3f(99, 98, 97)))
            @test g.invert
            @test BpWorld.Voxels.Generation.box_mode(g) ==
                      BpWorld.Voxels.Generation.BoxModes.edges
        end
        test_generator(:( Union(
                            Box(layer=0x02, min={4, 5, 6}, max={5, 7, 9}),
                            Sphere(layer=0x56, center={1, 2, 3}, radius=10.12345)
                        )), "Union") do g
            @test g isa VoxelUnion
            @test length(g.inputs) == 2
            @test g.inputs[1] isa VoxelBox
            @test g.inputs[1].layer == 0x02
            @test g.inputs[1].area == Box((min=v3f(4, 5, 6), max=v3f(5, 7, 9)))
            @test !g.inputs[1].invert
            @test BpWorld.Voxels.Generation.box_mode(g.inputs[1]) ==
                      BpWorld.Voxels.Generation.BoxModes.filled
            @test g.inputs[2] isa VoxelSphere
            @test g.inputs[2].layer == 0x56
            @test g.inputs[2].center == v3f(1, 2, 3)
            @test g.inputs[2].radius == convert(Float32, 10.12345)
            @test !g.inputs[2].invert
        end
        test_generator(:( Intersection(
                            Box(layer=0x02, size={4, 5, 6}, max={5, 7, 9}),
                            Sphere(layer=0x56, center={1, 2, 3}, radius=10.12345)
                        )), "Intersection") do g
            @test g isa VoxelIntersection
            @test length(g.inputs) == 2
            @test g.inputs[1] isa VoxelBox
            @test g.inputs[1].layer == 0x02
            @test g.inputs[1].area == Box((max=v3f(5, 7, 9), size=v3f(4, 5, 6)))
            @test !g.inputs[1].invert
            @test BpWorld.Voxels.Generation.box_mode(g.inputs[1]) ==
                      BpWorld.Voxels.Generation.BoxModes.filled
            @test g.inputs[2] isa VoxelSphere
            @test g.inputs[2].layer == 0x56
            @test g.inputs[2].center == v3f(1, 2, 3)
            @test g.inputs[2].radius == convert(Float32, 10.12345)
            @test !g.inputs[2].invert
        end
        test_generator(:( Difference(
                            Box(layer=0x02, min={4, 5, 6}, max={5, 7, 9}),
                            [ Sphere(layer=0x56, center={1, 2, 3}, radius=10.12345) ]
                        )), "Difference") do g
            @test g isa VoxelDifference
            @test g.main isa VoxelBox
            @test g.main.layer == 0x02
            @test g.main.area == Box((min=v3f(4, 5, 6), max=v3f(5, 7, 9)))
            @test !g.main.invert
            @test BpWorld.Voxels.Generation.box_mode(g.main) ==
                      BpWorld.Voxels.Generation.BoxModes.filled
            @test length(g.subtractors) == 1
            @test g.subtractors[1] isa VoxelSphere
            @test g.subtractors[1].layer == 0x56
            @test g.subtractors[1].center == v3f(1, 2, 3)
            @test g.subtractors[1].radius == convert(Float32, 10.12345)
        end
        test_generator(:( Difference(
                            Box(layer=0x02, min={4, 5, 6}, max={5, 7, 9}),
                            [ Sphere(layer=0x56, center={1, 2, 3}, radius=10.12345) ],
                            ignore = { 3, 4, 27 }
                        )), "Difference with ignore set") do g
            @test g isa VoxelDifference
            @test g.main isa VoxelBox
            @test g.main.layer == 0x02
            @test g.main.area == Box((min=v3f(4, 5, 6), max=v3f(5, 7, 9)))
            @test !g.main.invert
            @test BpWorld.Voxels.Generation.box_mode(g.main) ==
                      BpWorld.Voxels.Generation.BoxModes.filled
            @test length(g.subtractors) == 1
            @test g.subtractors[1] isa VoxelSphere
            @test g.subtractors[1].layer == 0x56
            @test g.subtractors[1].center == v3f(1, 2, 3)
            @test g.subtractors[1].radius == convert(Float32, 10.12345)
            @test g.to_ignore == Set{UInt8}([ 3, 4, 27 ])
        end
    end

    @testset "Voxel DSL Full sequences" begin
        @test_dsl "Basic sequence" ((5 + Vec(1.0, 2.0)) ^ Vec(1.0, 2.0)) begin
            x = 5
            y = { 1.0, 2.0 }
            z = (x + y)
            return z ^ y
        end

        @test_dsl("Overwriting variables",
                  5,
                  begin
                      a = 3
                      a = 4
                      a = 5
                      return a
                  end)

        @test_dsl("Using a trivial custom function",
                  40,
                  begin
                    @abc() = return 30
                    return abc() + 10
                  end)
        @test_dsl("Using a 3-param custom function, with default 3rd param",
                  (3+4) * 2.5,
                  begin
                    @abc(a, b, c=2.5) = return (a+b)*c
                    return abc(3, 4)
                  end)
        @test_dsl("Using a 3-param custom function, with non-default 3rd param",
                  (3+4) * 10.34,
                  begin
                    @abc(a, b, c=2.5) = return (a+b)*c
                    return abc(3, 4, 10.34)
                  end)

        @test_dsl("Using nested functions",
                  8 * (20 - 13.5),
                  begin
                      def = 8

                      @abc() = begin
                        @def(d) = return 20 - d
                        return def(13.5)
                      end

                      return def * abc()
                  end)
        @test_dsl("Using nested scopes",
                  8 - 13.5,
                  begin
                      def = 8

                      @abc() = begin
                        @ghi(g) = return def - g
                        return ghi(13.5)
                      end

                      return abc()
                  end)

        @test_dsl("Overwriting variables in different scopes",
                  4,
                  begin
                      a = 4
                      @b() = begin
                          a = 5
                          return a
                      end
                      bb = b()
                      return a
                  end)

        @test_dsl("Complex scope relationships",
                  4 + ((6/3.5) * 2),
                  begin
                      a = 2
                      b = 3.5
                      @cc(i) = return i*a
                      @dd(i) = return i/b
                      @ee() = begin
                          a = 4
                          i = 200
                          return a + cc(dd(6))
                      end
                      return ee()
                  end)

        @test_dsl("Trivial repeat() loop",
                  [1, 2, 3],
                  repeat(1:3) do i
                      return i
                  end,
                  false)
        @test_dsl("Repeat() with scope overwriting",
                  [ (2*2 + 7.5) * 5,
                    (3*2 + 7.5) * 5,
                    (4*2 + 7.5) * 5,
                    (5*2 + 7.5) * 5 ],
                  begin
                      d = 5
                      b = 7.5
                      @cc(i2) = return i2*d
                      return repeat(2:5) do i
                          d = i*2
                          a = d + b
                          return cc(a)
                      end
                  end,
                  false)
        #TODO: Test repeat() with VecI ranges
    end

    #TODO: Test that voxels are generated correctly.
end