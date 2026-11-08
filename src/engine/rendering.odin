package engine

import "core:fmt"
import "core:strings"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:math/linalg/glsl"
import "core:math"
import "core:c"
import "core:sync"
import "base:runtime"
import "core:time"

import "vendor:glfw"
import stb_image "vendor:stb/image"
import gl "vendor:OpenGL"
import vk "vendor:vulkan"

import "./graphics"


DrawOperation_Type :: enum {
    WIREFRAME,
    OBJECT,
    RECTANGLE,
}

DrawOperation :: struct {
    type: DrawOperation_Type,
    pos: vec3,
    scale: vec3,
    color: vec4,
    asset: ^Asset,
    x,y,w,h: f32,
}

RenderPass :: struct {
    drawOperations: [dynamic]DrawOperation,
}

RenderState :: struct {
    window: glfw.WindowHandle,
    width, height: i32,

    ui_shader : ^Asset,
    object_shader : ^Asset,
    object_wireframe_shader : ^Asset,
    mesh_rect: graphics.Mesh,
    mesh_cube: graphics.Mesh,

    camera_position : vec3,
    camera_rotation : vec3,

    projection : mat4,

    char_asset : ^Asset,
    wierdBlock_asset : ^Asset,
    // texture: Texture,

    cube_asset : ^Asset,

    first_mx : bool,
    mx, my : i32,
    last_mx, last_my : i32,

    cursor_locked : bool,

    cameraSensitivity : f32,

    ui_pass: RenderPass,
    world_pass: RenderPass,

    graphicsState: graphics.GraphicsState,

}

render_init_window :: proc (state: ^EngineState) {
    render := &state.render_state
    
    render.cameraSensitivity = 0.16
    render.width = 800
    render.height = 600

    glfw.Init()

    window_name := "Wanderthaum: The Living World"
    window: glfw.WindowHandle

    switch render.graphicsState.renderBackend {
        case .OPENGL:
            // @TODO Move into opengl backend
            glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3);
            glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3);
            glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE);
            
            window = glfw.CreateWindow(render.width, render.height, strings.clone_to_cstring(window_name), nil, nil)

        case .VULKAN:
            window = graphics.vulkan_init_window(&render.graphicsState.vulkanBackend, cast(int)render.width, cast(int)render.height, window_name)
    }

    glfw.SetWindowUserPointer(window, state)

    // hyprland may change the window size even if
    // we specify 800x600 when creating window.
    // We make sure to get the real size here.
    render.width, render.height = glfw.GetWindowSize(window)

    set_glfw_globals(render, window)

    glfw.SwapInterval(0)

    // render.ui_shader        = register_asset_from_store(state, "ui_shader",     "shaders/ui_vulkan.glsl")
    render.ui_shader        = register_asset_from_store(state, "ui_shader",     "shaders/ui.glsl")
    // render.object_shader    = register_asset_from_store(state, "object_shader", "shaders/object.glsl")
    // render.object_wireframe_shader = register_asset_from_store(state, "object_wireframe_shader", "shaders/object_wireframe.glsl")
    // render.wierdBlock_asset = register_asset_from_store(state, "block",         "models/block.glb")
    // render.char_asset       = register_asset_from_store(state, "iuno",          "models/character_trim.glb")
    // render.cube_asset       = register_asset_from_store(state, "cube",          "models/cube.glb")
    // render.cube_asset       = register_asset_empty(     state, "cube")

    // @IMPORTANT Set this last, this indicates to render thread that we can now MakeContextCurrent and do gl calls
    sync.atomic_store(&render.window, window)
}


init_render_state :: proc (state: ^EngineState) {
    render := &state.render_state

    switch render.graphicsState.renderBackend {
        case .OPENGL:
            // @TODO Move into opengl backend
            glfw.MakeContextCurrent(render.window)
            set_opengl_globals()
        
        case .VULKAN:
            graphics.vulkan_init_upfront_internals(&render.graphicsState.vulkanBackend)
    }

    // render.ui_shader = load_shader(ui_path)
    // render.object_shader = load_shader(object_path)

    render.mesh_rect = create_rect(state)
    render.mesh_cube = create_cube(state)

    // cubeModel := create_cube_model()
    // update_empty_asset(state, render.cube_asset, cubeModel)

    // block_path := "assets/models/block.glb"
    // block_path := "assets/models/cube.glb"
    // render.block_model = load_model(block_path)

    
    
    // render.texture = load_texture("C:/Users/emarioo/Downloads/尤诺/textures/Face_D.png")
    // render.texture = render.char_model.meshes[0].material.base_texture
}


