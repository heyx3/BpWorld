module Utils

using Setfield, Base.Threads,
      Suppressor, StructTypes, JSON3, CSyntax
using GLFW, CImGui,
      ImageIO, FileIO, ColorTypes, FixedPointNumbers, ImageTransformations,
      MacroTools
using Bplus,
      Bplus.Utilities, Bplus.Math, Bplus.GL,
      Bplus.BplusTools, Bplus.SceneTree, Bplus.Input
const ModernGLbp = Bplus.GL.ModernGLbp
#

# Allows the creation of multiple callbacks to run on program start, via the global list 'RUN_ON_INIT'
@decentralized_module_init

# Defines @bpworld_assert and @bpworld_debug.
# Recompile this project for debug mode by executing `BpWorld.Utils.bpworld_asserts_enabled() = true` at global scope.
@make_toggleable_asserts bpworld_


include("directories.jl")
include("general.jl")
include("shaders.jl")
include("textures.jl")


export @bpworld_assert, @bpworld_debug,
       @omit_type, @close_gl_resources,
       check_gl_logs,
       ROOT_PATH,
       VOXEL_LAYERS_PATH, ASSETS_PATH, SCENES_PATH,
       SCENES_EXTENSION,
       process_shader_contents, compile_shaders, compile_shader_files,
       pixel_converter, load_tex

end # module