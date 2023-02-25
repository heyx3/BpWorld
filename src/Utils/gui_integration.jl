# Based on the sample GLFW backend at:
#    https://github.com/JuliaImGui/ImGuiGLFWBackend.jl/blob/master/src/ImGuiGLFWBackend.jl

#TODO: Pull into B+ eventually

"
A CImGui backend, implemented as a B+ GL Service.
Hooks into GLFW callbacks, so you should not hook into them youself;
    instead, use the `glfw_callback_X` fields.

To pass a `Texture` or `View` into a CImGui function, wrap it with `gui_tex()`.
If you're making the CImgui call from another thread, make sure to
    manually pass the correct `GuiService` instance into `gui_tex()` yourself!
"
Base.@kwdef mutable struct GuiService
    window::GLFW.Window
    last_time_ns::UInt64 = time_ns()

    # Rendering assets.
    render_program::Program
    font_texture::Texture
    buffer_vertices::Buffer
    buffer_indices::Buffer
    buffer::Mesh

    # User textures, indexed by a unique handle.
    # Needed to use bindless textures with CImGui.
    user_textures_by_handle::Dict{CImGui.ImTextureID,
                                  Union{GL.Texture, GL.View}}
    user_texture_handles::Dict{Union{GL.Texture, GL.View},
                               CImGui.ImTextureID}
    # This service periodically prunes destroyed textures from the above lookups.
    max_tex_handle::CImGui.ImTextureID
    next_tex_handle_to_prune::CImGui.ImTextureID

    # Mouse button events.
    mouse_buttons_just_pressed::Vector{Bool} = fill(false, Int(CImGui.ImGuiMouseButton_COUNT))

    # Mouse cursor images.
    mouse_cursors::Vector{GLFW.Cursor} = fill(GLFW.Cursor(C_NULL), Int(CImGui.ImGuiMouseCursor_COUNT))

    # Custom user callbacks for GLFW, running after the GuiService logic.
    glfw_callbacks_mouse_button::Vector{Any} = [ ]
    glfw_callbacks_scroll::Vector{Any} = [ ]
    glfw_callbacks_key::Vector{Any} = [ ]
    glfw_callbacks_char::Vector{Any} = [ ]
end


########################
##   Implementation   ##
########################

const SERVICE_NAME_GUI = :cimgui_bplus_integration