tick_input :: proc (engineState: ^EngineState) {
    // We must initialize the GLFW window on the main thread.
    //   We are being cheeky and do it on a separate input thread
    //   and the important part is that we call glfw.PollEvents on
    //   the same thread.
    if engineState.render_state.window == nil {
        render_init_window(engineState)
    }

    if engineState.render_state.window != nil {
        if sync.atomic_load(&engineState.reset_glfw_globals) {
            set_glfw_globals(&engineState.render_state)
            sync.atomic_store(&engineState.reset_glfw_globals, false)
        }

        glfw.PollEvents()
    }

    time.sleep(5 * time.Millisecond)
}

// Shader :: struct {
//     program: u32,
//     uniforms: gl.Uniforms,
// }

// Texture :: struct {
//     id: u32,
//     width: u32,
//     height: u32,
//     raw_data: [^]u8,
// }

set_glfw_globals :: proc (render: ^RenderState, opt_window: glfw.WindowHandle = nil) {
    window := render.window
    if opt_window != nil {
        window = opt_window
    }
    glfw.SetKeyCallback(window, KeyProc)
    glfw.SetMouseButtonCallback(window, MouseButtonProc)
    glfw.SetCursorPosCallback(window, CursorPosProc)
    glfw.SetScrollCallback(window, ScrollProc)
    glfw.SetWindowSizeCallback(window, WindowSizeProc)
    glfw.SetFramebufferSizeCallback(window, FrameBufferResizeProc)
}

set_opengl_globals :: proc () {
    gl.load_up_to(4, 5, glfw.gl_set_proc_address);
}

