cd(@__DIR__)

using Pkg
Pkg.activate(".")

# Enable some B+ asserts.
using Bplus
Bplus.Utilities.bp_utils_asserts_enabled() = true
Bplus.Math.bp_math_asserts_enabled() = true
Bplus.GL.bp_gl_asserts_enabled() = true

# Enable BpWorld asserts.
using BpWorld
BpWorld.bpworld_asserts_enabled() = true

# Run!
BpWorld.main()