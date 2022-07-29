# Structs for various pieces of world data,
#    with accompanying GUI and serialization helpers.

"All information needed to describe the sun"
Base.@kwdef mutable struct SunData
    dir::v3f = vnorm(v3f(1, 1, -1))
    color::vRGBf = vRGBf(1, 1, 1)
end
StructTypes.StructType(::Type{SunData}) = StructTypes.Mutable()

Base.@kwdef mutable struct SunDataGui
    color_picker_is_open::Bool = false
    fallback_yaw::Ref{Float32} = Ref(@f32(0))
end
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
Base.@kwdef mutable struct FogData
    density::Float32 = @f32(0.0084)
    dropoff::Float32 = @f32(1)
    height_offset::Float32 = @f32(430)
    height_scale::Float32 = @f32(0.01)
    color::vRGBf = vRGBf(0.3, 0.3, 1.0)
end
StructTypes.StructType(::Type{FogData}) = StructTypes.Mutable()

Base.@kwdef mutable struct FogDataGui
    color_state::Bool = false
end
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