KeyProc          :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: c.int) {
    context = runtime.default_context()

    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
        render_state.cursor_locked = !render_state.cursor_locked
        
        if render_state.cursor_locked {
            assert(cast(bool)glfw.RawMouseMotionSupported())
            glfw.SetInputMode(render_state.window, glfw.CURSOR, glfw.CURSOR_DISABLED);
            glfw.SetInputMode(render_state.window, glfw.RAW_MOUSE_MOTION, 1);
        } else {
            glfw.SetInputMode(render_state.window, glfw.CURSOR, glfw.CURSOR_NORMAL);
            glfw.SetInputMode(render_state.window, glfw.RAW_MOUSE_MOTION, 0);
        }
    }
    
    actor := &engine.inputState.actors[0]


    setInputAction :: proc (actor: ^Input_Actor, inputAction: Input_Generic_Action, action: c.int) {
        actor.temp_actions[inputAction].value = cast(i32)(action != glfw.RELEASE)
        if action == glfw.PRESS {
            actor.temp_actions[inputAction].pressed += 1
        }
    }

    shiftMod := (mods & glfw.MOD_SHIFT) != 0
    controlMod := (mods & glfw.MOD_CONTROL) != 0

    for ki in 0..<len(actor.keymap.entries) {
        entry := &actor.keymap.entries[ki]

        if entry.key == cast(u32)key {
            if entry.shift && shiftMod {
                setInputAction(actor, entry.action, action)
                break
            } else if entry.control && controlMod {
                setInputAction(actor, entry.action, action)
                break
            } else if !entry.shift {
                setInputAction(actor, entry.action, action)
            }
        }
    }
    // fmt.printfln("move %v",global_render_state.move)

    // fmt.println("key",key,scancode,action,mods)
}
MouseButtonProc  :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
    context = runtime.default_context()
    
    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state
    
    
    actor := &engine.inputState.actors[0]

    setInputAction :: proc (actor: ^Input_Actor, inputAction: Input_Generic_Action, action: c.int) {
        actor.temp_actions[inputAction].value = cast(i32)(action != glfw.RELEASE)
        if action == glfw.PRESS {
            actor.temp_actions[inputAction].pressed += 1
        }
    }
    // fmt.println("mbutton", button, action, mods)


    shiftMod := (mods & glfw.MOD_SHIFT) != 0
    controlMod := (mods & glfw.MOD_CONTROL) != 0

    key : Input_Generic_Action = glfw.KEY_LAST + 1 + cast(u32)button
    
    for ki in 0..<len(actor.keymap.entries) {
        entry := &actor.keymap.entries[ki]

        if entry.key == key {
            if entry.shift && shiftMod {
                setInputAction(actor, entry.action, action)
                break
            } else if entry.control && controlMod {
                setInputAction(actor, entry.action, action)
                break
            } else if !entry.shift {
                setInputAction(actor, entry.action, action)
            }
        }
    }

    // if button == 0 {
    //     setInputAction(actor, Input_Action.PRIMARY_ACTION, action)
    // }
    // if button == 1 {
    //     setInputAction(actor, Input_Action.SECONDARY_ACTION, action)
    // }
    // if button == 2 {
    //     setInputAction(actor, Input_Action.THIRD_ACTION, action)
    // }
}
CursorPosProc    :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
    context = runtime.default_context()
    
    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    render_state.mx = cast(i32)xpos
    render_state.my = cast(i32)ypos

    actor := &engine.inputState.actors[0]

    for ki in 0..<len(actor.keymap.entries) {
        entry := &actor.keymap.entries[ki]

        if entry.key == PHYSICAL_KEY_POINTER_X {
            actor.temp_actions[entry.action].value = cast(i32)xpos
        }
        if entry.key == PHYSICAL_KEY_POINTER_Y {
            actor.temp_actions[entry.action].value = cast(i32)ypos
        }
    }
    // fmt.println(xpos, ypos)
    // fmt.println("diff",global_render_state.mx-global_render_state.last_mx, global_render_state.my-global_render_state.last_my)
}
ScrollProc       :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
    context = runtime.default_context()

    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    actor := &engine.inputState.actors[0]
    
    for ki in 0..<len(actor.keymap.entries) {
        entry := &actor.keymap.entries[ki]

        if entry.key == PHYSICAL_KEY_SCROLLED_X {
            actor.temp_actions[entry.action].value = cast(i32)xoffset
            actor.temp_actions[entry.action].pressed += cast(i32)xoffset
        }
        if entry.key == PHYSICAL_KEY_SCROLLED_Y {
            actor.temp_actions[entry.action].value = cast(i32)yoffset
            actor.temp_actions[entry.action].pressed += cast(i32)yoffset
        }
    }

    // fmt.printfln("scroll", xoffset, yoffset)
}
WindowSizeProc   :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
    context = runtime.default_context()

    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    render_state.width = cast(i32)width
    render_state.height = cast(i32)height
    // fmt.println("Windows size: ", width, " ", height);
}
FrameBufferResizeProc   :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
    context = runtime.default_context()

    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    // render_state.width = cast(i32)width
    // render_state.height = cast(i32)height
    fmt.println("Frame buffer resize: ", width, " ", height);
    // @TODO Set  state.frame_resized = true
}


load_texture :: proc {
    load_texture_from_file,
    load_texture_from_buffer,
}

load_texture_from_file :: proc (path: string, texture: ^graphics.Texture) {
    bytes, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("Could not open",path)
        os.exit(1)
    }

    load_texture_from_buffer(bytes, texture)

    fmt.printf("Loaded texture '%s'\n", path)
}
load_texture_from_buffer :: proc (data: []u8, texture: ^graphics.Texture) {
    if texture.raw_data != nil {
        stb_image.image_free(texture.raw_data)
        texture.raw_data = nil
    }

    stb_image.set_flip_vertically_on_load(1)

    width, height, channels: i32
    buffer := stb_image.load_from_memory(raw_data(data), cast(i32)len(data), &width, &height, &channels, 4)
    // @TODO Memory leak

    texture.width = cast(u32)width
    texture.height = cast(u32)height
    texture.raw_data = buffer
}