const IMGUI_KEY_TO_GLFW = Dict(
    #TODO: Why do so many keys seem to be missing?
    CImGui.ImGuiKey_Tab => GLFW.KEY_TAB,
    CImGui.ImGuiKey_LeftArrow => GLFW.KEY_LEFT,
    CImGui.ImGuiKey_RightArrow => GLFW.KEY_RIGHT,
    CImGui.ImGuiKey_UpArrow => GLFW.KEY_UP,
    CImGui.ImGuiKey_DownArrow => GLFW.KEY_DOWN,
    CImGui.ImGuiKey_PageUp => GLFW.KEY_PAGE_UP,
    CImGui.ImGuiKey_PageDown => GLFW.KEY_PAGE_DOWN,
    CImGui.ImGuiKey_Home => GLFW.KEY_HOME,
    CImGui.ImGuiKey_End => GLFW.KEY_END,
    CImGui.ImGuiKey_Insert => GLFW.KEY_INSERT,
    CImGui.ImGuiKey_Delete => GLFW.KEY_DELETE,
    CImGui.ImGuiKey_Backspace => GLFW.KEY_BACKSPACE,
    CImGui.ImGuiKey_Space => GLFW.KEY_SPACE,
    CImGui.ImGuiKey_Enter => GLFW.KEY_ENTER,
    CImGui.ImGuiKey_Escape => GLFW.KEY_ESCAPE,
    # CImGui.ImGuiKey_Apostrophe => GLFW.KEY_APOSTROPHE,
    # CImGui.ImGuiKey_Comma => GLFW.KEY_COMMA,
    # CImGui.ImGuiKey_Minus => GLFW.KEY_MINUS,
    # CImGui.ImGuiKey_Period => GLFW.KEY_PERIOD,
    # CImGui.ImGuiKey_Slash => GLFW.KEY_SLASH,
    # CImGui.ImGuiKey_Semicolon => GLFW.KEY_SEMICOLON,
    # CImGui.ImGuiKey_Equal => GLFW.KEY_EQUAL,
    # CImGui.ImGuiKey_LeftBracket => GLFW.KEY_LEFT_BRACKET,
    # CImGui.ImGuiKey_Backslash => GLFW.KEY_BACKSLASH,
    # CImGui.ImGuiKey_RightBracket => GLFW.KEY_RIGHT_BRACKET,
    # CImGui.ImGuiKey_GraveAccent => GLFW.KEY_GRAVE_ACCENT,
    # CImGui.ImGuiKey_CapsLock => GLFW.KEY_CAPS_LOCK,
    # CImGui.ImGuiKey_ScrollLock => GLFW.KEY_SCROLL_LOCK,
    # CImGui.ImGuiKey_NumLock => GLFW.KEY_NUM_LOCK,
    # CImGui.ImGuiKey_PrintScreen => GLFW.KEY_PRINT_SCREEN,
    # CImGui.ImGuiKey_Pause => GLFW.KEY_PAUSE,
    # CImGui.ImGuiKey_Keypad0 => GLFW.KEY_KP_0,
    # CImGui.ImGuiKey_Keypad1 => GLFW.KEY_KP_1,
    # CImGui.ImGuiKey_Keypad2 => GLFW.KEY_KP_2,
    # CImGui.ImGuiKey_Keypad3 => GLFW.KEY_KP_3,
    # CImGui.ImGuiKey_Keypad4 => GLFW.KEY_KP_4,
    # CImGui.ImGuiKey_Keypad5 => GLFW.KEY_KP_5,
    # CImGui.ImGuiKey_Keypad6 => GLFW.KEY_KP_6,
    # CImGui.ImGuiKey_Keypad7 => GLFW.KEY_KP_7,
    # CImGui.ImGuiKey_Keypad8 => GLFW.KEY_KP_8,
    # CImGui.ImGuiKey_Keypad9 => GLFW.KEY_KP_9,
    # CImGui.ImGuiKey_KeypadDecimal => GLFW.KEY_KP_DECIMAL,
    # CImGui.ImGuiKey_KeypadDivide => GLFW.KEY_KP_DIVIDE,
    # CImGui.ImGuiKey_KeypadMultiply => GLFW.KEY_KP_MULTIPLY,
    # CImGui.ImGuiKey_KeypadSubtract => GLFW.KEY_KP_SUBTRACT,
    # CImGui.ImGuiKey_KeypadAdd => GLFW.KEY_KP_ADD,
    CImGui.ImGuiKey_KeyPadEnter => GLFW.KEY_KP_ENTER,
    # CImGui.ImGuiKey_KeypadEqual => GLFW.KEY_KP_EQUAL,
    # CImGui.ImGuiKey_LeftShift => GLFW.KEY_LEFT_SHIFT,
    # CImGui.ImGuiKey_LeftCtrl => GLFW.KEY_LEFT_CONTROL,
    # CImGui.ImGuiKey_LeftAlt => GLFW.KEY_LEFT_ALT,
    # CImGui.ImGuiKey_LeftSuper => GLFW.KEY_LEFT_SUPER,
    # CImGui.ImGuiKey_RightShift => GLFW.KEY_RIGHT_SHIFT,
    # CImGui.ImGuiKey_RightCtrl => GLFW.KEY_RIGHT_CONTROL,
    # CImGui.ImGuiKey_RightAlt => GLFW.KEY_RIGHT_ALT,
    # CImGui.ImGuiKey_RightSuper => GLFW.KEY_RIGHT_SUPER,
    # CImGui.ImGuiKey_Menu => GLFW.KEY_MENU,
    # CImGui.ImGuiKey_0 => GLFW.KEY_0,
    # CImGui.ImGuiKey_1 => GLFW.KEY_1,
    # CImGui.ImGuiKey_2 => GLFW.KEY_2,
    # CImGui.ImGuiKey_3 => GLFW.KEY_3,
    # CImGui.ImGuiKey_4 => GLFW.KEY_4,
    # CImGui.ImGuiKey_5 => GLFW.KEY_5,
    # CImGui.ImGuiKey_6 => GLFW.KEY_6,
    # CImGui.ImGuiKey_7 => GLFW.KEY_7,
    # CImGui.ImGuiKey_8 => GLFW.KEY_8,
    # CImGui.ImGuiKey_9 => GLFW.KEY_9,
    CImGui.ImGuiKey_A => GLFW.KEY_A,
    # CImGui.ImGuiKey_B => GLFW.KEY_B,
    CImGui.ImGuiKey_C => GLFW.KEY_C,
    # CImGui.ImGuiKey_D => GLFW.KEY_D,
    # CImGui.ImGuiKey_E => GLFW.KEY_E,
    # CImGui.ImGuiKey_F => GLFW.KEY_F,
    # CImGui.ImGuiKey_G => GLFW.KEY_G,
    # CImGui.ImGuiKey_H => GLFW.KEY_H,
    # CImGui.ImGuiKey_I => GLFW.KEY_I,
    # CImGui.ImGuiKey_J => GLFW.KEY_J,
    # CImGui.ImGuiKey_K => GLFW.KEY_K,
    # CImGui.ImGuiKey_L => GLFW.KEY_L,
    # CImGui.ImGuiKey_M => GLFW.KEY_M,
    # CImGui.ImGuiKey_N => GLFW.KEY_N,
    # CImGui.ImGuiKey_O => GLFW.KEY_O,
    # CImGui.ImGuiKey_P => GLFW.KEY_P,
    # CImGui.ImGuiKey_Q => GLFW.KEY_Q,
    # CImGui.ImGuiKey_R => GLFW.KEY_R,
    # CImGui.ImGuiKey_S => GLFW.KEY_S,
    # CImGui.ImGuiKey_T => GLFW.KEY_T,
    # CImGui.ImGuiKey_U => GLFW.KEY_U,
    CImGui.ImGuiKey_V => GLFW.KEY_V,
    # CImGui.ImGuiKey_W => GLFW.KEY_W,
    CImGui.ImGuiKey_X => GLFW.KEY_X,
    CImGui.ImGuiKey_Y => GLFW.KEY_Y,
    CImGui.ImGuiKey_Z => GLFW.KEY_Z,
    # CImGui.ImGuiKey_F1 => GLFW.KEY_F1,
    # CImGui.ImGuiKey_F2 => GLFW.KEY_F2,
    # CImGui.ImGuiKey_F3 => GLFW.KEY_F3,
    # CImGui.ImGuiKey_F4 => GLFW.KEY_F4,
    # CImGui.ImGuiKey_F5 => GLFW.KEY_F5,
    # CImGui.ImGuiKey_F6 => GLFW.KEY_F6,
    # CImGui.ImGuiKey_F7 => GLFW.KEY_F7,
    # CImGui.ImGuiKey_F8 => GLFW.KEY_F8,
    # CImGui.ImGuiKey_F9 => GLFW.KEY_F9,
    # CImGui.ImGuiKey_F10 => GLFW.KEY_F10,
    # CImGui.ImGuiKey_F11 => GLFW.KEY_F11,
    # CImGui.ImGuiKey_F12 => GLFW.KEY_F12
)

 #TODO: Is it more performant to keep the CImGui mesh data on the CPU?
