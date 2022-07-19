# Based on the sample GLFW backend at:
#    https://github.com/JuliaImGui/ImGuiGLFWBackend.jl/blob/master/src/ImGuiGLFWBackend.jl

#TODO: Pull into B+ eventually

"The state of the CImGui backend, associated with a specific `Bplus.GL.Context`."
Base.@kwdef mutable struct GuiService
    window::GLFW.Window = GLFW.Window()
    id::Int=new_id()
    time::Cfloat = Cfloat(0.0f0)

    mouse_just_pressed::Vector{Bool} = fill(false, Int(ImGuiMouseButton_COUNT))
    mouse_cursors::Vector{GLFW.Cursor} = fill(GLFW.Cursor(C_NULL), Int(ImGuiMouseCursor_COUNT))

    key_owner_windows::Vector{GLFW.Window} = fill(GLFW.Window(), 512)
    should_update_monitors::Bool = true

    # Existing callbacks which this service must wrap.
    prev_user_callback_mousebutton = nothing
    prev_user_callback_scroll = nothing
    prev_user_callback_key = nothing
    prev_user_callback_char = nothing
    prev_user_callback_monitor = nothing
end

const SERVICE_NAME_GUI = :cimgui_bplus_integration
const BACKEND_NAME_INPUT = "bplus_input_backend"

