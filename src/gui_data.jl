# The GUI is architected with two types for each part of the GUI:
#  1. The "data", representing core important information.
#       This struct is saved/loaded when the program quits/restarts.
#  2. The "state", representing internal state when editing the "data".

#TODO: Put into its own module

const GuiVec2 = CImGui.LibCImGui.ImVec2
const GuiVec4 = CImGui.LibCImGui.ImVec4
const GuiColor = CImGui.LibCImGui.ImColor


abstract type GuiData end
abstract type GuiState end

"Spins up an initial gui state for some data."
init_gui_state(gui_data::GuiData)::GuiState = error("No defined state for ", typeof(gui_data), " gui")



"All information needed to describe the sun"
Base.@kwdef mutable struct SunData <: GuiData
    dir::v3f = vnorm(v3f(1, 1, -1))
    color::vRGBf = vRGBf(1, 1, 1)
end
StructTypes.StructType(::Type{SunData}) = StructTypes.Mutable()

Base.@kwdef mutable struct SunDataGui <: GuiState
    color_picker_is_open::Bool = false
    fallback_yaw::Ref{Float32} = Ref(@f32(0))
end
init_gui_state(::SunData) = SunDataGui()
function gui_sun(sun::SunData, state::SunDataGui, id = nothing)
    if exists(id)
        CImGui.PushID(id)
    end

    sun.dir = gui_spherical_vector(
        "Sun Dir", sun.dir,
        stays_normalized = true,
        fallback_yaw = state.fallback_yaw
    )
    state.color_picker_is_open = @c CImGui.ColorEdit3("Sun color", &sun.color)

    if exists(id)
        CImGui.PopID()
    end
end


"All information needed to describe fog"
Base.@kwdef mutable struct FogData <: GuiData
    density::Float32 = @f32(0.0084)
    dropoff::Float32 = @f32(1)
    height_offset::Float32 = @f32(430)
    height_scale::Float32 = @f32(0.01)
    color::vRGBf = vRGBf(0.3, 0.3, 1.0)
end
StructTypes.StructType(::Type{FogData}) = StructTypes.Mutable()

Base.@kwdef mutable struct FogDataGui <: GuiState
    color_state::Bool = false
end
init_gui_state(::FogData) = FogDataGui()
function gui_fog(fog::FogData, state::FogDataGui, id = nothing)
    if exists(id)
        CImGui.PushID(id)
    end

    @c CImGui.DragFloat(
        "Density", &fog.density, @f32(0.0001),
        @f32(0), @f32(0.1),
        "%.5f", @f32(1)
    )
    @c CImGui.DragFloat(
        "Dropoff", &fog.dropoff, @f32(0.03),
        @f32(0), @f32(10),
        "%.3f", @f32(1)
    )
    gui_with_item_width(100) do
        CImGui.Text("Height")
        CImGui.SameLine()
        @c CImGui.DragFloat(
            "Offset", &fog.height_offset, @f32(3.5),
            @f32(0), @f32(0),
            "%.0f", @f32(1)
        )
        CImGui.SameLine()
        @c CImGui.DragFloat(
            "Scale", &fog.height_scale, @f32(0.0005),
            @f32(0), @f32(1),
            "%.4f", @f32(1)
        )
    end
    state.color_state = @c CImGui.ColorEdit3(
        "Color", &fog.color,
        CImGui.ImGuiColorEditFlags_Float |
            CImGui.ImGuiColorEditFlags_DisplayHSV |
            CImGui.ImGuiColorEditFlags_InputRGB
    )

    if exists(id)
        CImGui.PopID()
    end
end