const KEEP_MESH_DATA_ON_CPU = false
gui_generate_mesh(verts::Buffer, indices::Buffer) = Mesh(
    PrimitiveTypes.triangle,
    [ VertexDataSource(verts, sizeof(CImGui.ImDrawVert)) ],
    # The vertex data is interleaved, and equivalent to the struct CImGui.ImDrawVert.
    map(zip(1:3, [ VertexData_FVector(2, Float32),
                   VertexData_FVector(2, Float32),
                   VertexData_FVector(4, UInt8, true) ])
       ) do (i, v_type)
        return VertexAttribute(1, fieldoffset(CImGui.ImDrawVert, i), v_type)
    end,
    MeshIndexData(indices, CImGui.ImDrawIdx)
)

const CLIPBOARD_BUFFER = Vector{UInt8}(undef, 1024)
function gui_clipboard_get(::Ptr{Cvoid})::String
    clipboard_raw = clipboard()
    clipboard_str::String = (clipboard_raw isa String) ?
                                clipboard_raw :
                                String(clipboard_raw)

    str_len = sizeof(clipboard_str)
    resize!(CLIPBOARD_BUFFER, str_len)

    output_buf = IOBuffer(CLIPBOARD_BUFFER, write=true)
    try
        write(output_buf, clipboard_str)
    finally
        close(output_buf)
    end

    return String(CLIPBOARD_BUFFER)
end
function gui_clipboard_set(::Ptr{Cvoid}, chars::String)::Cvoid
    clipboard(chars)
    return nothing
end
const GUI_CLIPBOARD_GET = @cfunction(gui_clipboard_get, String, (Ptr{Cvoid}, ))
const GUI_CLIPBOARD_SET = @cfunction(gui_clipboard_set, Cvoid, (Ptr{Cvoid}, String))


const IM_GUI_CONTEXT_REF = Ref{Ptr{CImGui.ImGuiContext}}(C_NULL)
const IM_GUI_CONTEXT_COUNTER = Ref(0)
const IM_GUI_CONTEXT_LOCKER = ReentrantLock()


###################
##   Interface   ##
###################