const GLFW_KEY_TO_IMGUI = Dict{GLFW.Key, ImGuiKey}(
    #TODO: Why do so many keys seem to be missing?
    GLFW.KEY_TAB => ImGuiKey_Tab,
    GLFW.KEY_LEFT => ImGuiKey_LeftArrow,
    GLFW.KEY_RIGHT => ImGuiKey_RightArrow,
    GLFW.KEY_UP => ImGuiKey_UpArrow,
    GLFW.KEY_DOWN => ImGuiKey_DownArrow,
    GLFW.KEY_PAGE_UP => ImGuiKey_PageUp,
    GLFW.KEY_PAGE_DOWN => ImGuiKey_PageDown,
    GLFW.KEY_HOME => ImGuiKey_Home,
    GLFW.KEY_END => ImGuiKey_End,
    GLFW.KEY_INSERT => ImGuiKey_Insert,
    GLFW.KEY_DELETE => ImGuiKey_Delete,
    GLFW.KEY_BACKSPACE => ImGuiKey_Backspace,
    GLFW.KEY_SPACE => ImGuiKey_Space,
    GLFW.KEY_ENTER => ImGuiKey_Enter,
    GLFW.KEY_ESCAPE => ImGuiKey_Escape,
    # GLFW.KEY_APOSTROPHE => ImGuiKey_Apostrophe,
    # GLFW.KEY_COMMA => ImGuiKey_Comma,
    # GLFW.KEY_MINUS => ImGuiKey_Minus,
    # GLFW.KEY_PERIOD => ImGuiKey_Period,
    # GLFW.KEY_SLASH => ImGuiKey_Slash,
    # GLFW.KEY_SEMICOLON => ImGuiKey_Semicolon,
    # GLFW.KEY_EQUAL => ImGuiKey_Equal,
    # GLFW.KEY_LEFT_BRACKET => ImGuiKey_LeftBracket,
    # GLFW.KEY_BACKSLASH => ImGuiKey_Backslash,
    # GLFW.KEY_RIGHT_BRACKET => ImGuiKey_RightBracket,
    # GLFW.KEY_GRAVE_ACCENT => ImGuiKey_GraveAccent,
    # GLFW.KEY_CAPS_LOCK => ImGuiKey_CapsLock,
    # GLFW.KEY_SCROLL_LOCK => ImGuiKey_ScrollLock,
    # GLFW.KEY_NUM_LOCK => ImGuiKey_NumLock,
    # GLFW.KEY_PRINT_SCREEN => ImGuiKey_PrintScreen,
    # GLFW.KEY_PAUSE => ImGuiKey_Pause,
    # GLFW.KEY_KP_0 => ImGuiKey_Keypad0,
    # GLFW.KEY_KP_1 => ImGuiKey_Keypad1,
    # GLFW.KEY_KP_2 => ImGuiKey_Keypad2,
    # GLFW.KEY_KP_3 => ImGuiKey_Keypad3,
    # GLFW.KEY_KP_4 => ImGuiKey_Keypad4,
    # GLFW.KEY_KP_5 => ImGuiKey_Keypad5,
    # GLFW.KEY_KP_6 => ImGuiKey_Keypad6,
    # GLFW.KEY_KP_7 => ImGuiKey_Keypad7,
    # GLFW.KEY_KP_8 => ImGuiKey_Keypad8,
    # GLFW.KEY_KP_9 => ImGuiKey_Keypad9,
    # GLFW.KEY_KP_DECIMAL => ImGuiKey_KeypadDecimal,
    # GLFW.KEY_KP_DIVIDE => ImGuiKey_KeypadDivide,
    # GLFW.KEY_KP_MULTIPLY => ImGuiKey_KeypadMultiply,
    # GLFW.KEY_KP_SUBTRACT => ImGuiKey_KeypadSubtract,
    # GLFW.KEY_KP_ADD => ImGuiKey_KeypadAdd,
    GLFW.KEY_KP_ENTER => ImGuiKey_KeyPadEnter,
    # GLFW.KEY_KP_EQUAL => ImGuiKey_KeypadEqual,
    # GLFW.KEY_LEFT_SHIFT => ImGuiKey_LeftShift,
    # GLFW.KEY_LEFT_CONTROL => ImGuiKey_LeftCtrl,
    # GLFW.KEY_LEFT_ALT => ImGuiKey_LeftAlt,
    # GLFW.KEY_LEFT_SUPER => ImGuiKey_LeftSuper,
    # GLFW.KEY_RIGHT_SHIFT => ImGuiKey_RightShift,
    # GLFW.KEY_RIGHT_CONTROL => ImGuiKey_RightCtrl,
    # GLFW.KEY_RIGHT_ALT => ImGuiKey_RightAlt,
    # GLFW.KEY_RIGHT_SUPER => ImGuiKey_RightSuper,
    # GLFW.KEY_MENU => ImGuiKey_Menu,
    # GLFW.KEY_0 => ImGuiKey_0,
    # GLFW.KEY_1 => ImGuiKey_1,
    # GLFW.KEY_2 => ImGuiKey_2,
    # GLFW.KEY_3 => ImGuiKey_3,
    # GLFW.KEY_4 => ImGuiKey_4,
    # GLFW.KEY_5 => ImGuiKey_5,
    # GLFW.KEY_6 => ImGuiKey_6,
    # GLFW.KEY_7 => ImGuiKey_7,
    # GLFW.KEY_8 => ImGuiKey_8,
    # GLFW.KEY_9 => ImGuiKey_9,
    GLFW.KEY_A => ImGuiKey_A,
    # GLFW.KEY_B => ImGuiKey_B,
    GLFW.KEY_C => ImGuiKey_C,
    # GLFW.KEY_D => ImGuiKey_D,
    # GLFW.KEY_E => ImGuiKey_E,
    # GLFW.KEY_F => ImGuiKey_F,
    # GLFW.KEY_G => ImGuiKey_G,
    # GLFW.KEY_H => ImGuiKey_H,
    # GLFW.KEY_I => ImGuiKey_I,
    # GLFW.KEY_J => ImGuiKey_J,
    # GLFW.KEY_K => ImGuiKey_K,
    # GLFW.KEY_L => ImGuiKey_L,
    # GLFW.KEY_M => ImGuiKey_M,
    # GLFW.KEY_N => ImGuiKey_N,
    # GLFW.KEY_O => ImGuiKey_O,
    # GLFW.KEY_P => ImGuiKey_P,
    # GLFW.KEY_Q => ImGuiKey_Q,
    # GLFW.KEY_R => ImGuiKey_R,
    # GLFW.KEY_S => ImGuiKey_S,
    # GLFW.KEY_T => ImGuiKey_T,
    # GLFW.KEY_U => ImGuiKey_U,
    GLFW.KEY_V => ImGuiKey_V,
    # GLFW.KEY_W => ImGuiKey_W,
    GLFW.KEY_X => ImGuiKey_X,
    GLFW.KEY_Y => ImGuiKey_Y,
    GLFW.KEY_Z => ImGuiKey_Z,
    # GLFW.KEY_F1 => ImGuiKey_F1,
    # GLFW.KEY_F2 => ImGuiKey_F2,
    # GLFW.KEY_F3 => ImGuiKey_F3,
    # GLFW.KEY_F4 => ImGuiKey_F4,
    # GLFW.KEY_F5 => ImGuiKey_F5,
    # GLFW.KEY_F6 => ImGuiKey_F6,
    # GLFW.KEY_F7 => ImGuiKey_F7,
    # GLFW.KEY_F8 => ImGuiKey_F8,
    # GLFW.KEY_F9 => ImGuiKey_F9,
    # GLFW.KEY_F10 => ImGuiKey_F10,
    # GLFW.KEY_F11 => ImGuiKey_F11,
    # GLFW.KEY_F12 => ImGuiKey_F12,
)
glfw_key_to_imgui(k::GLFW.Key)::ImGuiKey = get(GLFW_KEY_TO_IMGUI, k, ImGuiKey_None)

