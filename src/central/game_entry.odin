package central

import "core:fmt"
import "core:time"
import "core:sync"
import "core:strings"
import "core:strconv"
import "core:thread"
import "core:os"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "../engine/driver"
import "../engine/util"
import "../engine/graphics"
import "../engine"

@(export)
driver_event :: proc (event: driver.EventKind, event_data: ^driver.EventData, data: ^driver.DriverData) {
    if event != driver.EventKind.EVENT_TICK {
        fmt.println("EVENT ", event)
    }

    switch event {
        case .EVENT_START:
            event_data.user_data = new(GameState)
            event_data.user_index = cast(int)driver.ThreadType.UPDATE
            data.user_data = event_data.user_data
            game_state := cast(^GameState)event_data.user_data
            game_state.engineState.running = true
            
            handle_arguments(game_state, data.args)
            
            game_state.engineState.game_directory = data.game_directory
            game_state.engineState.storage.game_directory = data.game_directory

            game_state.engineState.startTime = time.now()
            game_init(game_state)
            
            if !game_state.engineState.server_mode {
                {
                    thr := thread.create(data.thread_main)
                    thr.data = data
                    thr.user_index = cast(int)driver.ThreadType.INPUT
                    append(&data.threads, thr)
                    thread.start(thr)
                }
                {
                    thr := thread.create(data.thread_main)
                    thr.data = data
                    thr.user_index = cast(int)driver.ThreadType.RENDER_0
                    append(&data.threads, thr)
                    thread.start(thr)
                }
            }
            {
                thr := thread.create(data.thread_main)
                thr.data = data
                thr.user_index = cast(int)driver.ThreadType.WORKER_0
                append(&data.threads, thr)
                thread.start(thr)
            }

        case .EVENT_STOP:
            // TODO: cleanup
        case .EVENT_LOAD:
            if event_data.user_data != nil {
                game_state := cast(^GameState)event_data.user_data
                engine.hotreload(&game_state.engineState)
            }
        case .EVENT_UNLOAD:

        case .EVENT_TICK:
            game_state := cast(^GameState)event_data.user_data
            thread_type := cast(driver.ThreadType)event_data.user_index

            #partial switch thread_type {
                case .UPDATE:
                    tick(game_state)
                    data.running = game_state.engineState.running
                case .INPUT:
                    engine.tick_input(&game_state.engineState)
                case .RENDER_0..<.RENDER_MAX:
                    tick_render(game_state, thread_type)
                case .WORKER_0..<.WORKER_MAX:
                    tick_worker(game_state, thread_type)
            }

    }
}


handle_arguments :: proc (state: ^GameState, args: []string) {

    server_mode := false
    port        := 8789
    world_path: string

    test_mode   := false
    test_path: string 

    // renderBackend: graphics.RenderBackend = .VULKAN
    renderBackend: graphics.RenderBackend = .OPENGL

    argi := 1
    for argi < len(args) {
        arg := args[argi]
        argi += 1

        if arg == "--server" {
            server_mode = true
        } else if arg == "--port" {
            if argi >= len(args) {
                fmt.println("\033[31mERROR:\033[0m Missing port after ", arg)
                os.exit(1)
            }
            err: bool
            port, err = strconv.parse_int(args[argi])
            if !err {
                fmt.println("\033[31mERROR:\033[0m Not a valid port number ", args[argi])
                os.exit(1)
            }
            argi += 1
        } else if arg == "--world" {
            if argi >= len(args) {
                fmt.println("\033[31mERROR:\033[0m Missing path after ", arg)
                os.exit(1)
            }
            world_path = args[argi]
            argi += 1
        } else if arg == "--test" {
            if argi >= len(args) {
                fmt.println("\033[31mERROR:\033[0m Missing path after ", arg)
                os.exit(1)    
            }
            test_mode = true
            test_path = args[argi]
            argi += 1
        } else if arg == "--opengl" {
            renderBackend = .OPENGL
        } else if arg == "--vulkan" {
            renderBackend = .VULKAN
        } else if arg[0] == '-' {
            fmt.println("\033[31mERROR:\033[0m Unknown argument ", arg)
            os.exit(1)
        }
    }
    if server_mode && test_mode {
        fmt.println("You cannot specify --server and --test")
    }
    if server_mode {
        fmt.println("Server-mode at port ", port)
        // @TODO Check if world was specified
    }
    if test_mode {
        fmt.println("Test-mode from ", test_path)
    }

    state.engineState.server_mode = server_mode
    state.engineState.render_state.graphicsState.renderBackend = renderBackend
}