"All information needed to drive the scene editor gui"
Base.@kwdef mutable struct SceneData <:GuiData
    contents::String = """
# Add a box. Later we will use the inflated box to mask out some terrain.
box_min = { 0.065 }.xxx
box_max = { 0.435 }.xxx
box = Box(
    layer = 0x2,
    min = box_min,
    max = box_max
)
box_inflated = Box(
    layer = 0x2,
    min = box_min / 1.3,
    max = box_max * 1.3
)

# Add a sphere. Later we will use the inflated sphere to mask out some terrain.
sphere_radius = 0.3
sphere_center = { { 0.25 }.xx, 0.75 }
sphere = Sphere(
    layer = 0x3,
    center = sphere_center,
    radius = sphere_radius
)
sphere_inflated = Sphere(
    layer = 0x3,
    center = sphere_center,
    radius = sphere_radius * 1.3
)

# Generate some Perlin noise "terrain".
terrain = BinaryField(
    layer = 0x1,
    field = 0.2 + (0.5 * perlin(pos * 5.0))
)
# Remove any terrain near the box or sphere.
terrain = Difference(
    terrain,
    [ box_inflated, sphere_inflated ]
)

# Combine the terrain with the box and sphere.
return Union(box, sphere, terrain)"""

    refresh_wait_interval_seconds::Float64 = 3.0
end
StructTypes.StructType(::Type{SceneData}) = StructTypes.Mutable()

@bp_enum SceneState ready compiling error
Base.@kwdef mutable struct SceneDataGui <: GuiState
    scene_buffer::Vector{UInt8}
    scene_changed::Bool = true
    last_update_time::UInt64 = 0
    parse_error_msg::Optional{String} = nothing
    parse_state::E_SceneState = SceneState.ready
end
function init_gui_state(data::SceneData)
    buffer = Vector{UInt8}(data.contents)

    # Make the buffer at least 4096 bytes, and leave room for a null terminator at the end.
    first_unused_buffer_idx = (length(data.contents) + 1) * sizeof(Char)
    resize!(buffer, max(first_unused_buffer_idx + sizeof(Char) - 1, 4096))

    # Fill the unused bytes with null terminators.
    buffer[first_unused_buffer_idx:end] .= zero(UInt8)

    return SceneDataGui(scene_buffer = buffer)
end

function gui_scene(func_try_compile_scene, # (String) -> Optional{String} : returns the error message if it failed
                   scene::SceneData, state::SceneDataGui, id = nothing)
    if exists(id)
        CImGui.PushID(id)
    end

    #TODO: Figure out how to use the "resize" callback
    just_changed::Bool = @c CImGui.InputTextMultiline(
        "Code",
        &state.scene_buffer[0], length(state.scene_buffer),
        (0, 650),
        CImGui.ImGuiInputTextFlags_AllowTabInput
    )
    state.scene_changed |= just_changed
    if (state.parse_state == SceneState.ready) && state.scene_changed
        state.parse_state = SceneState.compiling
    end

    # After enough time, tell the world to try rendering this new scene.
    if just_changed
        state.last_update_time = time_ns()
    elseif state.scene_changed &&
           ((time_ns() - state.last_update_time) / 1e9) > scene.refresh_wait_interval_seconds
    #begin
        last_idx = findfirst(iszero, state.scene_buffer) - 1
        scene.contents = String(@view state.scene_buffer[1:last_idx])
        state.parse_error_msg = func_try_compile_scene(scene.contents)
        # gui.scene_parse_error_msg = start_new_scene(world, scene_str)

        state.scene_changed = false
        state.parse_state = exists(state.parse_error_msg) ? SceneState.error : SceneState.ready
    end

    CImGui.Spacing()

    # Draw the state of the scene compiler.
    (color, text) = if state.parse_state == SceneState.ready
                        (GuiVec4(0, 1, 0, 1), "Compiled")
                    elseif state.parse_state == SceneState.compiling
                        (GuiVec4(1, 1, 0, 1), "Compiling...")
                    elseif state.parse_state == SceneState.error
                        (GuiVec4(1, 0, 0, 1), state.parse_error_msg)
                    else
                        error(state.parse_state)
                    end
    CImGui.TextColored(color, text)

    if exists(id)
        CImGui.PopID()
    end
end