"Starts and returns the GUI service."
function service_gui_init( context::Bplus.GL.Context
                           ;
                           initial_vertex_capacity::Int = 1024,
                           initial_index_capacity::Int = (initial_vertex_capacity * 2) ÷ 3
                         )::GuiService
    # Create/get the CImGui context.
    @lock IM_GUI_CONTEXT_LOCKER begin
        if IM_GUI_CONTEXT_COUNTER[] < 1
            IM_GUI_CONTEXT_REF[] = CImGui.CreateContext()
        end
        IM_GUI_CONTEXT_COUNTER[] += 1
    end
    @assert(IM_GUI_CONTEXT_REF[] != C_NULL)
    gui_io::Ptr{CImGui.ImGuiIO} = CImGui.GetIO()
    gui_fonts::Ptr{CImGui.ImFontAtlas} = gui_io.Fonts
    CImGui.AddFontDefault(gui_fonts)

    # Report capabilities to CImGUI.
    gui_io.BackendPlatformName = "bplus_glfw"
    gui_io.BackendFlags |= CImGui.ImGuiBackendFlags_HasMouseCursors
    gui_io.BackendFlags |= CImGui.ImGuiBackendFlags_HasSetMousePos
    gui_io.BackendRendererName = "bplus_GL"
    gui_io.BackendFlags |= CImGui.ImGuiBackendFlags_RendererHasVtxOffset

    # Set up keybindings.
    for (imgui_key, glfw_key) in IMGUI_KEY_TO_GLFW
        CImGui.Set_KeyMap(gui_io, imgui_key, glfw_key)
    end

    # Set up the clipboard.
    gui_io.GetClipboardTextFn = GUI_CLIPBOARD_GET
    gui_io.SetClipboardTextFn = GUI_CLIPBOARD_SET

    # Tell ImGui how to manipulate/query data.
    GLFW.SetCharCallback(context.window, (window::GLFW.Window, c::Char) -> begin
        # Why this range? The example code doesn't explain.
        # It limits the char to a 2-byte range, and ignores the null terminator.
        if UInt(c) in 0x1:0xffff
            CImGui.AddInputCharacter(gui_io, c)
        end
        for user_callback in serv.glfw_callbacks_char
            user_callback(window, c)
        end
        return nothing
    end)
    GLFW.SetKeyCallback(context.window, (window::GLFW.Window,
                                         key::GLFW.Key, scancode::Cint,
                                         action::GLFW.Action, mods::Cint) -> begin
        if action == GLFW.PRESS
            CImGui.Set_KeysDown(gui_io, key, true)
        elseif action == GLFW.RELEASE
            CImGui.Set_KeysDown(gui_io, key, false)
        end

        # Calculate modifiers.
        #   (note from the original implementation: "modifiers are not reliable across systems")
        gui_io.KeyCtrl = any(CImGui.Get_KeysDown.(Ref(gui_io), (GLFW.KEY_LEFT_CONTROL, GLFW.KEY_RIGHT_CONTROL)))
        gui_io.KeyShift = any(CImGui.Get_KeysDown.(Ref(gui_io), (GLFW.KEY_LEFT_SHIFT, GLFW.KEY_RIGHT_SHIFT)))
        gui_io.KeyAlt = any(CImGui.Get_KeysDown.(Ref(gui_io), (GLFW.KEY_LEFT_ALT, GLFW.KEY_RIGHT_ALT)))
        gui_io.KeySuper = any(CImGui.Get_KeysDown.(Ref(gui_io), (GLFW.KEY_LEFT_SUPER, GLFW.KEY_RIGHT_SUPER)))

        for user_callback in serv.glfw_callbacks_key
            user_callback(window, key, scancode, action, mods)
        end
        return nothing
    end)
    GLFW.SetMouseButtonCallback(context.window, (window::GLFW.Window,
                                                 button::GLFW.MouseButton,
                                                 action::GLFW.Action,
                                                 mods::Cint) -> begin
        button_i = Int(button) + 1
        if button_i in 1:length(serv.mouse_buttons_just_pressed)
            if action == GLFW.PRESS
                serv.mouse_buttons_just_pressed[button_i] = true
            end
        else
            @warn "Mouse button idx too large" button
        end

        for user_callback in serv.glfw_callbacks_mouse_button
            user_callback(window, button, action, mods)
        end
        return nothing
    end)
    GLFW.SetScrollCallback(context.window, (window, x, y) -> begin
        gui_io.MouseWheelH += Cfloat(x)
        gui_io.MouseWheel += Cfloat(y)

        for user_callback in serv.glfw_callbacks_scroll
            user_callback(window, x, y)
        end
        return nothing
    end)

    # Create renderer assets.
    render_program = bp_glsl"""
    #START_VERTEX
        layout (location = 0) in vec2 vIn_pos;
        layout (location = 1) in vec2 vIn_uv;
        layout (location = 2) in vec4 vIn_color;

        uniform mat4 u_transform;

        out vec2 fIn_uv;
        out vec4 fIn_color;

        void main() {
            fIn_uv = vIn_uv;
            fIn_color = vIn_color;

            vec4 pos = u_transform * vec4(vIn_pos, 0, 1);
            gl_Position = vec4(pos.x, pos.y, pos.zw);
        }

    #START_FRAGMENT
        in vec2 fIn_uv;
        in vec4 fIn_color;

        uniform sampler2D u_texture;

        layout (location = 0) out vec4 fOut_color;

        void main() {
            fOut_color = fIn_color * texture(u_texture, fIn_uv);
        }
    """
    # Font texture data comes from querying the ImGUI's IO structure.
    font_pixels = Ptr{Cuchar}(C_NULL)
    font_size_x = Cint(-1)
    font_size_y = Cint(-1)
    @c CImGui.GetTexDataAsRGBA32(gui_fonts, &font_pixels, &font_size_x, &font_size_y)
    font_pixels_casted = Ptr{vRGBAu8}(font_pixels)
    font_pixels_managed = unsafe_wrap(Matrix{vRGBAu8}, font_pixels_casted,
                                      (font_size_x, font_size_y))
    font_texture = Texture(
        SimpleFormat(FormatTypes.normalized_uint,
                     SimpleFormatComponents.RGBA,
                     SimpleFormatBitDepths.B8),
        font_pixels_managed,
        sampler = Sampler{2}(
            wrapping = WrapModes.clamp
        )
    )
    # Mesh vertex/index data is generated procedurally, into a single mesh object.
    buffer_vertices = Buffer(sizeof(CImGui.ImDrawVert) * initial_vertex_capacity,
                             true, KEEP_MESH_DATA_ON_CPU)
    buffer_indices = Buffer(sizeof(CImGui.ImDrawIdx) * initial_index_capacity,
                            true, KEEP_MESH_DATA_ON_CPU)
    mesh = gui_generate_mesh(buffer_vertices, buffer_indices)

    # Create the service instance.
    FONT_TEXTURE_ID = CImGui.ImTextureID(1)
    serv = GuiService(
        window = context.window,

        render_program = render_program,
        font_texture = font_texture,
        buffer_vertices = buffer_vertices,
        buffer_indices = buffer_indices,
        buffer = mesh,

        user_textures_by_handle = Dict{CImGui.ImTextureID,
                                       Union{GL.Texture, GL.View}}(
            FONT_TEXTURE_ID => font_texture
        ),
        user_texture_handles = Dict{Union{GL.Texture, GL.View},
                                    CImGui.ImTextureID}(
            font_texture => FONT_TEXTURE_ID
        ),
        max_tex_handle = FONT_TEXTURE_ID,
        next_tex_handle_to_prune = FONT_TEXTURE_ID
    )
    CImGui.SetTexID(gui_fonts, FONT_TEXTURE_ID)

    # Configure the cursors to use.
    cursors = [
        (CImGui.ImGuiMouseCursor_Arrow, GLFW.ARROW_CURSOR),
        (CImGui.ImGuiMouseCursor_TextInput, GLFW.IBEAM_CURSOR),
        (CImGui.ImGuiMouseCursor_ResizeNS, GLFW.VRESIZE_CURSOR),
        (CImGui.ImGuiMouseCursor_ResizeEW, GLFW.HRESIZE_CURSOR),
        (CImGui.ImGuiMouseCursor_Hand, GLFW.HAND_CURSOR),
        # In GLFW 3.4, there are new cursor images we could use.
        # However, that version isn't supported.
        (CImGui.ImGuiMouseCursor_ResizeAll, GLFW.ARROW_CURSOR), # GLFW.RESIZE_ALL_CURSOR
        (CImGui.ImGuiMouseCursor_ResizeNESW, GLFW.ARROW_CURSOR), # GLFW.RESIZE_NESW_CURSOR
        (CImGui.ImGuiMouseCursor_ResizeNWSE, GLFW.ARROW_CURSOR), # GLFW.RESIZE_NWSE_CURSOR
        (CImGui.ImGuiMouseCursor_NotAllowed, GLFW.ARROW_CURSOR) # GLFW.NOT_ALLOWED_CURSOR
    ]
    for (slot, type) in cursors
        # Remember that the libraries specify things in 0-based indices.
        serv.mouse_cursors[slot + 1] = GLFW.CreateStandardCursor(type)
    end

    # Finally, register and return the service.
    Bplus.GL.register_service(
        context, SERVICE_NAME_GUI,
        Bplus.GL.Service(
            serv,
            on_destroyed = service_gui_cleanup
        )
    )
    return serv