init_texture_render :: proc (texture: ^graphics.Texture) {
    if texture.id != 0 {
        gl.DeleteTextures(1, &texture.id)
    }

    gl.GenTextures(1, &texture.id)
    gl.BindTexture(gl.TEXTURE_2D, texture.id)

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    // start := time.now()
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, cast(i32)texture.width, cast(i32)texture.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, texture.raw_data)
    // gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, cast(i32)texture.width, cast(i32)texture.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    // end := time.now()
    
    // fmt.printfln("texture %v", time.diff(start, end))

    gl.BindTexture(gl.TEXTURE_2D, 0)

    stb_image.image_free(texture.raw_data)
    texture.raw_data = nil
}

update_projection :: proc (render : ^RenderState) {
    projection := glsl.mat4Perspective( 90.0/(180/math.PI), cast(f32)render.width/cast(f32)render.height, 0.02, 400)
    model_view := glsl.inverse_mat4(
        glsl.mat4Translate(render.camera_position) * 
        glsl.mat4Rotate(vec3{0,1,0}, render.camera_rotation.y) * 
        glsl.mat4Rotate(vec3{1,0,0}, render.camera_rotation.x)
    )
    render.projection = projection * model_view
}

update_camera :: proc (render : ^RenderState) {
    if render.cursor_locked {
        if !render.first_mx {
            render.last_mx = render.mx
            render.last_my = render.my
            render.first_mx = true
        }
        dx := render.mx - render.last_mx
        dy := render.my - render.last_my
        // fmt.println(dx, dy)
        rawX := -cast(f32)(dx) * (math.PI / 360.0) * render.cameraSensitivity;
        rawY := -cast(f32)(dy) * (math.PI / 360.0) * render.cameraSensitivity;
        // e.window->m_tickRawMouseX += rawX;
        // e.window->m_frameRawMouseX += rawX;
        // e.window->m_tickRawMouseY += rawY;
        // e.window->m_frameRawMouseY += rawY;

        rot := render.camera_rotation
        rot.y += rawX;
        rot.x += rawY;
        // clamp up and down directions.
        if (rot.x > math.PI / 2) {
            rot.x = math.PI / 2;
        }
        if (rot.x < -math.PI / 2) {
            rot.x = -math.PI / 2;
        }
        rot.x = math.remainder_f32(rot.x, math.PI * 2);
        rot.y = math.remainder_f32(rot.y, math.PI * 2);
        render.camera_rotation = rot
    }
    // Last mouse pos shall be set even when
    // we aren't in "focused" mode
    render.last_mx = render.mx
    render.last_my = render.my

}

set_vulkan_globals :: proc () { }

render_state_begin :: proc (engineState: ^EngineState) {

    if !sync.atomic_load(&engineState.has_init_render) {
        sync.mutex_lock(&engineState.someRenderMutex)
        if !sync.atomic_load(&engineState.has_init_render) {
            init_render_state(engineState)
            sync.atomic_store(&engineState.has_init_render, true)
        }
        sync.mutex_unlock(&engineState.someRenderMutex)
    }
    
    if sync.atomic_load(&engineState.reset_opengl_globals) {
        sync.mutex_lock(&engineState.someRenderMutex)
        if sync.atomic_load(&engineState.reset_opengl_globals) {
            set_opengl_globals()
            sync.atomic_store(&engineState.reset_opengl_globals, false)
        }
        sync.mutex_unlock(&engineState.someRenderMutex)
    }
     if sync.atomic_load(&engineState.reset_vulkan_globals) {
        sync.mutex_lock(&engineState.someRenderMutex)
        if sync.atomic_load(&engineState.reset_vulkan_globals) {
            set_vulkan_globals()
            sync.atomic_store(&engineState.reset_vulkan_globals, false)
        }
        sync.mutex_unlock(&engineState.someRenderMutex)
    }
}

