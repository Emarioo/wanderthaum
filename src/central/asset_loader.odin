package central

import "core:strings"
import "core:fmt"
import "core:time"
import "core:sync"
import "core:path/filepath"
import "./util"
import "../engine/driver"

AssetStatus :: enum {
    READY,
    FAILED,
    NEEDS_MAIN_PROCESSING,
    NEEDS_RENDER_PROCESSING,
}

AssetType :: enum {
    MODEL,
    SHADER,
}

Asset :: struct {
    name: string,
    path: string,

    type: AssetType,
    status: AssetStatus,
    scheduled_time: time.Time,
    submit_time: time.Time,
    loaded_time: time.Time,
    processing_time: time.Duration,

    model: ^Model,
    wip_model: ^Model, // background model being processed.

    shader: ^Shader,
    wip_shader: ^Shader,
}


AssetQueue :: struct {
    list:  [dynamic]^Asset,
    mutex: sync.Mutex,
}

ASSET_RELOAD_TIME :: 100 * time.Millisecond
ASSET_TIME_QUANTUM :: 10 * time.Millisecond

queue_push :: proc (queue: ^AssetQueue, asset: ^Asset) {
    sync.mutex_lock(&queue.mutex)
    defer sync.mutex_unlock(&queue.mutex)
    append(&queue.list, asset)
}
// Pops asset ready to be processed, asset may not be ready due to ASSET_RELOAD_TIME
queue_pop :: proc (queue: ^AssetQueue) -> (out_asset: ^Asset) {
    sync.mutex_lock(&queue.mutex)
    defer sync.mutex_unlock(&queue.mutex)

    out_asset = nil
    now := time.now()
    for i:=len(queue.list)-1; i>=0; i-=1 {
        asset := queue.list[i]
        diff := time.diff(asset.scheduled_time, now)
        if diff > ASSET_RELOAD_TIME {
            out_asset = asset
            unordered_remove(&queue.list, i)
            break
        }
    }
    return
}


AssetStorage :: struct {
    assets_by_name: map[string]^Asset,
    assets_by_src:  map[string]^Asset,
    game_directory: string,
    assets_mutex:   sync.Mutex,
    
    render_queue: AssetQueue, // These assets require processing on the render thread, OpenGL forces this work onto one thread.
    main_queue:   AssetQueue, // These assets require File IO or vertex, image loading and processing (anything that doesn't need render thread).

    art_watcher: util.Watcher,
}

shorten_path :: proc (state: ^EngineState, path: string) -> string {
    return strings.cut(path, len(state.storage.art_watcher.root)+1)
}

register_asset_from_store :: proc (state: ^EngineState, name: string, rel_path: string) -> ^Asset {
    fixed := strings.concatenate({state.storage.game_directory, "/assets/", rel_path})
    return register_asset(state, name, fixed)
}
register_asset :: proc (state: ^EngineState, name: string, path: string) -> ^Asset {
    fmt.printfln("Register %v", shorten_path(state, path))
    asset := new(Asset)
    asset.name = strings.clone(name)
    asset.path = strings.clone(path)
    // @TODO Check that the asset doesn't exist (path and name?)
    sync.lock(&state.storage.assets_mutex)
    state.storage.assets_by_name[asset.name] = asset
    state.storage.assets_by_src[path] = asset
    sync.unlock(&state.storage.assets_mutex)

    asset.scheduled_time = time.from_nanoseconds(0)
    asset.submit_time = time.now()
    asset.processing_time = 0

    switch filepath.ext(path) {
        case ".glsl":
            asset.type   = .SHADER
            asset.status = .NEEDS_RENDER_PROCESSING
            queue_push(&state.storage.render_queue, asset)
        case ".glb":
            asset.type   = .MODEL
            asset.status = .NEEDS_MAIN_PROCESSING
            queue_push(&state.storage.main_queue, asset)
    }

    return asset
}

register_asset_empty :: proc (state: ^EngineState, name: string) -> ^Asset {
    fmt.printfln("Register %v", name)
    asset := new(Asset)
    asset.name = strings.clone(name)
    // asset.path = strings.clone(path)
    // @TODO Check that the asset doesn't exist (path and name?)
    sync.lock(&state.storage.assets_mutex)
    state.storage.assets_by_name[asset.name] = asset
    // state.storage.assets_by_src[path] = asset
    sync.unlock(&state.storage.assets_mutex)

    asset.scheduled_time = time.from_nanoseconds(0)
    asset.submit_time = time.now()
    asset.processing_time = 0
    
    asset.type   = .MODEL
    asset.status = .FAILED

    return asset
}

update_empty_asset :: proc (state: ^EngineState, asset: ^Asset, model: ^Model) {
    asset.model = model
    asset.status = .READY
}

