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

"All information needed to describe the loaded scene file"
Base.@kwdef mutable struct SceneData <:GuiData
    new_file_name::String = "my_new_scene"
    current_file_path::Optional{Vector{String}} = nothing

    contents::String = replace("""
        #layer 1 rocks/rocks.json
        terrain = BinaryField(
            layer = 0x1,
            field = 0.2 + (0.5 * perlin(pos * 5.0))
        )
        
        #layer 2 scifi/blue.json
        box = Box(
            layer = 0x2,
            min = { 0.065, 0.065, 0.065 },
            max = { 0.435 }.xxx,
            mode = edges
        )
        
        #layer 3 scifi/red.json
        sphere = Sphere(
            layer = 0x3,
            center = { {0.25}.xx, 0.75 },
            radius = 0.3
        )
        
        # Remove any terrain near the box or sphere.
        box_inflated = copy(box,
            size *= 1.3,
            mode = filled
        )
        sphere_inflated = copy(sphere,
            radius *= 1.3
        )
        terrain = Difference(
            terrain,
            [ box_inflated, sphere_inflated ]
        )
        
        return Union(box, sphere, terrain)""", "        "=>"")

    refresh_wait_interval_seconds::Float64 = 3.0
end
StructTypes.StructType(::Type{SceneData}) = StructTypes.Mutable()

"A 'leaf' node in the file tree."
struct SceneFile end
"A non-leaf node in the file tree."
mutable struct SceneFolder
    contents::Dict{String, Union{SceneFile, SceneFolder}}
    SceneFolder(contents = Dict{String, Union{SceneFile, SceneFolder}}()) = new(contents)
    function SceneFolder(path::AbstractString)
        # Map the contents of this directory.
        return SceneFolder(Dict(Iterators.map(readdir(path, sort=false)) do name::AbstractString
            if isfile(joinpath(path, name))
                return name => SceneFile()
            else
                return name => SceneFolder(joinpath(path, name))
            end
        end))
    end
end

@bp_enum SceneState ready compiling error
Base.@kwdef mutable struct SceneDataGui <: GuiState
    scene_buffer::Vector{UInt8}
    new_name_buffer::Vector{UInt8}

    scene_changed::Bool = true
    last_update_time::UInt64 = 0
    parse_error_msg::Optional{String} = nothing
    parse_state::E_SceneState = SceneState.ready

    scene_folder_tree::SceneFolder = SceneFolder(SCENES_PATH)
end
function init_gui_state(data::SceneData)
    scene_buffer = Vector{UInt8}(data.contents)
    new_name_buffer = Vector{UInt8}(data.new_file_name)

    # Copy the initial string data into their buffers,
    #    give the buffers a minimum size,
    #    and fill the extra space with null terminators (ensuring at least one exists).
    # Give the buffers a minimum size, and fill with null terminators at the end.
    for (buff, min_size) in [ (scene_buffer, 4096),
                              (new_name_buffer, 256) ]
        first_nullterm_idx = length(buff) + 1
        resize!(buff, max(first_nullterm_idx, min_size))
        buff[first_nullterm_idx:end] .= zero(UInt8)
    end

    return SceneDataGui(scene_buffer = scene_buffer,
                        new_name_buffer = new_name_buffer)
end

