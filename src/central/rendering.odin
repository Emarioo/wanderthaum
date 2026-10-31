package central

import "core:fmt"
import "core:strings"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:math/linalg/glsl"
import "core:math"
import "core:c"
import "base:runtime"
import "core:time"

import "vendor:glfw"
import stb_image "vendor:stb/image"
import gl "vendor:OpenGL"


RenderState :: struct {
    window: glfw.WindowHandle,
    width, height: i32,

    ui_shader : ^Asset,
    object_shader : ^Asset,
    mesh_rect: Mesh,
    // mesh_: Mesh

    camera_position : vec3,
    camera_rotation : vec3,

    projection : mat4,

    char_asset : ^Asset,
    wierdBlock_asset : ^Asset,
    texture: Texture,

    cube_asset : ^Asset,

    first_mx : bool,
    mx, my : i32,
    last_mx, last_my : i32,

    cursor_locked : bool,

    cameraSensitivity : f32,
}

render_init_window :: proc (state: ^EngineState) {
    render := &state.render_state
    
    glfw.Init()
    
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 3);
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 3);
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE);
    
    render.cameraSensitivity = 0.16
    
    render.width = 800
    render.height = 600
    window := glfw.CreateWindow(render.width, render.height, cstring("Wanderthaum: The Living World"), nil, nil)
    glfw.SetWindowUserPointer(window, state)


    // hyprland may change the window size even if
    // we specify 800x600 when creating window.
    // We make sure to get the real size here.
    render.width, render.height = glfw.GetWindowSize(window)

    set_glfw_globals(render, window)

    glfw.SwapInterval(0)

    render.ui_shader        = register_asset_from_store(state, "ui_shader",     "shaders/ui.glsl")
    render.object_shader    = register_asset_from_store(state, "object_shader", "shaders/object.glsl")
    render.wierdBlock_asset = register_asset_from_store(state, "block",         "models/block.glb")
    render.char_asset       = register_asset_from_store(state, "iuno",          "models/character_trim.glb")
    render.cube_asset       = register_asset_from_store(state, "cube",          "models/cube.glb")
    // render.cube_asset       = register_asset_empty(     state, "cube")

    // @IMPORTANT Set this last, this indicates to render thread that we can now MakeContextCurrent and do gl calls
    render.window = window
}


init_render_state :: proc (state: ^EngineState) {
    render := &state.render_state

    glfw.MakeContextCurrent(render.window)
    set_opengl_globals()

    // render.ui_shader = load_shader(ui_path)
    // render.object_shader = load_shader(object_path)

    render.mesh_rect = create_rect()

    // cubeModel := create_cube_model()
    // update_empty_asset(state, render.cube_asset, cubeModel)

    // block_path := "assets/models/block.glb"
    // block_path := "assets/models/cube.glb"
    // render.block_model = load_model(block_path)

    
    
    // render.texture = load_texture("C:/Users/emarioo/Downloads/尤诺/textures/Face_D.png")
    // render.texture = render.char_model.meshes[0].material.base_texture
}

Shader :: struct {
    program: u32,
    uniforms: gl.Uniforms,
}

