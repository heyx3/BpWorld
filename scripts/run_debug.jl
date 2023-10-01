# Move to the Julia project folder, and activate this project.
cd(joinpath(@__DIR__, ".."))
using Pkg
Pkg.activate(".")

# Enable debug mode within some B+ modules.
using Bplus
Bplus.Utilities.bp_utils_asserts_enabled() = true
Bplus.Math.bp_math_asserts_enabled() = true
Bplus.GL.bp_gl_asserts_enabled() = true

# Enable debug mode within this project.
using BpWorld
BpWorld.Utils.bpworld_asserts_enabled() = true

# Run!
BpWorld.main()