end
function service_gui_get(context::Bplus.GL.Context = get_context())::GuiService
    return Bplus.GL.get_service(context, SERVICE_NAME_GUI)
end

function service_gui_cleanup(s::GuiService)
    # Clean up mouse cursors.
    for cursor in s.mouse_cursors
        GLFW.DestroyCursor(cursor)
    end
    empty!(s.mouse_cursors)

    # Clean up GL resources.
    close(s.render_program)
    close(s.font_texture)
    close(s.buffer)
    close(s.buffer_indices)
    close(s.buffer_vertices)

    # Clean up the CImGui context if nobody else needs it.
    @lock IM_GUI_CONTEXT_LOCKER begin
        IM_GUI_CONTEXT_COUNTER[] -= 1
        if IM_GUI_CONTEXT_COUNTER[] < 1
            CImGui.DestroyContext(IM_GUI_CONTEXT_REF[])
            IM_GUI_CONTEXT_REF[] = C_NULL
        end
    end

    return nothing
end

service_gui_start_frame(context::Bplus.GL.Context = get_context()) = service_gui_start_frame(service_gui_get(context))
function service_gui_start_frame(serv::GuiService)
    io::Ptr{CImGui.ImGuiIO} = CImGui.GetIO()
    @bpworld_assert(CImGui.ImFontAtlas_IsBuilt(io.Fonts),
                    "Font atlas isn't built! This implies the renderer isn't initialized properly")

    # Set up the display size.
    window_size::v2i = get_window_size(serv.window)
    render_size::v2i = let render_size_glfw = GLFW.GetFramebufferSize(serv.window)
        v2i(render_size_glfw.width, render_size_glfw.height)
    end
    io.DisplaySize = CImGui.ImVec2(Cfloat(window_size.x), Cfloat(window_size.y))
    render_scale::Vec2{Cfloat} = render_size / max(one(v2i), window_size)
    io.DisplayFramebufferScale = CImGui.ImVec2(render_scale...)

    # Update the frame time.
    last_time = serv.last_time_ns
    serv.last_time_ns = time_ns()
    io.DeltaTime = (serv.last_time_ns - last_time) / 1e9

    # Update mouse buttons.
    for i in 1:length(serv.mouse_buttons_just_pressed)
        # If a mouse press happened, always pass it as "mouse held this frame";
        #    otherwise we'd miss fast clicks.
        is_down::Bool = serv.mouse_buttons_just_pressed[i] ||
                        GLFW.GetMouseButton(serv.window, GLFW.MouseButton(i - 1))
        CImGui.Set_MouseDown(io, i - 1, is_down)
        serv.mouse_buttons_just_pressed[i] = false
    end

    # Update mouse position.
    prev_mouse_pos = io.MousePos
    io.MousePos = CImGui.ImVec2(-CImGui.FLT_MAX, -CImGui.FLT_MAX)
    if GLFW.GetWindowAttrib(serv.window, GLFW.FOCUSED) != 0
        if io.WantSetMousePos
            GLFW.SetCursorPos(serv.window, Cdouble(prev_mouse_pos.x), Cdouble(prev_mouse_pos.y))
        else
            (cursor_x, cursor_y) = GLFW.GetCursorPos(serv.window)
            io.MousePos = CImGui.ImVec2(Cfloat(cursor_x), Cfloat(cursor_y))
        end
    end

    # Update the mouse cursor's image.
    if ((io.ConfigFlags & CImGui.ImGuiConfigFlags_NoMouseCursorChange) != CImGui.ImGuiConfigFlags_NoMouseCursorChange) &&
       (GLFW.GetInputMode(serv.window, GLFW.CURSOR) != GLFW.CURSOR_DISABLED)
    #begin
        imgui_cursor::CImGui.ImGuiMouseCursor = CImGui.GetMouseCursor()
        # Hide the OS mouse cursor if ImGui is drawing it, or if it wants no cursor.
        if (imgui_cursor == CImGui.ImGuiMouseCursor_None) || io.MouseDrawCursor
            GLFW.SetInputMode(serv.window, GLFW.CURSOR, GLFW.CURSOR_HIDDEN)
        # Otherwise, make sure it's shown.
        else
            cursor = serv.mouse_cursors[imgui_cursor + 1]
            cursor_img = (cursor.handle == C_NULL) ?
                                serv.mouse_cursors[imgui_cursor + 1] :
                                serv.mouse_cursors[CImGui.ImGuiMouseCursor_Arrow + 1]
            GLFW.SetCursor(serv.window, cursor_img)
            GLFW.SetInputMode(serv.window, GLFW.CURSOR, GLFW.CURSOR_NORMAL)
        end
    end

    #TODO: Update/handle gamepads. Refer to CImGui/backend/GLFW/impl.jl

    # Check for previously-used textures getting destroyed.
    # Just check a few different textures every frame.
    for _ in 1:3
        if haskey(serv.user_textures_by_handle, serv.next_tex_handle_to_prune)
            tex_to_prune = serv.user_textures_by_handle[serv.next_tex_handle_to_prune]
            if is_destroyed(tex_to_prune)
                delete!(serv.user_textures_by_handle, serv.next_tex_handle_to_prune)
                delete!(serv.user_texture_handles, tex_to_prune)
            end
        end
        serv.next_tex_handle_to_prune = CImGui.ImTextureID(
            (UInt64(serv.next_tex_handle_to_prune) + 1) %
                UInt64(serv.max_tex_handle)
        )
    end

    CImGui.NewFrame()

    return nothing