render_state :: proc (state: ^EngineState) {
    render := &state.render_state

    if glfw.WindowShouldClose(render.window) {
        fmt.println("closing window")
        state.running = false
        return
    }

    
    update_camera(render)
    update_projection(render)

    switch render.graphicsState.renderBackend {
        case .OPENGL:
            gl.ClipControl(gl.UPPER_LEFT, gl.ZERO_TO_ONE)
            gl.Viewport(0, 0, render.width, render.height)
            gl.ClearColor(0.3,0.5,0.6,1.0)
            gl.Clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT)

            // cull face
            // depth alpha
            gl.Disable(gl.CULL_FACE)
            gl.Disable(gl.DEPTH_TEST)
            // gl.Enable(gl.CULL_FACE)
            // gl.Enable(gl.DEPTH_TEST)

            // diff := cast(f32)(time.time_to_unix_nano(time.now()) - time.time_to_unix_nano(state.startTime)) / 1.0e9
            // render_rect(state, cast(f32)render.width/2 - 25 + math.cos(2*diff) * cast(f32)(render.width/2-50), cast(f32)render.height/2 - 25 + math.sin(2*diff) * cast(f32)(render.height/2-50), 50, 50, {1, 0.2, 0.2, 1})
            // render_rect(state, 900 + diff * 20, 1000, 500, 500, {1, 0.2, 0.2, 1})
            // render_rect(state, 400 + diff * 20, 300, 500, 500, {1, 0.2, 0.2, 1})
            // color: vec4 = {1, 1, 1, 1}
            color: vec4 = {1, 0.2, 0.2, 1}
            render_rect(state, 50, 0, 100, 100, color)

            // render_model(state, render.block_model, vec3{ 0, 0, -3 }, vec3{1,1,1})
            // render_model(state, render.char_asset.model, vec3{ 0, -1, -1 }, vec3{1,1,1})

            // render entities
            
            // for i in 0..<get_entity_count(state) {
            //     entity := get_entity_by_index(state, i)

            //     if entity.hidden || entity.killed || entity.asset == nil {
            //         continue
            //     }

            //     render_model(state, entity.asset.model, entity.pos, entity.scale)
            // }


            gl.Enable(gl.CULL_FACE)
            gl.Enable(gl.DEPTH_TEST)

            for i in 0..<len(render.world_pass.drawOperations) {
                op := &render.world_pass.drawOperations[i]
                if op.type == .WIREFRAME {
                    render_wireframe(state, op.pos, op.scale, op.color.xyz)
                } else if op.type == .OBJECT {
                    render_model(state, op.asset.model, op.pos, op.scale)
                }
            }

            gl.Disable(gl.CULL_FACE)
            gl.Disable(gl.DEPTH_TEST)

            for i in 0..<len(render.ui_pass.drawOperations) {
                op := &render.ui_pass.drawOperations[i]
                if op.type == .RECTANGLE {
                    render_rect(state, op.x, op.y, op.w, op.h, op.color)
                }
            }

            clear(&render.world_pass.drawOperations)
            clear(&render.ui_pass.drawOperations)
            
            glfw.SwapBuffers(render.window)
        
        case .VULKAN:
            res: vk.Result
            backend := &render.graphicsState.vulkanBackend

            vk.WaitForFences(backend.device, 1, &backend.fence_inFlight[backend.currentFrame], true, max(u64))

            imageIndex: u32
            res = vk.AcquireNextImageKHR(backend.device, backend.swapchain, max(u64), backend.sem_imageAvailable[backend.currentFrame], 0, &imageIndex)
            if res == .ERROR_OUT_OF_DATE_KHR {
                fmt.println("Resized1")
                graphics.recreate_swapchain(backend)
                break
            } else if (res != .SUCCESS && res != .SUBOPTIMAL_KHR) {
                graphics.check_error(res, "failed acquire next image")
            }
            vk.ResetFences(backend.device, 1, &backend.fence_inFlight[backend.currentFrame])



            if render.ui_shader.shader != nil {
                shader := &render.ui_shader.shader.internal.(graphics.vulkan_Shader)

                if !backend.made_pipeline {
                    graphics.create_pipeline(backend, shader.vert_shader, shader.frag_shader, &render.mesh_rect.vertexLayout)
                    backend.made_pipeline = true
                }
                
                vk.ResetCommandBuffer(backend.commandBuffers[backend.currentFrame], {})

                // gl.UseProgram(shader.program)

                // gl.Uniform2f(shader.uniforms["uWindow"].location, cast(f32)render.width, cast(f32)render.height)
                // gl.Uniform2f(shader.uniforms["uPos"].location, x, y)
                // gl.Uniform2f(shader.uniforms["uSize"].location, w, h)
                // gl.Uniform4f(shader.uniforms["uColor"].location, color.r, color.g, color.b, color.a)
                // gl.Uniform1i(render.ui_shader.uniforms["uSampler"].location, 0)

                // gl.ActiveTexture(gl.TEXTURE0)
                // gl.BindTexture(gl.TEXTURE_2D, render.texture.id)

                // gl.BindVertexArray(render.mesh_rect.vertexLayout.internal.(graphics.opengl_VertexArrayObject).vao)
                // gl.DrawArrays(gl.TRIANGLES, 0, 6)
                
                // color: vec4 = {1, 0.2, 0.2, 1}
                color: vec4 = {0, 1.0, 1.0, 1.0}
                // render_rect(state, 50, 0, 100, 100, color)

                push: graphics.Rect_Push_Constants = {
                    color  = {color.r, color.g, color.b, color.a},
                    window = {cast(f32)render.width, cast(f32)render.height},
                    pos    = {50, 0},
                    size   = {100, 100},
                }
                
                graphics.record_command_buffer(backend, backend.commandBuffers[backend.currentFrame], imageIndex, &render.mesh_rect, &push)

                waitStages: [1]vk.PipelineStageFlags = { { .COLOR_ATTACHMENT_OUTPUT } }
                submitInfo: vk.SubmitInfo = {
                    sType = .SUBMIT_INFO,
                    waitSemaphoreCount = 1,
                    pWaitSemaphores = &backend.sem_imageAvailable[backend.currentFrame],
                    pWaitDstStageMask = &waitStages[0],
                    commandBufferCount = 1,
                    pCommandBuffers = &backend.commandBuffers[backend.currentFrame],
                    signalSemaphoreCount = 1,
                    pSignalSemaphores = &backend.sem_renderFinished[backend.currentFrame],
                }

                res = vk.QueueSubmit(backend.graphicsQueue, 1, &submitInfo, backend.fence_inFlight[backend.currentFrame])
                graphics.check_error(res, "failed submit queue")
            }




            presentInfo: vk.PresentInfoKHR = {
                sType = .PRESENT_INFO_KHR,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &backend.sem_renderFinished[backend.currentFrame],
                swapchainCount = 1,
                pSwapchains = &backend.swapchain,
                pImageIndices = &imageIndex,
                pResults = nil, // optional
            }

            // @TODO Present and graphics queue are assumed to be the same. (a problem?)
            res = vk.QueuePresentKHR(backend.graphicsQueue, &presentInfo)
            if res == .ERROR_OUT_OF_DATE_KHR || backend.frame_resized {
                // @TODO I don't think the resize is working. The triangle looks pixelated when scaled up.
                //   Do we render once and then continously fail? try make moving triangle to see if we render.
                fmt.println("Resized")
                backend.frame_resized = false
                graphics.recreate_swapchain(backend)
            } else if (res != .SUCCESS && res != .SUBOPTIMAL_KHR) {
                graphics.check_error(res, "failed acquire next image")
            }

            clear(&render.world_pass.drawOperations)
            clear(&render.ui_pass.drawOperations)

            
            backend.currentFrame = (backend.currentFrame + 1) % graphics.MAX_FRAMES_IN_FLIGHT

    }
}


