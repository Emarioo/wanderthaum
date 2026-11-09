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
    windowPosX, windowPosY: i32,
    hasPreviousWindowPos: bool,

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


    initialized_once: bool,
}



render_init_window :: proc (state: ^EngineState) {
    render := &state.render_state

    if !render.initialized_once {
    
        render.cameraSensitivity = 0.16
        render.width = 800
        render.height = 600

        glfw.Init()

        render.ui_shader        = register_asset_from_store(state, "ui_shader",     "shaders/ui.glsl")
        render.object_shader    = register_asset_from_store(state, "object_shader", "shaders/object.glsl")
        render.object_wireframe_shader = register_asset_from_store(state, "object_wireframe_shader", "shaders/object_wireframe.glsl")
        render.wierdBlock_asset = register_asset_from_store(state, "block",         "models/block.glb")
        render.char_asset       = register_asset_from_store(state, "iuno",          "models/character_trim.glb")
        render.cube_asset       = register_asset_from_store(state, "cube",          "models/cube.glb")
        // render.cube_asset       = register_asset_empty(     state, "cube")

        render.initialized_once = true
    }


    window_name := "Wanderthaum: The Living World"
    window: glfw.WindowHandle

    switch render.graphicsState.renderBackend {
        case .OPENGL:
            // @TODO Move into opengl backend
            glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3);
            glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3);
            glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE);
            glfw.WindowHint(glfw.CLIENT_API, glfw.OPENGL_API);
            
            // @TODO MEMORY LEAK! Free cloned cstring
            window = glfw.CreateWindow(render.width, render.height, strings.clone_to_cstring(window_name), nil, nil)

        case .VULKAN:
            window = graphics.vulkan_init_window(&render.graphicsState.vulkanBackend, cast(int)render.width, cast(int)render.height, window_name)
    }

    if state.render_state.hasPreviousWindowPos {
        glfw.SetWindowPos(window, state.render_state.windowPosX, state.render_state.windowPosY)
    }

    glfw.SetWindowUserPointer(window, state)

    state.render_state.cursor_locked = false

    // hyprland may change the window size even if
    // we specify 800x600 when creating window.
    // We make sure to get the real size here.
    render.width, render.height = glfw.GetWindowSize(window)

    set_glfw_globals(render, window)

    // @IMPORTANT Set this last, this indicates to render thread that we can now MakeContextCurrent and do gl calls
    sync.atomic_store(&render.window, window)
}