Texture :: struct {
    id: u32,
    width: u32,
    height: u32,
    raw_data: [^]u8,
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

    NO_ACTION := cast(Input_Action)-1
    inputAction: Input_Action = NO_ACTION

    if key == glfw.KEY_W {
        inputAction = Input_Action.MOVE_FORWARD
    }
    if key == glfw.KEY_A {
        inputAction = Input_Action.MOVE_LEFT
    }
    if key == glfw.KEY_S {
        inputAction = Input_Action.MOVE_BACKWARD
    }
    if key == glfw.KEY_D {
        inputAction = Input_Action.MOVE_RIGHT
    }
    if key == glfw.KEY_SPACE {
        inputAction = Input_Action.MOVE_UP
    }
    if key == glfw.KEY_C {
        inputAction = Input_Action.MOVE_DOWN
    }
    if key == glfw.KEY_LEFT_SHIFT {
        inputAction = Input_Action.MOVE_SPRINT
    }
    // if key == glfw.KEY_R && (mods & glfw.MOD_CONTROL) != 0 {
    if key == KEY_F1 {
        inputAction = Input_Action.RELOAD_ASSETS
    }
    
    if key == glfw.KEY_F2 {
        inputAction = Input_Action.EDITOR_TOGGLE
    }
    if key == glfw.KEY_1 {
        inputAction = Input_Action.EDITOR_TOOL0
    }
    if key == glfw.KEY_2 {
        inputAction = Input_Action.EDITOR_TOOL1
    }
    if key == glfw.KEY_3 {
        inputAction = Input_Action.EDITOR_TOOL2
    }
    if key == glfw.KEY_4 {
        inputAction = Input_Action.EDITOR_TOOL3
    }
    if key == glfw.KEY_K {
        inputAction = Input_Action.EDITOR_SPAWN_CUBE
    }

    if inputAction != NO_ACTION {
        actor.temp_actions[inputAction].value = cast(i32)(action != glfw.RELEASE)
        if action == glfw.PRESS {
            actor.temp_actions[inputAction].pressed += 1
        }
    }


    // fmt.printfln("move %v",global_render_state.move)

    // fmt.println("key",key,scancode,action,mods)
}
MouseButtonProc  :: proc "c" (window: glfw.WindowHandle, button, action, mods: c.int) {
    context = runtime.default_context()
    
    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state
    
    // fmt.println("mbutton", button, action, mods)
    
    actor := &engine.inputState.actors[0]

    inputAction: Input_Action
    if button == 0 {
        inputAction = Input_Action.PRIMARY_ACTION
    } else if button == 1 {
        inputAction = Input_Action.SECONDARY_ACTION
    } else if button == 2 {
        inputAction = Input_Action.THIRD_ACTION
    }

    actor.actions[inputAction].value   = cast(i32)(action != glfw.RELEASE)
    if action == glfw.PRESS {
        actor.actions[inputAction].pressed += 1
    }
}
CursorPosProc    :: proc "c" (window: glfw.WindowHandle, xpos,  ypos: f64) {
    context = runtime.default_context()
    
    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    render_state.mx = cast(i32)xpos
    render_state.my = cast(i32)ypos

    actor := &engine.inputState.actors[0]
    actor.actions[Input_Action.POINTER_X].value = cast(i32)xpos
    actor.actions[Input_Action.POINTER_Y].value = cast(i32)xpos
    // fmt.println(xpos, ypos)
    // fmt.println("diff",global_render_state.mx-global_render_state.last_mx, global_render_state.my-global_render_state.last_my)
}
ScrollProc       :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
    context = runtime.default_context()

    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    actor := &engine.inputState.actors[0]
    actor.actions[Input_Action.SCROLL_X].value = cast(i32)xoffset
    actor.actions[Input_Action.SCROLL_Y].value = cast(i32)yoffset
}
WindowSizeProc   :: proc "c" (window: glfw.WindowHandle, width, height: c.int) {
    context = runtime.default_context()

    engine := cast(^EngineState)glfw.GetWindowUserPointer(window)
    render_state := &engine.render_state

    render_state.width = cast(i32)width
    render_state.height = cast(i32)height
    // fmt.println("Windows size: ", width, " ", height);
}

load_shader :: proc (path : string, shader: ^Shader) {
    bytes: []byte
    ok: bool
    err: os.Error
    bytes, err = os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("Could not open",path)
        os.exit(1)
    }

    text := string(bytes)
    vertex_index   := strings.index(text, "#vertex") // don't pattern match \n, on Windows we have \r\n while on linux just \n
    fragment_index := strings.index(text, "#fragment")

    vertex_text := text[vertex_index+8:fragment_index]
    fragment_text := text[fragment_index+10:]

    shader.program, ok = gl.load_shaders_source(vertex_text, fragment_text)
    if !ok {
        fmt.eprintln("Failed loading shaders from", path)
        return
        // os.exit(1)
    }
    shader.uniforms = gl.get_uniforms_from_program(shader.program)

    // fmt.printf("Loaded shader '%s'\n", path)
}

load_texture :: proc {
    load_texture_from_file,
    load_texture_from_buffer,
}