end

service_gui_end_frame(context::Bplus.GL.Context = get_context()) = service_gui_end_frame(service_gui_get(context), context)
function service_gui_end_frame(serv::GuiService, context::Bplus.GL.Context = get_context())
    io::Ptr{CImGui.ImGuiIO} = CImGui.GetIO()
    @assert(CImGui.ImFontAtlas_IsBuilt(io.Fonts),
            "Font atlas isn't built! This implies the renderer isn't initialized properly")

    CImGui.Render()
    draw_data::Ptr{CImGui.ImDrawData} = CImGui.GetDrawData()
    if draw_data == C_NULL
        return nothing
    end

    # Compute coordinate transforms.
    framebuffer_size = v2i(trunc(draw_data.DisplaySize.x * draw_data.FramebufferScale.x),
                           trunc(draw_data.DisplaySize.y * draw_data.FramebufferScale.y))
    if any(framebuffer_size <= 0)
        return nothing
    end
    draw_pos_min = v2f(draw_data.DisplayPos.x, draw_data.DisplayPos.y)
    draw_size = v2f(draw_data.DisplaySize.x, draw_data.DisplaySize.y)
    draw_pos_max = draw_pos_min + draw_size
    draw_pos_min, draw_pos_max = tuple(
        v2f(draw_pos_min.x, draw_pos_max.y),
        v2f(draw_pos_max.x, draw_pos_min.y)
    )
    mat_proj::fmat4 = m4_ortho(vappend(draw_pos_min, -one(Float32)),
                               vappend(draw_pos_max, one(Float32)))
    set_uniform(serv.render_program, "u_transform", mat_proj)

    # Set up render state.
    set_blending(context, make_blend_alpha(BlendStateRGBA))
    set_culling(context, FaceCullModes.Off)
    set_depth_test(context, ValueTests.Pass)
    set_depth_writes(context, false)
    #TODO: Set clip mode to lower-left corner, and depth range to (-1,+1), once B+ supports glClipControl

    # Pre-activate the font texture, which will presumably be rendered a lot.
    font_tex_id = io.Fonts.TexID
    view_activate(serv.user_textures_by_handle[font_tex_id])

    # Scissor/clip rectangles will come in projection space.
    # We'll need to map them into framebuffer space.
    # Clip offset is (0,0) unless using multi-viewports.
    clip_offset = -draw_pos_min
    # Clip scale is (1, 1) unless using retina display, which is often (2, 2).
    clip_scale = v2f(draw_data.FramebufferScale.x, draw_data.FramebufferScale.y)

    # Execute the individual drawing commands.
    for cmd_list_i in 1:draw_data.CmdListsCount
        cmd_list = CImGui.ImDrawData_Get_CmdLists(draw_data, cmd_list_i - 1)

        # Upload the vertex/index data.
        # We may have to reallocate the buffers if they're not large enough.
        vertices_native = CImGui.ImDrawList_Get_VtxBuffer(cmd_list)
        indices_native = CImGui.ImDrawList_Get_IdxBuffer(cmd_list)
        reallocated_buffers::Bool = false
        let vertices = unsafe_wrap(Vector{CImGui.ImDrawVert},
                                   vertices_native.Data, vertices_native.Size)
            if serv.buffer_vertices.byte_size < (length(vertices) * sizeof(CImGui.ImDrawVert))
                close(serv.buffer_vertices)
                new_size = sizeof(CImGui.ImDrawVert) * length(vertices) * 2
                serv.buffer_vertices = Buffer(new_size, true, KEEP_MESH_DATA_ON_CPU)
                reallocated_buffers = true
            end
            set_buffer_data(serv.buffer_vertices, vertices)
        end
        let indices = unsafe_wrap(Vector{CImGui.ImDrawIdx},
                                  indices_native.Data, indices_native.Size)
            if serv.buffer_indices.byte_size < (length(indices) * sizeof(CImGui.ImDrawIdx))
                close(serv.buffer_indices)
                new_size = sizeof(CImGui.ImDrawIdx) * length(indices) * 2
                serv.buffer_indices = Buffer(new_size, true, KEEP_MESH_DATA_ON_CPU)
                reallocated_buffers = true
            end
            set_buffer_data(serv.buffer_indices, indices)
        end
        if reallocated_buffers
            close(serv.buffer)
            serv.buffer = gui_generate_mesh(serv.buffer_vertices, serv.buffer_indices)
        end

        # Execute each command in this list.
        cmd_buffer = CImGui.ImDrawList_Get_CmdBuffer(cmd_list)
        for cmd_i in 1:cmd_buffer.Size
            cmd_ptr::Ptr{CImGui.ImDrawCmd} = cmd_buffer.Data + ((cmd_i - 1) * sizeof(CImGui.ImDrawCmd))
            n_elements = cmd_ptr.ElemCount

            # If the user provided a custom drawing function, use that.
            if cmd_ptr.UserCallback != C_NULL
                ccall(cmd_ptr.UserCallback, Cvoid,
                      (Ptr{CImGui.ImDrawList}, Ptr{CImGui.ImDrawCmd}),
                      cmd_list, cmd_ptr)
            # Otherwise, do a normal GUI draw.
            else
                # Set the scissor region.
                clip_rect_projected = cmd_ptr.ClipRect
                clip_minmax_projected = v4f(clip_rect_projected.x, clip_rect_projected.y,
                                            clip_rect_projected.z, clip_rect_projected.w)
                clip_min = clip_scale * (clip_minmax_projected.xy - clip_offset)
                clip_max = clip_scale * (clip_minmax_projected.zw - clip_offset)
                if all(clip_min < framebuffer_size) && all(clip_max >= 0)
                    # The scissor min and max depend on the assumption
                    #    of lower-left-corner clip-mode.
                    scissor_min = Vec(clip_min.x, framebuffer_size.y - clip_max.y)
                    scissor_max = clip_max

                    scissor_min_pixel = map(x -> trunc(Cint, x), scissor_min)
                    scissor_max_pixel = map(x -> trunc(Cint, x), scissor_max)
                    # ImGUI is using 0-based, but B+ uses 1-based.
                    scissor_min_pixel += one(Int32)
                    # Max pixel doesn't need to add 1, but I'm not quite sure why.
                    set_scissor(context, (scissor_min_pixel, scissor_max_pixel))
                end

                # Draw the texture.
                tex_id = cmd_ptr.TextureId
                tex = haskey(serv.user_textures_by_handle, tex_id) ?
                          serv.user_textures_by_handle[tex_id] :
                          error("Unknown GUI texture handle: ", tex_id)
                set_uniform(serv.render_program, "u_texture", tex)
                (tex_id != font_tex_id) && view_activate(tex)
                render_mesh(
                    context,
                    serv.buffer, serv.render_program
                    ;
                    indexed_params = DrawIndexed(
                        value_offset = UInt64(cmd_ptr.VtxOffset)
                    ),
                    elements = Box_minsize(
                        UInt32(cmd_ptr.IdxOffset + 1),
                        UInt32(n_elements)
                    )
                )
                (tex_id != font_tex_id) && view_deactivate(tex)
            end
        end
    end

    view_deactivate(serv.user_textures_by_handle[font_tex_id])

    return nothing