function gui_scene(func_try_compile_scene, # (String) -> Optional{String} : returns the error message if it failed
                   scene::SceneData, state::SceneDataGui, id = nothing)
    if exists(id)
        CImGui.PushID(id)
    end

    # Provide a GUI for picking/creating a scene file.
    if CImGui.Button("Save new file")
        relative_path = "$(scene.new_file_name).$SCENES_EXTENSION"
        full_path = joinpath(SCENES_PATH, relative_path)
        if !isfile(full_path)
            mkpath(dirname(full_path))
            open(full_path, "w") do file
                println(file, scene.contents)
            end

            # Select the file, and refresh the scene folder tree.
            scene.current_file_path = split(relative_path, [ '/', '\\' ])
            state.scene_folder_tree = SceneFolder(SCENES_PATH)
        else
            #TODO: Display the error to the user somehow
        end
    end
    CImGui.SameLine()
    just_changed_new_file_name::Bool = @c CImGui.InputText(
        "",
        &state.new_name_buffer[0], length(state.new_name_buffer),
        0
    )
    if just_changed_new_file_name
        null_idx = findfirst('\0', state.new_name_buffer)
        scene.new_file_name = String(@view state.new_name_buffer[1:(null_idx-1)])
    end
    if CImGui.Button("Refresh Scene Files") #TODO: Just refresh every second or so instead
        state.scene_folder_tree = SceneFolder(SCENES_PATH)
    end
    # Use recursion to display the file hierarchy under the root scene folder.
    function gui_scene_folder(path::AbstractString, name::AbstractString,
                              folder::SceneFolder,
                              # The 'current_path_selection' is relative to its current folder
                              #    (recusive calls will peel off the first element, or pass `nothing`).
                              current_path_selection::Optional{AbstractVector{<:AbstractString}},
                              # The path of this folder within the root scene folder.
                              relative_path::Vector{<:AbstractString}
                             )::Optional{Vector{<:AbstractString}} # Returns the new selected file
        new_selection = Ref{Optional{Vector{<:AbstractString}}}(nothing)
        gui_within_fold(name) do
            # Display folders.
            for (name, sub_folder) in folder.contents
                if sub_folder isa SceneFolder
                    if exists(current_path_selection) && (current_path_selection[1] == name)
                        inner_current_selection = @view inner_current_selection[2:end]
                    else
                        inner_current_selection = nothing
                    end
                    inner_selection = gui_scene_folder(join(path, name), name,
                                                       sub_folder,
                                                       inner_current_selection,
                                                       vcat(relative_path, name))
                    if exists(inner_selection)
                        insert!(inner_selection, 1, name)
                        new_selection[] = inner_selection
                        current_path_selection = nothing # Nobody else will care now
                    end
                end
            end
            # Display files.
            for (name, file) in folder.contents
                if file isa SceneFile
                    #TODO: Use the following snippet to highlight a selected file:
                    # if (length(current_path_selection) == 1) && current_path_selection[1] == name
                    #     add_highlight_to_next_item()
                    # end
                    if CImGui.Button(name)
                        new_selection[] = [ name ]
                    end
                    CImGui.SameLine(0, 50)
                    #TODO: Display dialog before opening or overwriting. Make an inline dialog for simplicity.
                    if CImGui.Button("Open")
                        full_path = joinpath(path, name)
                        open(joinpath(path, name), "r") do file::IO
                            scene.contents = read(file, String)
                        end
                        scene.contents = replace(scene.contents, "\r"=>"")
                        # Update the string buffer.
                        resize!(state.scene_buffer,
                                max(length(state.scene_buffer), length(scene.contents) + 1))
                        copyto!(state.scene_buffer, scene.contents)
                        state.scene_buffer[length(scene.contents) + 1] = 0x0
                        # Reset the "edit" counter.
                        state.last_update_time = time_ns()
                        state.scene_changed = true
                        # Select this file.
                        scene.current_file_path = vcat(relative_path, name)
                        println("Selecting: ", scene.current_file_path)
                    end
                    CImGui.SameLine(0, 50)
                    if CImGui.Button("Overwrite")
                        open(joinpath(path, name), "w") do file::IO
                            print(file, scene.contents)
                        end
                    end
                end
            end
        end

        return new_selection[]
    end
    gui_scene_folder(SCENES_PATH, "Scene Files",
                     state.scene_folder_tree,
                     scene.current_file_path,
                     AbstractString[ ])

    just_changed_scene_contents::Bool = gui_with_font(1) do
        return @c CImGui.InputTextMultiline(
            "",
            &state.scene_buffer[0], length(state.scene_buffer),
            (0, 650),
            CImGui.ImGuiInputTextFlags_AllowTabInput
        )
    end
    state.scene_changed |= just_changed_scene_contents
    if (state.parse_state == SceneState.ready) && state.scene_changed
        state.parse_state = SceneState.compiling
    end

    # After enough time, tell the world to try rendering this new scene.
    if just_changed_scene_contents
        state.last_update_time = time_ns()
    elseif state.scene_changed &&
           ((time_ns() - state.last_update_time) / 1e9) > scene.refresh_wait_interval_seconds
    #begin
        last_idx = findfirst(iszero, state.scene_buffer) - 1
        scene.contents = String(@view state.scene_buffer[1:last_idx])
        state.parse_error_msg = func_try_compile_scene(scene.contents)

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