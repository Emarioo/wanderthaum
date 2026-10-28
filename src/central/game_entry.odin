package central

import "core:fmt"
import "core:time"
import "core:sync"
import "core:strings"
import "core:thread"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "../driver"
import "./util"

@(export)
driver_event :: proc (event: driver.EventKind, event_data: ^driver.EventData, data: ^driver.DriverData) {
    if event != driver.EventKind.EVENT_TICK {
        fmt.println("EVENT ", event)
    }

    switch event {
        case .EVENT_START:
            event_data.user_data = new(GameState)
            event_data.user_index = cast(int)ThreadType.UPDATE
            data.user_data = event_data.user_data
            game_state := cast(^GameState)event_data.user_data
            game_state.engine.running = true
            
            game_state.engine.game_directory = data.game_directory
            game_state.engine.storage.game_directory = data.game_directory

            game_state.engine.startTime = time.now()
            update_init(game_state)
            
            // @TODO Improve thread driver hot reload situation.
            //   We want to support network threads.
            // @TODO I HAVE HARDCODED data.active_thread in driver main.odin. Fix it when adding new threads.
            {
                thr := thread.create(data.thread_main)
                thr.data = data
                thr.user_index = cast(int)ThreadType.INPUT
                append(&data.threads, thr)
                thread.start(thr)
            }
            {
                thr := thread.create(data.thread_main)
                thr.data = data
                thr.user_index = cast(int)ThreadType.RENDER_0
                append(&data.threads, thr)
                thread.start(thr)
            }
            {
                thr := thread.create(data.thread_main)
                thr.data = data
                thr.user_index = cast(int)ThreadType.WORKER_0
                append(&data.threads, thr)
                thread.start(thr)
            }

        case .EVENT_STOP:
            // TODO: cleanup
        case .EVENT_LOAD:
            if event_data.user_data != nil {
                // reload gl global variable procedures, not the first load, need to setup window first
                game_state := cast(^GameState)event_data.user_data
                game_state.engine.reset_opengl_globals = true
                game_state.engine.reset_glfw_globals = true
            }
        case .EVENT_UNLOAD:

        case .EVENT_TICK:
            game_state := cast(^GameState)event_data.user_data
            thread_type := cast(ThreadType)event_data.user_index

            #partial switch thread_type {
                case .UPDATE:
                    tick(game_state)
                    data.running = game_state.engine.running
                case .INPUT:
                    tick_input(game_state)
                case .RENDER_0..<.RENDER_MAX:
                    tick_render(game_state, thread_type)
                case .WORKER_0..<.WORKER_MAX:
                    tick_worker(game_state, thread_type)
            }

    }
}


tick_render :: proc (state: ^GameState, thread_type: ThreadType) {
    engine_state := &state.engine
    storage := &state.engine.storage

    if engine_state.render_state.window == nil {
        // window not initialized by input thread yet
        return
    }

    if !engine_state.has_init_render {
        engine_state.has_init_render = true
        init_render_state(engine_state)
    }
    
    if engine_state.reset_opengl_globals {
        engine_state.reset_opengl_globals = false
        set_opengl_globals()
    }

    process_assets(&state.engine, thread_type)

    player := get_entity(engine_state, state.player_index)
    // state.render_state.camera_position = player.pos
    engine_state.render_state.camera_position = player.pos + player.vel * engine_state.accDeltaTime
    render_state(engine_state)

    render_state_end(engine_state)

    time.sleep(1 * time.Millisecond)
}

tick_input :: proc (state: ^GameState) {
    engine_state := &state.engine
    if engine_state.render_state.window == nil {
        render_init_window(engine_state)
    }

    if engine_state.reset_glfw_globals {
        engine_state.reset_glfw_globals = false
        set_glfw_globals(&engine_state.render_state)
    }

    // fmt.println("spam2")
    glfw.PollEvents()

    time.sleep(5 * time.Millisecond)
}

tick_worker :: proc (state: ^GameState, thread_type: ThreadType) {
    engine_state := &state.engine
    storage := &state.engine.storage

    if thread_type == .WORKER_0 {
        // Only one worker can poll events (because watcher has two event lists it switches between, one for user to read, one for watcher thread to write)
        events := util.watcher_poll(&storage.art_watcher)
        for e in events {
            fmt.printfln("%v", e)
            // @TODO Wait with reloading, blender modifies the file multiple times when exporting.
            rel_path := strings.concatenate({storage.art_watcher.root, "/", e.path}, context.temp_allocator)

            asset := find_asset_by_src(storage, rel_path)
            // fmt.printfln("Hello %v %v", rel_path, asset)
            if asset != nil && can_be_reloaded(asset) {
                reload_asset(engine_state, asset, time.now())
            }
        }
    }

    process_assets(&state.engine, thread_type)

    time.sleep(1 * time.Millisecond)
}

tick :: proc (state: ^GameState) {
    engine_state := &state.engine
    if time.time_to_unix_nano(engine_state.lastTime) == 0 {
        // last_time is zero first tick
        engine_state.lastTime = time.now()
    }
    // fmt.println("sdad?")

    now := time.now()
    engine_state.delta = cast(f32)(time.time_to_unix_nano(now) - time.time_to_unix_nano(engine_state.lastTime)) / 1.0e9
    engine_state.lastTime = now
    engine_state.accDeltaTime += cast(f32)engine_state.delta


    engine_state.fixedDelta = FIXED_UPDATE_DELTA
    for engine_state.accDeltaTime > FIXED_UPDATE_DELTA {
        engine_state.accDeltaTime -= FIXED_UPDATE_DELTA
        // state.fixedDelta = state.delta
        engine_state.render_state.move = engine_state.render_state.temp_move
        update_state(state)
        engine_state.current_tick += 1
        engine_state.render_state.prev_move = engine_state.render_state.move
    }
    // state.render_state.camera_position += {5 * state.delta,0, 5 * state.delta}

    
    

    // if state.current_tick % 60 == 0 {
    //     fmt.printfln("fps %v", 1/state.delta)
    // }

    // time.sleep(14 * 1000000)
}