end

"Wraps a `Bplus.GL.Texture` or `Bplus.GL.View` so that it can be passed to CImGui."
function gui_tex(tex::Union{Texture, View}, service::GuiService = service_gui_get())
    return get!(service.user_texture_handles, tex) do
        @bpworld_assert(!haskey(service.user_texture_handles, tex),
                        "The call to get!() invoked this lambda twice in a row")

        next_handle = service.max_tex_handle + 1
        service.max_tex_handle += 1
        @bpworld_assert(!haskey(service.user_textures_by_handle, next_handle))

        service.user_textures_by_handle[next_handle] = tex
        return CImGui.ImTextureID(next_handle)
    end
end


#################
##   Helpers   ##
#################

function gui_window(to_do, args...; kw_args...)
    output = CImGui.Begin(args..., kw_args...)
    try
        to_do()
        return output
    finally
        CImGui.End()
    end
end
function gui_with_item_width(to_do, width::Real)
    CImGui.PushItemWidth(Float32(width))
    try
        return to_do()
    finally
        CImGui.PopItemWidth()
    end
end
function gui_with_unescaped_tabbing(to_do)
    CImGui.PushAllowKeyboardFocus(false)
    try
        return to_do()
    finally
        CImGui.PopAllowKeyboardFocus()
    end