can_be_reloaded :: proc (asset: ^Asset) -> bool {
    return asset.status == .READY || asset.status == .FAILED
}

can_be_used :: proc (asset: ^Asset) -> bool {
    return asset.status == .READY
}


find_asset_by_name :: proc (storage: ^AssetStorage, name: string) -> ^Asset {
    sync.lock(&storage.assets_mutex)
    defer sync.unlock(&storage.assets_mutex)
    return storage.assets_by_name[name]
    
}
find_asset_by_src :: proc (storage: ^AssetStorage, path: string) -> ^Asset {
    sync.lock(&storage.assets_mutex)
    defer sync.unlock(&storage.assets_mutex)
    return storage.assets_by_src[path]
}

reload_asset :: proc (state: ^EngineState, asset: ^Asset, scheduled_time: time.Time = time.Time{0}) {
    // Here we assume two threads can't reload an asset at the same time.
    // Race condition if this happens.
    if asset.status != .READY {
        fmt.printfln("Submit reload (already reloading) %v from %v", asset.name, shorten_path(state, asset.path))
        return
    }
    fmt.printfln("Submit reload %v from %v", asset.name, shorten_path(state, asset.path))

    asset.scheduled_time = scheduled_time
    asset.submit_time = time.now()
    asset.processing_time = 0

    switch asset.type {
        case .MODEL:
            asset.status = .NEEDS_MAIN_PROCESSING
            queue_push(&state.storage.main_queue, asset)
        case .SHADER:
            asset.status = .NEEDS_RENDER_PROCESSING
            queue_push(&state.storage.render_queue, asset)
    }
}


process_asset_main :: proc (state: ^EngineState, asset: ^Asset) -> bool {
    // caller needs to change state and lock asset schedule arrays
    fmt.printfln("Process (main) %v", shorten_path(state, asset.path))
    

    switch asset.type {
        case .MODEL:
            if asset.wip_model == nil {
                asset.wip_model = new(Model)
            }
            load_model(asset.path, asset.wip_model)
        case .SHADER:
            fmt.printfln("ASSET SHADER WAS ADDED TO MAIN PROCESSING! %v", asset.name, shorten_path(state, asset.path))
            // False would tell CALLER that the asset isn't done yet.
            // To prevent infinite processing we return true.
            return true
    }
    
    // @IMPORTANT At the moment all assets do render processing. move into switch when that's not the case
    asset.status = .NEEDS_RENDER_PROCESSING
    queue_push(&state.storage.render_queue, asset)
    return true
}


process_asset_render :: proc (state: ^EngineState, asset: ^Asset) -> bool {
    fmt.printfln("Process (render) %v", shorten_path(state, asset.path))

    switch asset.type {
        case .MODEL:
            load_model_render(asset.wip_model)
            tmp := asset.model
            asset.model = asset.wip_model
            asset.wip_model = tmp
        case .SHADER:
            if asset.wip_shader == nil {
                asset.wip_shader = new(Shader)
            }
            load_shader(asset.path, asset.wip_shader)
            tmp := asset.shader
            asset.shader = asset.wip_shader
            asset.wip_shader = tmp
    }

    asset.status = .READY

    return true
}


// Multiple threads can poll assets and reload them
process_assets :: proc (state: ^EngineState, thread_type: driver.ThreadType) {
    storage := &state.storage

    work_start := time.now()

    queue: ^AssetQueue
    if driver.is_render(thread_type) {
        queue = &storage.render_queue
    } else {
        queue = &storage.main_queue
    }

    process_attempts := 0
    asset_to_process: ^Asset
    for {
        now := time.now()
        if time.diff(work_start, now) >= ASSET_TIME_QUANTUM && process_attempts > 0 {
            if asset_to_process != nil {
                queue_push(queue, asset_to_process)
                asset_to_process = nil
            }
            break
        }

        if asset_to_process == nil {
            asset_to_process = queue_pop(queue)
            if asset_to_process == nil {
                break
            }
        }

        process_attempts += 1

        start_time := time.now()
        finished: bool
        if driver.is_render(thread_type) {
            finished = process_asset_render(state, asset_to_process)
            end_time := time.now()
            asset_to_process.processing_time += time.diff(start_time, end_time)
        } else {
            finished = process_asset_main(state, asset_to_process)
        }
        
        if finished {
            asset_to_process.loaded_time = time.now()
            fmt.printfln("Loaded asset '%v' %v %v", shorten_path(state, asset_to_process.path), asset_to_process.processing_time, time.diff(asset_to_process.submit_time, asset_to_process.loaded_time))
            asset_to_process = nil
        }
    }
}