// render_state_end :: proc (state: ^EngineState) {
//     render := &state.render_state


//     gl.Enable(gl.CULL_FACE)
//     gl.Enable(gl.DEPTH_TEST)

//     for i in 0..<len(render.world_pass.drawOperations) {
//         op := &render.world_pass.drawOperations[i]
//         if op.type == .WIREFRAME {
//             render_wireframe(state, op.pos, op.scale, op.color.xyz)
//         } else if op.type == .OBJECT {
//             render_model(state, op.asset.model, op.pos, op.scale)
//         }
//     }

//     gl.Disable(gl.CULL_FACE)
//     gl.Disable(gl.DEPTH_TEST)

//     for i in 0..<len(render.ui_pass.drawOperations) {
//         op := &render.ui_pass.drawOperations[i]
//         if op.type == .RECTANGLE {
//             render_rect(state, op.x, op.y, op.w, op.h, op.color)
//         }
//     }

//     clear(&render.world_pass.drawOperations)
//     clear(&render.ui_pass.drawOperations)
    
//     glfw.SwapBuffers(render.window)
// }

submit_model :: proc (state: ^EngineState, asset: ^Asset, pos: vec3, scale: vec3) {
    render := &state.render_state

    if asset == nil {
        return
    }

    drawOperation: DrawOperation = {
        type = .OBJECT,
        pos = pos,
        scale = scale,
        asset = asset,
    }

    append(&render.world_pass.drawOperations, drawOperation)
}