const CLIPBOARD_BUFFER = Vector{Char}(undef, 1024)
function gui_clipboard_get(::Ptr{Cvoid})::Ref
    clipboard_raw = clipboard()
    clipboard_str::String = (clipboard_raw isa String) ?
                                clipboard_raw :
                                String(clipboard_raw)
    str_len = length(clipboard_str)
    resize!(CLIPBOARD_BUFFER, str_len)
    GC.@preserve(clipboard_str,
        GC.@preserve(CLIPBOARD_BUFFER,
            unsafe_copyto!(CLIPBOARD_BUFFER, pointer(clipboard_str), str_len)
        )
    )
    return Ref(CLIPBOARD_BUFFER, 1)
end
function gui_clipboard_set(::Ptr{Cvoid}, chars::Ptr{UInt8})::Cvoid
    clipboard(unsafe_string(chars))
    return nothing
end
const GUI_CLIPBOARD_GET = @cfunction(gui_clipboard_get, Ptr{UInt8}, (Ptr{Cvoid}, ))
const GUI_CLIPBOARD_SET = @cfunction(gui_clipboard_set, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}))


"
Starts the GUI service.
You should only do this *after* setting up your own GLFW callbacks,
    as this GUI service will wrap them.
"
function service_gui_init(context::Bplus.GL.Context)
    serv = GuiService()

    # Report capabilities to CImGUI.
    gui_io::Ptr{ImGuiIO} = igGetIO()
    gui_io.BackendFlags |= unsafe_load(gui_io.BackendFlags) |
                               ImGuiBackendFlags_HasMouseCursors |
                               ImGuiBackendFlags_HasSetMousePos |
                               ImGuiBackendFlags_PlatformHasViewports
    gui_io.BackendPlatformName = pointer(BACKEND_NAME_INPUT)

    # Set up keybindings.
    set_keymap(im_gui, glfw) = unsafe_store!(Ptr{Int32}(io.KeyMap),
                                             glfw,
                                             Integer(im_gui) + 1)
    set_keymap(ImGuiKey_Tab, GLFW_KEY_TAB)
    set_keymap(ImGuiKey_LeftArrow, GLFW_KEY_LEFT)
    set_keymap(ImGuiKey_RightArrow, GLFW_KEY_RIGHT)
    set_keymap(ImGuiKey_UpArrow, GLFW_KEY_UP)
    set_keymap(ImGuiKey_DownArrow, GLFW_KEY_DOWN)
    set_keymap(ImGuiKey_PageUp, GLFW_KEY_PAGE_UP)
    set_keymap(ImGuiKey_PageDown, GLFW_KEY_PAGE_DOWN)
    set_keymap(ImGuiKey_Home, GLFW_KEY_HOME)
    set_keymap(ImGuiKey_End, GLFW_KEY_END)
    set_keymap(ImGuiKey_Insert, GLFW_KEY_INSERT)
    set_keymap(ImGuiKey_Delete, GLFW_KEY_DELETE)
    set_keymap(ImGuiKey_Backspace, GLFW_KEY_BACKSPACE)
    set_keymap(ImGuiKey_Space, GLFW_KEY_SPACE)
    set_keymap(ImGuiKey_Enter, GLFW_KEY_ENTER)
    set_keymap(ImGuiKey_Escape, GLFW_KEY_ESCAPE)
    set_keymap(ImGuiKey_KeyPadEnter, GLFW_KEY_KP_ENTER)
    set_keymap(ImGuiKey_A, GLFW_KEY_A)
    set_keymap(ImGuiKey_C, GLFW_KEY_C)
    set_keymap(ImGuiKey_V, GLFW_KEY_V)
    set_keymap(ImGuiKey_X, GLFW_KEY_X)
    set_keymap(ImGuiKey_Y, GLFW_KEY_Y)
    set_keymap(ImGuiKey_Z, GLFW_KEY_Z)

    # Set up the clipboard.
    gui_io.GetClipboardTextFn = GUI_CLIPBOARD_GET
    gui_io.SetClipboardTextFn = GUI_CLIPBOARD_SET

    # Configure the cursors to use.
    cursors = [
        (ImGuiMouseCursor_Arrow, GLFW.ARROW_CURSOR),
        (ImGuiMouseCursor_TextInput, GLFW.IBEAM_CURSOR),
        (ImGuiMouseCursor_ResizeNS, GLFW.VRESIZE_CURSOR),
        (ImGuiMouseCursor_ResizeEW, GLFW.HRESIZE_CURSOR),
        (ImGuiMouseCursor_Hand, GLFW.HAND_CURSOR),
        # In GLFW 3.4, there are new cursor images we could use.
        # However, that version isn't supported.
        (ImGuiMouseCursor_ResizeAll, GLFW.ARROW_CURSOR), # GLFW.RESIZE_ALL_CURSOR
        (ImGuiMouseCursor_ResizeNESW, GLFW.ARROW_CURSOR), # GLFW.RESIZE_NESW_CURSOR
        (ImGuiMouseCursor_ResizeNWSE, GLFW.ARROW_CURSOR), # GLFW.RESIZE_NWSE_CURSOR
        (ImGuiMouseCursor_NotAllowed, GLFW.ARROW_CURSOR) # GLFW.NOT_ALLOWED_CURSOR
    ]
    for (slot, type) in cursors
        # Remember that the libraries specify things in 0-based indices.
        serv.mouse_cursors[slot + 1] = GLFW.CreateStandardCursor(type)
    end

    # Point the ImGui viewport at the window.
    gui_viewport::Ptr{ImGuiViewport} = igGetMainViewport()
    gui_viewport.PlatformHandle = Ptr{Cvoid}(context.window.handle)

    # Tell ImGui how to manipulate/query windows.
    # Store the user's own GLFW callbacks, to be invoked inside ours.
    serv.prev_user_callback_monitor = GLFW.SetMonitorCallback(context.window, (monitor::GLFW.Monitor, i::Integer) -> begin
        if exists(serv.prev_user_callback_monitor)
            serv.prev_user_callback_monitor(monitor, i)
        end
        serv.should_update_monitors = true
        return nothing
    end)
    serv.prev_user_callback_char = GLFW.SetCharCallback(context.window, (window::GLFW.Window, c::Cuint) -> begin
        if exists(serv.prev_user_callback_char)
            serv.prev_user_callback_char(window, c)
        end
        if 0 < c < 0x10000 # Why this range? The example code doesn't explain.
            ImGuiIO_AddInputCharacter(igGetIO(), c)
        end
        return nothing
    end)
    serv.prev_user_callback_key = GLFW.SetKeyCallback(context.window, (window::GLFW.Window,
                                                                       key::Cint, scancode::Cint,
                                                                       action::GLFW.Action, mods::Cint) -> begin
        if exists(serv.prev_user_callback_key)
            serv.prev_user_callback_key(window, key, scancode, action, mods)
        end

        io::Ptr{ImGuiIO} = igGetIO()
        if (key - 1) in 1:length(unsafe_load(io.KeysDown))
            if action == GLFW.PRESS
                unsafe_store!(Ptr{Bool}(io.KeysDown), true, key + 1)
                serv.key_owner_windows[key + 1] = window
            elseif action == GLFW.RELEASE
                unsafe_store!(Ptr{Bool}(io.KeysDown), false, key + 1)
                serv.key_owner_windows[key + 1] = C_NULL
            end
        end

        # Modifiers are not reliable across systems.
        io.KeyCtrl = unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_LEFT_CONTROL + 1) ||
                     unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_RIGHT_CONTROL + 1)
        io.KeyShift = unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_LEFT_SHIFT + 1) ||
                      unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_RIGHT_SHIFT + 1)
        io.KeyAlt = unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_LEFT_ALT + 1) ||
                    unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_RIGHT_ALT + 1)
        if Sys.iswindows()
            io.KeySuper = false
        else
            io.KeySuper = unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_LEFT_SUPER + 1) ||
                          unsafe_load(Ptr{Bool}(io.KeysDown), GLFW.KEY_RIGHT_SUPER + 1)
        end

        return nothing
    end)
    serv.prev_user_callback_mousebutton = GLFW.SetMouseButtonCallback(context.window, (window, button,
                                                                                       action,  callback) -> begin
        if exists(serv.prev_user_callback_mousebutton)
            serv.prev_user_callback_mousebutton(window, button, action, callback)
        end

        if (button + 1) in 1:length(serv.mouse_just_pressed)
            if action == GLFW.PRESS
                serv.mouse_just_pressed[button + 1] = true
            end
        end

        return nothing
    end)
    serv.prev_user_callback_scroll = GLFW.SetScrollCallback(context.window, (window, x, y) -> begin
        if exists(serv.prev_user_callback_scroll)
            serv.prev_user_callback_scroll(window, x, y)
        end

        io::Ptr{ImGuiIO} = igGetIO()
        io.MouseWheelH = unsafe_load(io.MouseWheelH) + Cfloat(x)
        io.MouseWheel = unsafe_load(io.MouseWheel) + Cfloat(y)

        return nothing
    end)
    #TODO: Tell ImGUI how to create/destroy windows. These windows need to have GLFW callbacks set up similarly to this window, and need to play nicely with the Bplus Context.

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
function service_gui_get(context::Bplus.GL.Context)::GuiService
    return Bplus.GL.get_service(context, SERVICE_NAME_GUI)