load_texture_from_file :: proc (path: string, texture: ^Texture) {
    bytes, err := os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("Could not open",path)
        os.exit(1)
    }

    load_texture_from_buffer(bytes, texture)

    fmt.printf("Loaded texture '%s'\n", path)
}
load_texture_from_buffer :: proc (data: []u8, texture: ^Texture) {
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

init_texture_render :: proc (texture: ^Texture) {
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


render_state :: proc (state: ^EngineState) {
    render := &state.render_state

    if glfw.WindowShouldClose(render.window) {
        fmt.println("closing window")
        state.running = false
        return
    }

    // glfw.PollEvents()
    // glfw.WaitEventsTimeout(1/144.0)
    
    update_camera(render)
    update_projection(render)

    gl.Viewport(0, 0, render.width, render.height)
    gl.ClearColor(0.3,0.5,0.6,1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT)


    

    // cull face
    // depth alpha
    gl.Disable(gl.CULL_FACE)
    // gl.Enable(gl.CULL_FACE)
    gl.Enable(gl.DEPTH_TEST)

    // diff := cast(f32)(time.time_to_unix_nano(time.now()) - time.time_to_unix_nano(state.startTime)) / 1.0e9
    // render_rect(state, cast(f32)render.width/2 - 25 + math.cos(2*diff) * cast(f32)(render.width/2-50), cast(f32)render.height/2 - 25 + math.sin(2*diff) * cast(f32)(render.height/2-50), 50, 50, {1, 0.2, 0.2, 1})
    // render_rect(state, 900 + diff * 20, 1000, 500, 500, {1, 0.2, 0.2, 1})
    // render_rect(state, 400 + diff * 20, 300, 500, 500, {1, 0.2, 0.2, 1})
    color: vec4 = {1, 1, 1, 1}
    // color: vec4 = {1, 0.2, 0.2, 1}
    // render_rect(state, 50, 0, 100, 100, color)

    // render_model(state, render.block_model, Vector3f32{ 3, 0, 0 })
    // render_model(state, render.block_model, Vector3f32{ -3, 0, 0 })
    // render_model(state, render.block_model, Vector3f32{ 0, 0, 3 })
    // render_model(state, render.block_model, vec3{ 0, 0, -3 })
    render_model(state, render.char_asset.model, vec3{ 0, -1, -1 })
    // render_model(state, render.block_model, Vector3f32{ 0, 3, 0 })
    // render_model(state, render.block_model, Vector3f32{ 0, -3, 0 })

    // render entities
    for i in 0..<state.entities_count {
        entity := &state.entities[i]

        if entity.hidden || entity.asset == nil {
            continue
        }

        render_model(state, entity.asset.model, entity.pos)
    }
}


render_state_end :: proc (state: ^EngineState) {
    render := &state.render_state
    
    glfw.SwapBuffers(render.window)
}

render_model :: proc (state: ^EngineState, model: ^Model, pos: vec3) {
    render := &state.render_state

    if model == nil {
        return
    }

    if render.object_shader.shader == nil {
        return
    }

    gl.UseProgram(render.object_shader.shader.program)

    transform := glsl.mat4Translate(pos)

    gl.UniformMatrix4fv(render.object_shader.shader.uniforms["uTransform"].location, 1, false, transmute([^]f32) &transform)
    gl.UniformMatrix4fv(render.object_shader.shader.uniforms["uProjection"].location, 1, false,  transmute([^]f32) &render.projection)
    // gl.Uniform3f(render.object_shader.shader.uniforms["uCameraPos"].location,
        // render.camera_position.x, render.camera_position.y, render.camera_position.z)


    for i in 0..<len(model.meshes) {
        mesh := &model.meshes[i]
        
        if mesh.material.useTexture {
            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, mesh.material.base_texture.id)

            gl.Uniform1i(render.object_shader.shader.uniforms["use_diffuseMap"].location, 1)
            gl.Uniform1i(render.object_shader.shader.uniforms["diffuse_map"].location, 0)
        } else {
            gl.Uniform1i(render.object_shader.shader.uniforms["use_diffuseMap"].location, 0)
            gl.Uniform3f(render.object_shader.shader.uniforms["diffuse_color"].location,
                mesh.material.diffuse.x, mesh.material.diffuse.y, mesh.material.diffuse.z)
        }
        gl.BindVertexArray(mesh.vao)
        gl.DrawElements(gl.TRIANGLES, mesh.index_count, gl.UNSIGNED_INT, nil)
    }
}


render_rect :: proc (state: ^EngineState, x,y,w,h: f32, color: [4]f32) {
    render := &state.render_state

    if render.ui_shader.shader == nil {
        return
    }

    gl.UseProgram(render.ui_shader.shader.program)

    gl.Uniform2f(render.ui_shader.shader.uniforms["uWindow"].location, cast(f32)render.width, cast(f32)render.height)
    gl.Uniform2f(render.ui_shader.shader.uniforms["uPos"].location, x, y)
    gl.Uniform2f(render.ui_shader.shader.uniforms["uSize"].location, w, h)
    gl.Uniform4f(render.ui_shader.shader.uniforms["uColor"].location, color.r, color.g, color.b, color.a)
    // gl.Uniform1i(render.ui_shader.uniforms["uSampler"].location, 0)

    // gl.ActiveTexture(gl.TEXTURE0)
    // gl.BindTexture(gl.TEXTURE_2D, render.texture.id)

    gl.BindVertexArray(render.mesh_rect.vao)
    gl.DrawArrays(gl.TRIANGLES, 0, 6)
}


create_rect :: proc () -> (mesh: Mesh) {

    vertex_data: []f32 = {
    //   pos
        0.0, 0.0,
        1.0, 0.0,
        0.0, 1.0,
        1.0, 0.0,
        1.0, 1.0,
        0.0, 1.0,
    }
    // index_data: []u32 = {
    //     1, 3, 2,
    // }

    // for i in 0..<len(vertex_data) {
    //     vertex_data[i]/=2.0
    // }

    gl.GenVertexArrays(1, &mesh.vao)
    gl.GenBuffers     (1, &mesh.vbo)
    // gl.GenBuffers     (1, &mesh.ibo)

    gl.BindVertexArray(mesh.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertex_data) * size_of(f32), raw_data(vertex_data), gl.STATIC_DRAW)

    // gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo)
    // gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(index_data) * size_of(u32), raw_data(index_data), gl.STATIC_DRAW)

    // position attribute
	gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(f32) * 2, cast(uintptr)0)
	gl.EnableVertexAttribArray(0)

    gl.BindVertexArray(0)

    return
}