render_model :: proc (state: ^EngineState, model: ^Model, pos: vec3, scale: vec3) {
    render := &state.render_state

    if model == nil {
        return
    }

    if render.object_shader.shader == nil {
        return
    }

    // @NOCHECKIN Fix
    // gl.UseProgram(render.object_shader.shader.program)

    // transform := glsl.mat4Translate(pos) * glsl.mat4Scale(scale)

    // gl.UniformMatrix4fv(render.object_shader.shader.uniforms["uTransform"].location, 1, false, transmute([^]f32) &transform)
    // gl.UniformMatrix4fv(render.object_shader.shader.uniforms["uProjection"].location, 1, false,  transmute([^]f32) &render.projection)
    // // gl.Uniform3f(render.object_shader.shader.uniforms["uCameraPos"].location,
    //     // render.camera_position.x, render.camera_position.y, render.camera_position.z)


    // for i in 0..<len(model.meshes) {
    //     mesh := &model.meshes[i]
        
    //     if mesh.material.useTexture {
    //         gl.ActiveTexture(gl.TEXTURE0)
    //         gl.BindTexture(gl.TEXTURE_2D, mesh.material.base_texture.id)

    //         gl.Uniform1i(render.object_shader.shader.uniforms["use_diffuseMap"].location, 1)
    //         gl.Uniform1i(render.object_shader.shader.uniforms["diffuse_map"].location, 0)
    //     } else {
    //         gl.Uniform1i(render.object_shader.shader.uniforms["use_diffuseMap"].location, 0)
    //         gl.Uniform3f(render.object_shader.shader.uniforms["diffuse_color"].location,
    //             mesh.material.diffuse.x, mesh.material.diffuse.y, mesh.material.diffuse.z)
    //     }
    //     gl.BindVertexArray(mesh.vao)
    //     gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
    // }
}


submit_rect :: proc (state: ^EngineState, x,y,w,h: f32, color: [4]f32) {
    render := &state.render_state

    drawOperation: DrawOperation = {
        type = .RECTANGLE,
        x = x,
        y = y,
        w = w,
        h = h,
        color = color,
    }

    append(&render.ui_pass.drawOperations, drawOperation)
}

render_rect :: proc (state: ^EngineState, x,y,w,h: f32, color: [4]f32) {
    render := &state.render_state

    if render.ui_shader.shader == nil {
        return
    }

    switch render.graphicsState.renderBackend {
        case .OPENGL:

            shader := &render.ui_shader.shader.internal.(graphics.opengl_Shader)

            gl.UseProgram(shader.program)

            gl.Uniform2f(shader.uniforms["pc.fields.window"].location, cast(f32)render.width, cast(f32)render.height)
            gl.Uniform2f(shader.uniforms["pc.fields.pos"].location, x, y)
            gl.Uniform2f(shader.uniforms["pc.fields.size"].location, w, h)
            gl.Uniform4f(shader.uniforms["pc.fields.color"].location, color.r, color.g, color.b, color.a)
            // gl.Uniform1i(render.ui_shader.uniforms["uSampler"].location, 0)

            // gl.ActiveTexture(gl.TEXTURE0)
            // gl.BindTexture(gl.TEXTURE_2D, render.texture.id)

            gl.BindVertexArray(render.mesh_rect.vertexLayout.internal.(graphics.opengl_VertexArrayObject).vao)
            gl.DrawArrays(gl.TRIANGLES, 0, 6)

        case .VULKAN:
            
    }
}