tick_render :: proc (state: ^GameState, thread_type: driver.ThreadType) {
    engine_state := &state.engineState
    storage := &state.engineState.storage
    
    // @TODO Remove or change, game does very little so we don't want to hammer the CPU
    defer  time.sleep(1 * time.Millisecond)

    engine.render_state_begin(engine_state)

    engine.process_assets(&state.engineState, thread_type)

    player := engine.get_entity(engine_state, state.player_id)
    if !state.editor.editorEnabled {
        engine_state.render_state.camera_position = player.pos + player.vel * engine_state.accDeltaTime
    } else {
        engine_state.render_state.camera_position = state.editor.editorCamera_pos + state.editor.editorCamera_vel * engine_state.accDeltaTime
    }
    
    render_editor(state)

    engine.render_state(engine_state)

}

tick_worker :: proc (state: ^GameState, thread_type: driver.ThreadType) {
    engine_state := &state.engineState
    storage := &state.engineState.storage

    if thread_type == .WORKER_0 {
        // Only one worker can poll events (because watcher has two event lists it switches between, one for user to read, one for watcher thread to write)
        events := util.watcher_poll(&storage.art_watcher)
        for e in events {
            fmt.printfln("%v", e)
            // @TODO Wait with reloading, blender modifies the file multiple times when exporting.
            rel_path := strings.concatenate({storage.art_watcher.root, "/", e.path}, context.temp_allocator)

            asset := engine.find_asset_by_src(storage, rel_path)
            // fmt.printfln("Hello %v %v", rel_path, asset)
            if asset != nil && engine.can_be_reloaded(asset) {
                engine.reload_asset(engine_state, asset, time.now())
            }
        }
    }

    engine.process_assets(&state.engineState, thread_type)

    time.sleep(1 * time.Millisecond)
}

tick :: proc (state: ^GameState) {
    engine_state := &state.engineState
    if time.time_to_unix_nano(engine_state.lastTime) == 0 {
        // last_time is zero first tick
        engine_state.lastTime = time.now()
    }
    // fmt.println("sdad?")

    now := time.now()
    engine_state.delta = cast(f32)(time.time_to_unix_nano(now) - time.time_to_unix_nano(engine_state.lastTime)) / 1.0e9
    engine_state.lastTime = now
    engine_state.accDeltaTime += cast(f32)engine_state.delta


    engine_state.fixedDelta = engine.FIXED_UPDATE_DELTA
    for engine_state.accDeltaTime > engine.FIXED_UPDATE_DELTA {
        engine_state.accDeltaTime -= engine.FIXED_UPDATE_DELTA
        // state.fixedDelta = state.delta
        for i in 0..<len(engine_state.inputState.actors) {
            actor := &engine_state.inputState.actors[i]
            
            for j in 0..<len(actor.actions) {
                actor.actions[j] = actor.temp_actions[j]
                actor.temp_actions[j].pressed = 0
            }
        }
        update_state(state)
        engine_state.current_tick += 1
    }
    // state.render_state.camera_position += {5 * state.delta,0, 5 * state.delta}

    
    

    // if state.current_tick % 60 == 0 {
    //     fmt.printfln("fps %v", 1/state.delta)
    // }

    // time.sleep(14 * 1000000)
}