end

function service_gui_cleanup(s::GuiService)
    for cursor in s.mouse_cursors
        GLFW.DestroyCursor(cursor)
    end
    empty!(s.mouse_cursors)

    # Un-wrwap the user's GLFW callbacks.
    GLFW.SetMonitorCallback(s.window, s.prev_user_callback_monitor)
    GLFW.SetCharCallback(s.window, s.prev_user_callback_char)
    GLFW.SetKeyCallback(s.window, s.prev_user_callback_key)
    GLFW.SetMouseButtonCallback(s.window, s.prev_user_callback_mousebutton)
    GLFW.SetScrollCallback(s.window, s.prev_user_callback_scroll)

    return nothing
end

service_gui_new_frame(context::Bplus.GL.Context = get_context()) = service_gui_new_frame(service_gui_get(context))
function service_gui_new_frame(serv::GuiService)
    io::Ptr{ImGuiIO} = igGetIO()
    @assert(ImFontAtlas_IsBuilt(unsafe_load(io.Fonts)),
            "Font atlas isn't built! This implies the renderer isn't initialized properly")

    # Set up the display size.
    window_size::v2i = get_window_size(serv.window)
    render_size::v2i = let render_size_glfw = GLFW.GetFramebufferSize(serv.window)
        v2i(render_size_glfw.width, render_size_glfw.height)
    end
    io.DisplaySize = ImVec2(Cfloat(window_size.x), Cfloat(window_size.y))
    if all(window_size > 0)
        render_scale::Vec2{Cfloat} = render_size / window_size
        io.DisplayFramebuffereScale = ImVec2(render_scale...)
    end

    if serv.should_update_monitors
        # Placeholder for when we add monitor/window control to the ImGUI backend
    end

    # Update mouse buttons.
    for i in 1:length(serv.mouse_just_pressed)
        # If a mouse press happened, always pass it as "mouse held this frame";
        #    otherwise we'd miss fast clicks.
        is_down::Bool = serv.mouse_just_pressed[i] ||
                        GLFW.GetMouseButton(serv.window, i - 1) == GLFW.PRESS
        unsafe_store!(Ptr{Bool}(io.MouseDown), is_down, i - 1)
        serv.mouse_just_pressed[i] = false
    end

    # Update mouse position.
    prev_mouse_pos  = unsafe_load(io.MousePos)
    max_float = igGET_FLT_MAX()
    io.MousePos = ImVec2(-max_float, -max_float)
    io.MouseHoveredViewport = 0
    io_platform::Ptr{ImGuiPlatformIO} = igGetPlatformIO()
    viewports_span = unsafe_load(io_platform.Viewports)
    viewport_ptrs = unsafe_wrap(Vector{Ptr{ImGuiViewport}},
                                viewports_span.Data, viewports_span.Size)
    for viewport::Ptr{ImGuiViewport} in viewport_ptrs
        window::GLFW.Window = GLFW.Window(unsafe_load(viewport.PlatformHandle))
        @assert(window.handle != C_NULL)

        # If this window is in focus, update its mouse position.
        if GLFW.GetWindowAttrib(window, GLFW.FOCUSED) != 0
            if unsafe_load(io.WantSetMousePos)
                GLFW.SetCursorPos(window,
                                  Cdouble(prev_mouse_pos.x - unsafe_load(viewport.Pos.x)),
                                  Cdouble(prev_mouse_pos.y - unsafe_load(viewport.Pos.y)))
            else
                cursor_pos_glfw = GLFW.GetCursorPos(window)
                cursor_pos = v2i(cursor_pos_glfw.x, cursor_pos_glfw.y)
                if (unsafe_load(io.ConfigFlags) & ImGuiConfigFlags_ViewportsEnable) == ImGuiConfigFlags_ViewportsEnable
                    # Multi-viewport mode: mouse position in OS absolute coordinates
                    #    (io.MousePos is relative to the upper-left of the primary monitor).
                    window_pos_glfw = GLFW.GetWindowPos(window)
                    window_pos = v2i(window_pos_glfw.x, window_pos_glfw.y)
                    io.MousePos = Imec2(Vec{2, Cfloat}(window_pos + cursor_pos)...)
                else
                    # Single viewport mode: mouse position is in client window coordinates
                    #    (io.MousePos is relative to the upper-left corner of the window).
                    io.MousePos = ImVec2(Vec{2, Cfloat}(cursor_pos)...)
                end
            end
        end

        # Update mouse input.
        for i in 1:length(serv.mouse_just_pressed)
            unsafe_store!(io.MouseDown,
                          unsafe_load(Ptr{Bool}(io.MouseDown), i) ||
                              (GLFW.GetMouseButton(window, i - 1) == GLFW.PRESS),
                          i)
        end
    end

    # Update the mouse cursor's image.
    if ((unsafe_load(io.ConfigFlags) & ImGuiConfigFlags_NoMouseCursorChange) != ImGuiConfigFlags_NoMouseCursorChange) &&
       (GLFW.GetInputMode(serv.window, GLFW.CURSOR) != GLFW.CURSOR_DISABLED)
    #begin
        imgui_cursor::Integer = igGetMouseCursor()
        platform_io::Ptr{ImGuiPlatformIO} = igGetPlatformIO()
        for viewport in viewport_ptrs
            window = unsafe_load(viewport.PlatformHandle)
            @assert(window.handle != C_NULL)

            # Hide the OS mouse cursor if ImGui is drawing it, or if it wants no cursor.
            if (imgui_cursor == ImGuiMouseCursor_None) || unsafe_load(io.MouseDrawCursor)
                GLFW.SetInputMode(window, GLFW.CURSOR, GLFW.CURSOR_HIDDEN)
            # Otherwise, make sure it's shown.
            else
                cursor = serv.mouse_cursors[imgui_cursor + 1]
                cursor_img = (cursor == C_NULL) ?
                                 serv.mouse_cursors[imgui_cursor + 1] :
                                 serv.mouse_cursors[ImGuiMouseCursor_Arrow + 1]
                GLFW.SetCursor(window, cursor_img)
                GLFW.SetInputMode(window, GLFW.CURSOR, GLFW.CURSOR_NORMAL)
            end
        end
    end

    return nothing
end