submit_wireframe :: proc (state: ^EngineState, pos: vec3, scale: vec3, color: [3]f32) {
    render := &state.render_state

    drawOperation: DrawOperation = {
        type = .WIREFRAME,
        pos = pos,
        scale = scale,
        color = {color.x,color.y,color.z,1},
    }

    append(&render.world_pass.drawOperations, drawOperation)
}

render_wireframe :: proc (state: ^EngineState, pos: vec3, scale: vec3, color: [3]f32) {
    render := &state.render_state

    if render.object_wireframe_shader.shader == nil {
        return
    }
    // @NOCHECKIN Fix

    // gl.UseProgram(render.object_wireframe_shader.shader.program)

    // transform := glsl.mat4Translate(pos) * glsl.mat4Scale(scale)
    
    // mesh := &render.mesh_cube

    // gl.UniformMatrix4fv(render.object_wireframe_shader.shader.uniforms["uTransform"].location, 1, false, transmute([^]f32) &transform)
    // gl.UniformMatrix4fv(render.object_wireframe_shader.shader.uniforms["uProjection"].location, 1, false,  transmute([^]f32) &render.projection)
    // gl.Uniform3f(render.object_wireframe_shader.shader.uniforms["wireframe_color"].location, color.x, color.y, color.z)

    // gl.BindVertexArray(mesh.vao)
    // gl.DrawElements(gl.LINES, mesh.index_count, gl.UNSIGNED_INT, nil)
}


create_rect :: proc (state: ^EngineState) -> (mesh: graphics.Mesh) {
    vertex_data: []f32 = {
        //   pos
        0.0, 0.0,
        1.0, 0.0,
        0.0, 1.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
        
        // 0.1, 0.1,
        // 0.4, 0.1,
        // 0.1, 0.4,
        // 0.4, 0.1,
        // 0.4, 0.4,
        // 0.1, 0.4,
    }

    attributes: []graphics.VertexAttribute = {
        { 0, .FLOAT32_2 }
    }

    graphics.make_mesh(&state.render_state.graphicsState, vertex_data, {}, attributes, &mesh)

    return
}

create_cube :: proc (state: ^EngineState) -> (mesh: graphics.Mesh) {

    CUBE_EDGES : [12][2]u32 = {
        {0, 1}, {1, 2}, {2, 3}, {3, 0},
        {4, 5}, {5, 6}, {6, 7}, {7, 4},
        {0, 4}, {1, 5}, {2, 6}, {3, 7},
    }

    CUBE_VERTICES : [8]vec3 = {
        {-0.5, -0.5, -0.5},
        { 0.5, -0.5, -0.5},
        { 0.5,  0.5, -0.5},
        {-0.5,  0.5, -0.5},
        {-0.5, -0.5,  0.5},
        { 0.5, -0.5,  0.5},
        { 0.5,  0.5,  0.5},
        {-0.5,  0.5,  0.5},
    }

    vertices := slice.from_ptr(&CUBE_VERTICES[0].x, len(CUBE_VERTICES) * 3)
    indices  := slice.from_ptr(&CUBE_EDGES[0][0], len(CUBE_EDGES) * 2)

    attributes: []graphics.VertexAttribute = {
        { 0, .FLOAT32_3 }
    }

    graphics.make_mesh(&state.render_state.graphicsState, vertices, indices, attributes, &mesh)

    // gl.GenVertexArrays(1, &mesh.vao)
    // gl.GenBuffers     (1, &mesh.vbo)
    // gl.GenBuffers     (1, &mesh.ibo)

    // gl.BindVertexArray(mesh.vao)

    // gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
    // gl.BufferData(gl.ARRAY_BUFFER, len(CUBE_VERTICES) * size_of(vec3), transmute(^f32)&CUBE_VERTICES[0], gl.STATIC_DRAW)

    // gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo)
    // gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(CUBE_EDGES) * 2 * size_of(u32), transmute(^f32)&CUBE_EDGES[0], gl.STATIC_DRAW)

    // // position attribute
	// gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(f32) * 3, cast(uintptr)0)
	// gl.EnableVertexAttribArray(0)

    // gl.BindVertexArray(0)

    // mesh.index_count = len(CUBE_EDGES) * 2
    // mesh.vertex_count = len(CUBE_VERTICES)

    return
}