init_render_state :: proc (state: ^EngineState) {
    render := &state.render_state

    switch render.graphicsState.renderBackend {
        case .OPENGL:
            // @TODO Move into opengl backend
            // fmt.println(glfw.GetWindowAttrib(render.window, glfw.CLIENT_API))
            glfw.MakeContextCurrent(render.window)
            glfw.SwapInterval(0)
            // fmt.println(glfw.GetCurrentContext() == render.window)
            set_opengl_globals()
            // fmt.println(gl.GetString(gl.VERSION))
            // fmt.println(gl.GetString(gl.RENDERER))
        
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

destroy_all_window_resources :: proc (engineState: ^EngineState) {
    engineState.render_state.windowPosX, engineState.render_state.windowPosY = glfw.GetWindowPos(engineState.render_state.window)
    engineState.render_state.hasPreviousWindowPos = true
    glfw.DestroyWindow(engineState.render_state.window)
    engineState.render_state.window = nil
}

tick_input :: proc (engineState: ^EngineState) {

    if sync.atomic_load(&engineState.switchingBackend) {
        if sync.atomic_load(&engineState.destroyed_all_input_resources) {
            sync.mutex_lock(&engineState.someRenderMutex)
            defer sync.mutex_unlock(&engineState.someRenderMutex)

            if sync.atomic_load(&engineState.destroyed_all_input_resources) {
                destroy_all_window_resources(engineState)
                engineState.render_state.graphicsState.renderBackend = engineState.queued_renderbackend
                
                engineState.has_init_render = false
                sync.atomic_store(&engineState.destroyed_all_input_resources, false)
                sync.atomic_store(&engineState.switchingBackend, false)
                resource_end_switch(&engineState.switchingBackend_gate)
            }
        }
        return
    }

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


render_state_begin :: proc (engineState: ^EngineState) {

    if sync.atomic_load(&engineState.switchingBackend) {

        if sync.atomic_load(&engineState.destroyed_all_render_resources) {
            sync.mutex_lock(&engineState.someRenderMutex)
            defer sync.mutex_unlock(&engineState.someRenderMutex)
            
            if sync.atomic_load(&engineState.destroyed_all_render_resources) {
                resource_wait(&engineState.switchingBackend_gate)

                destroy_internal_asset_graphics_resources(engineState)
                graphics.destroy_mesh(&engineState.render_state.graphicsState, &engineState.render_state.mesh_rect)
                graphics.destroy_mesh(&engineState.render_state.graphicsState, &engineState.render_state.mesh_cube)

                graphics.destroy_all_resources(&engineState.render_state.graphicsState)

                if engineState.render_state.graphicsState.renderBackend == .OPENGL {
                    glfw.MakeContextCurrent(nil)
                }

                sync.atomic_store(&engineState.destroyed_all_render_resources, false)
                sync.atomic_store(&engineState.destroyed_all_input_resources, true)
            }
        }
        
        return
    }

    
    acquired := resource_enter(&engineState.switchingBackend_gate)
    if !acquired {
        return
    }
    defer resource_leave(&engineState.switchingBackend_gate)


    if sync.atomic_load(&engineState.render_state.window) == nil {
        return
    }

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
            if engineState.render_state.graphicsState.renderBackend == .OPENGL {
                set_opengl_globals()
            }
            sync.atomic_store(&engineState.reset_opengl_globals, false)
        }
        sync.mutex_unlock(&engineState.someRenderMutex)
    }
     if sync.atomic_load(&engineState.reset_vulkan_globals) {
        sync.mutex_lock(&engineState.someRenderMutex)
        if sync.atomic_load(&engineState.reset_vulkan_globals) {
            if engineState.render_state.graphicsState.renderBackend == .VULKAN {
                graphics.set_vulkan_globals(&engineState.render_state.graphicsState.vulkanBackend)
            }
            sync.atomic_store(&engineState.reset_vulkan_globals, false)
        }
        sync.mutex_unlock(&engineState.someRenderMutex)
    }
}

render_state :: proc (state: ^EngineState) {
    render := &state.render_state

    acquired := resource_enter(&state.switchingBackend_gate)
    if !acquired {
        return
    }
    defer resource_leave(&state.switchingBackend_gate)

    
    if sync.atomic_load(&render.window) == nil {
        return
    }

    if glfw.WindowShouldClose(render.window) {
        fmt.println("closing window")
        state.running = false
        return
    }

    
    update_camera(render)
    update_projection(render)

    // clearColor: vec4 = { 0.5,0.5,0.5,1.0 }
    clearColor: vec4 = { 0.2,0.5,0.9,1.0 }
    // clearColor: vec4 = { 0.0,0.0,0.0,1.0 }
    // clearColor: vec4 = { 1.0,1.0,1.0,1.0 }

    switch render.graphicsState.renderBackend {
        case .OPENGL:
            gl.ClipControl(gl.UPPER_LEFT, gl.ZERO_TO_ONE)
            gl.Enable(gl.FRAMEBUFFER_SRGB) // This makes clear color more consistent with vulkan's.
            gl.Viewport(0, 0, render.width, render.height)
            gl.ClearColor(clearColor.r, clearColor.g, clearColor.b, clearColor.a)
            gl.Clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT)

            // cull face
            // depth alpha
            gl.Disable(gl.CULL_FACE)
            gl.Disable(gl.DEPTH_TEST)

            // diff := cast(f32)(time.time_to_unix_nano(time.now()) - time.time_to_unix_nano(state.startTime)) / 1.0e9
            // render_rect(state, cast(f32)render.width/2 - 25 + math.cos(2*diff) * cast(f32)(render.width/2-50), cast(f32)render.height/2 - 25 + math.sin(2*diff) * cast(f32)(render.height/2-50), 50, 50, {1, 0.2, 0.2, 1})
            // render_rect(state, 900 + diff * 20, 1000, 500, 500, {1, 0.2, 0.2, 1})
            // render_rect(state, 400 + diff * 20, 300, 500, 500, {1, 0.2, 0.2, 1})
            // color: vec4 = {1, 1, 1, 1}
            // color: vec4 = {1, 0.2, 0.2, 1}
            // color: vec4 = {1, 0.0, 0.0, 1}
            // render_rect(state, 50, 0, 100, 100, color)

            // render_model(state, render.block_model, vec3{ 0, 0, -3 }, vec3{1,1,1})
            // render_model(state, render.char_asset.model, vec3{ 0, -1, -1 }, vec3{1,1,1})

            gl.Enable(gl.CULL_FACE)
            gl.Enable(gl.DEPTH_TEST)
            gl.FrontFace(gl.CW)

            // render entities
            
            for i in 0..<get_entity_count(state) {
                entity := get_entity_by_index(state, i)

                if entity.hidden || entity.killed || entity.asset == nil {
                    continue
                }

                render_model(state, entity.asset.model, entity.pos, entity.scale)
            }


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

            glfw.SwapBuffers(render.window)
        
        case .VULKAN:
            res: vk.Result
            backend := &render.graphicsState.vulkanBackend

            vk.WaitForFences(backend.device, 1, &backend.fence_inFlight[backend.currentFrame], true, max(u64))

            imageIndex: u32
            res = vk.AcquireNextImageKHR(backend.device, backend.swapchain, max(u64), backend.sem_imageAvailable[backend.currentFrame], 0, &imageIndex)
            if res == .ERROR_OUT_OF_DATE_KHR {
                // fmt.println("Resized1")
                graphics.recreate_swapchain(backend)
                break
            } else if (res != .SUCCESS && res != .SUBOPTIMAL_KHR) {
                graphics.check_error(res, "failed acquire next image")
            }
            vk.ResetFences(backend.device, 1, &backend.fence_inFlight[backend.currentFrame])


            if render.ui_shader.shader != nil && render.object_shader.shader != nil && render.object_wireframe_shader.shader != nil {
                shader_ui := &render.ui_shader.shader.internal.(graphics.vulkan_Shader)
                shader_obj := &render.object_shader.shader.internal.(graphics.vulkan_Shader)
                shader_wireframe := &render.object_wireframe_shader.shader.internal.(graphics.vulkan_Shader)

                if !backend.made_cmd_buffers {
                    backend.made_cmd_buffers = true

                    graphics.create_command_buffers(backend)
                
                    graphics.create_render_pass(backend, &backend.default_renderPass)

                    graphics.create_pipeline(backend, &backend.default_renderPass, shader_ui.vert_shader, shader_ui.frag_shader, &render.mesh_rect.vertexLayout, size_of(graphics.Rect_Push_Constants), &backend.pipeline_rect)

                    attributes: []graphics.VertexAttribute = {
                        { 0, .FLOAT32_3 },
                        { 1, .FLOAT32_3 },
                        { 2, .FLOAT32_2 },
                    }
                    vertexLayout: graphics.VertexLayout
                    graphics.make_vertex_layout(&state.render_state.graphicsState, attributes, &vertexLayout)

                    graphics.create_pipeline(backend, &backend.default_renderPass, shader_obj.vert_shader, shader_obj.frag_shader, &vertexLayout, size_of(graphics.Object_Push_Constants), &backend.pipeline_object, depthStencil = true)
                    
                    attributes_wire: []graphics.VertexAttribute = {
                        { 0, .FLOAT32_3 },
                    }
                    vertexLayout_wire: graphics.VertexLayout
                    graphics.make_vertex_layout(&state.render_state.graphicsState, attributes_wire, &vertexLayout_wire)

                    graphics.create_pipeline(backend, &backend.default_renderPass, shader_wireframe.vert_shader, shader_wireframe.frag_shader, &vertexLayout_wire, size_of(graphics.Wireframe_Push_Constants), &backend.pipeline_wireframe, depthStencil = true, wireframe = true)
                }
                
                vk.ResetCommandBuffer(backend.commandBuffers[backend.currentFrame], {})

                
                graphics.vulkan_begin_cmd_buffer(backend, backend.commandBuffers[backend.currentFrame])
                
                graphics.vulkan_begin_render_pass(backend, backend.commandBuffers[backend.currentFrame], &backend.default_renderPass, imageIndex, clearColor)
                
                graphics.vulkan_begin_pipeline(backend, backend.commandBuffers[backend.currentFrame], &backend.pipeline_object)

                    // asset := find_asset_by_name(&state.storage, "cube")
                    // if asset.model != nil {
                    //     render_model(state, asset.model, { 0, 0, 0}, {1,1,1})
                    // }

                    for i in 0..<get_entity_count(state) {
                        entity := get_entity_by_index(state, i)

                        if entity.hidden || entity.killed || entity.asset == nil {
                            continue
                        }

                        render_model(state, entity.asset.model, entity.pos, entity.scale)
                    }
                    
                    for i in 0..<len(render.world_pass.drawOperations) {
                        op := &render.world_pass.drawOperations[i]
                        if op.type == .WIREFRAME {
                            // render_wireframe(state, op.pos, op.scale, op.color.xyz)
                        } else if op.type == .OBJECT {
                            render_model(state, op.asset.model, op.pos, op.scale)
                        }
                    }


                graphics.vulkan_end_pipeline(backend, backend.commandBuffers[backend.currentFrame])
                
                graphics.vulkan_begin_pipeline(backend, backend.commandBuffers[backend.currentFrame], &backend.pipeline_wireframe)

                    for i in 0..<len(render.world_pass.drawOperations) {
                        op := &render.world_pass.drawOperations[i]
                        if op.type == .WIREFRAME {
                            render_wireframe(state, op.pos, op.scale, op.color.xyz)
                        } else if op.type == .OBJECT {
                            // render_model(state, op.asset.model, op.pos, op.scale)
                        }
                    }

                graphics.vulkan_end_pipeline(backend, backend.commandBuffers[backend.currentFrame])

                graphics.vulkan_begin_pipeline(backend, backend.commandBuffers[backend.currentFrame], &backend.pipeline_rect)
                    
                    // color: vec4 = {1, 0.2, 0.2, 1}
                    color: vec4 = {1.0, 0.0, 0.0, 1.0}
                    // render_rect(state, 50, 0, 100, 100, color)

                    // push: graphics.Rect_Push_Constants = {
                    //     color  = {color.r, color.g, color.b, color.a},
                    //     window = {cast(f32)render.width, cast(f32)render.height},
                    //     pos    = {50, 0},
                    //     size   = {100, 100},
                    // }
                    // graphics.vulkan_draw_mesh(backend, backend.commandBuffers[backend.currentFrame], &render.mesh_rect, &backend.pipeline_rect, slice.bytes_from_ptr(&push, size_of(push)))

                    
                    for i in 0..<len(render.ui_pass.drawOperations) {
                        op := &render.ui_pass.drawOperations[i]
                        if op.type == .RECTANGLE {
                            push: graphics.Rect_Push_Constants = {
                                color  = {op.color.r, op.color.g, op.color.b, 1.0},
                                window = {cast(f32)render.width, cast(f32)render.height},
                                pos    = {op.x, op.y},
                                size   = {op.w, op.h},
                            }
                            graphics.vulkan_draw_mesh(backend, backend.commandBuffers[backend.currentFrame], &render.mesh_rect, &backend.pipeline_rect, slice.bytes_from_ptr(&push, size_of(push)))
                        }
                    }


                graphics.vulkan_end_pipeline(backend, backend.commandBuffers[backend.currentFrame])

                graphics.vulkan_end_render_pass(backend, backend.commandBuffers[backend.currentFrame])

                graphics.vulkan_end_cmd_buffer(backend, backend.commandBuffers[backend.currentFrame])
                

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
            } else {
                // Submit nothing
                waitStages: [1]vk.PipelineStageFlags = { { .COLOR_ATTACHMENT_OUTPUT } }
                submitInfo: vk.SubmitInfo = {
                    sType = .SUBMIT_INFO,
                    waitSemaphoreCount = 1,
                    pWaitSemaphores = &backend.sem_imageAvailable[backend.currentFrame],
                    pWaitDstStageMask = &waitStages[0],
                    commandBufferCount = 0,
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
                // fmt.println("Resized")
                backend.frame_resized = false
                graphics.recreate_swapchain(backend)
            } else if (res != .SUCCESS && res != .SUBOPTIMAL_KHR) {
                graphics.check_error(res, "failed acquire next image")
            }
            
            backend.currentFrame = (backend.currentFrame + 1) % graphics.MAX_FRAMES_IN_FLIGHT

    }

    clear(&render.world_pass.drawOperations)
    clear(&render.ui_pass.drawOperations)
}



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

    switch state.render_state.graphicsState.renderBackend {
        case .OPENGL:

            shader := &render.object_shader.shader.internal.(graphics.opengl_Shader)

            // @NOCHECKIN Fix
            gl.UseProgram(shader.program)

            transform := glsl.mat4Translate(pos) * glsl.mat4Scale(scale)

            gl.UniformMatrix4fv(shader.uniforms["CONST.uTransform"].location, 1, false, transmute([^]f32) &transform)
            gl.UniformMatrix4fv(shader.uniforms["CONST.uProjection"].location, 1, false,  transmute([^]f32) &render.projection)
            // gl.Uniform3f(render.object_shader.shader.uniforms["uCameraPos"].location,
                // render.camera_position.x, render.camera_position.y, render.camera_position.z)


            for i in 0..<len(model.meshes) {
                mesh := &model.meshes[i]
                
                // if mesh.material.useTexture {
                //     texture := &mesh.material.base_texture.internal.(graphics.opengl_Texture)

                //     gl.ActiveTexture(gl.TEXTURE0)
                //     gl.BindTexture(gl.TEXTURE_2D, texture.id)

                //     gl.Uniform1i(shader.uniforms["CONST.use_diffuseMap"].location, 1)
                //     gl.Uniform1i(shader.uniforms["diffuse_map"].location, 0)
                // } else {
                // gl.Uniform1i(shader.uniforms["CONST.use_diffuseMap"].location, 0)
                gl.Uniform3f(shader.uniforms["CONST.diffuse_color"].location,
                    mesh.material.diffuse.x, mesh.material.diffuse.y, mesh.material.diffuse.z)
                // }
                gl.BindVertexArray(mesh.vertexLayout.internal.(graphics.opengl_VertexArrayObject).vao)
                gl.DrawElements(gl.TRIANGLES, cast(i32)mesh.indexBuffer.index_count, gl.UNSIGNED_INT, nil)
            }

        case .VULKAN:

            backend := &state.render_state.graphicsState.vulkanBackend
        
            transform := glsl.mat4Translate(pos) * glsl.mat4Scale(scale)
    
            for i in 0..<len(model.meshes) {
                mesh := &model.meshes[i]

                push: graphics.Object_Push_Constants = {
                    uTransform  = transform,
                    uProjection = render.projection,
                    diffuse_color = mesh.material.diffuse,
                    use_diffuseMap = 1,
                }
                graphics.vulkan_draw_mesh(backend, backend.commandBuffers[backend.currentFrame], mesh, &backend.pipeline_object, slice.bytes_from_ptr(&push, size_of(push)))
            }
    }
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

            gl.Uniform2f(shader.uniforms["CONST.window"].location, cast(f32)render.width, cast(f32)render.height)
            gl.Uniform2f(shader.uniforms["CONST.pos"].location, x, y)
            gl.Uniform2f(shader.uniforms["CONST.size"].location, w, h)
            gl.Uniform4f(shader.uniforms["CONST.color"].location, color.r, color.g, color.b, color.a)
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

    switch state.render_state.graphicsState.renderBackend {
        case .OPENGL:

            shader := &render.object_wireframe_shader.shader.internal.(graphics.opengl_Shader)

            gl.UseProgram(shader.program)

            transform := glsl.mat4Translate(pos) * glsl.mat4Scale(scale)
            
            mesh := &render.mesh_cube

            gl.UniformMatrix4fv(shader.uniforms["CONST.uTransform"].location, 1, false, transmute([^]f32) &transform)
            gl.UniformMatrix4fv(shader.uniforms["CONST.uProjection"].location, 1, false,  transmute([^]f32) &render.projection)
            gl.Uniform3f(shader.uniforms["CONST.wireframe_color"].location, color.x, color.y, color.z)

            gl.BindVertexArray(mesh.vertexLayout.internal.(graphics.opengl_VertexArrayObject).vao)
            gl.DrawElements(gl.LINES, cast(i32)mesh.indexBuffer.index_count, gl.UNSIGNED_INT, nil)

        case .VULKAN:

            backend := &state.render_state.graphicsState.vulkanBackend
        
            transform := glsl.mat4Translate(pos) * glsl.mat4Scale(scale)
    
            mesh := &render.mesh_cube

            push: graphics.Wireframe_Push_Constants = {
                uTransform  = transform,
                uProjection = render.projection,
                wireframe_color = color,
            }
            graphics.vulkan_draw_mesh(backend, backend.commandBuffers[backend.currentFrame], mesh, &backend.pipeline_wireframe, slice.bytes_from_ptr(&push, size_of(push)))

    }
}


create_rect :: proc (state: ^EngineState) -> (mesh: graphics.Mesh) {
    vertex_data: []f32 = {
        // clockwise?
        //   pos
        0.0, 0.0,
        0.0, 1.0,
        1.0, 0.0,
        1.0, 0.0,
        0.0, 1.0,
        1.0, 1.0,
        
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

    return
}




update_projection :: proc (render : ^RenderState) {
    projection := glsl.mat4Perspective( 90.0/(180/math.PI), cast(f32)render.width/cast(f32)render.height, 0.02, 400)

    projection[1][1] *= -1

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
    glfw.SetErrorCallback(ErrorProc)
}

set_opengl_globals :: proc () {
    gl.load_up_to(4, 5, glfw.gl_set_proc_address);
}






//#################################
//        WINDOW EVENTS
//##################################


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
    // fmt.println("Frame buffer resize: ", width, " ", height);
    // @TODO Set  
    render_state.graphicsState.vulkanBackend.frame_resized = true
}



ErrorProc :: proc "c" (a0: c.int, a1: cstring) {
    context = runtime.default_context()

    fmt.println("GLFW ERROR ", a0, a1)
}