end
function gui_within_tree_node(to_do, label)
    is_visible::Bool = CImGui.TreeNode(label)
    if is_visible
        try
            return to_do()
        finally
            CImGui.TreePop()
        end
    end

    return nothing
end

"Edits a vector with spherical coordinates; returns its new value."
function gui_spherical_vector( label, vec::v3f
                               ;
                               stays_normalized::Bool = false,
                               fallback_yaw::Ref{Float32} = Ref(zero(Float32))
                             )::v3f
    radius = vlength(vec)
    vec /= radius

    yawpitch = Float32.((atan(vec.y, vec.x), acos(vec.z)))
    # Keep the editor stable when it reaches a straight-up or straight-down vector.
    if yawpitch[2] in (Float32(-π), Float32(π))
        yawpitch = (fallback_yaw[], yawpitch[2])
    else
        fallback_yaw[] = yawpitch[1]
    end

    if stays_normalized
        # Remove floating-point error in the previous length calculation.
        radius = one(Float32)
    else
        # Provide an editor for the radius.
        @c CImGui.InputFloat("$label Length", &radius)
        CImGui.SameLine()
    end
    @c CImGui.SliderFloat2(label, &yawpitch, -π, π)

    # Convert back to cartesian coordinates.
    pitch_sincos = sincos(yawpitch[2])
    vec_2d = v2f(sincos(yawpitch[1])).yx * pitch_sincos[1]
    vec_z = pitch_sincos[2]
    return radius * vappend(vec_2d, vec_z)
end