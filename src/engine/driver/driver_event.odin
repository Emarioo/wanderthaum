/*
    Data Structures for the driver
*/

package driver

import "core:sync"
import "core:thread"
import "core:dynlib"
import "core:fmt"

EventKind :: enum {
    EVENT_START,  // called after the first load
    EVENT_LOAD,
    EVENT_TICK,
    EVENT_UNLOAD,
    EVENT_STOP    // called before the final unload
}

ThreadType :: enum {
    UPDATE,   // updates entities and more main processing
    INPUT,    // window creation, input events (would normally be in UPDATE/MAIN thread but Windows blocks on window resize so we use a separate thread)
    RENDER_0 = 100,
    RENDER_MAX,
    WORKER_0 = 200, // general independent worker, IO task or read asset data, process vertex data, AI pathfinding, some networking stuff?
    WORKER_MAX,        // general independent worker, IO task or read asset data, process vertex data, AI pathfinding, some networking stuff?
}

is_render :: #force_inline proc (type: ThreadType) -> bool {
    return cast(i32)type >= cast(i32)ThreadType.RENDER_0 && cast(i32)type < cast(i32)ThreadType.RENDER_MAX
}
is_worker :: #force_inline proc (type: ThreadType) -> bool {
    return cast(i32)type >= cast(i32)ThreadType.WORKER_0 && cast(i32)type < cast(i32)ThreadType.WORKER_MAX
}

DriverData :: struct {
    running: bool,
    driver_event: proc(event: EventKind, event_data: ^EventData, data: ^DriverData),
    threads: [dynamic]^thread.Thread,
    thread_main: thread.Thread_Proc,

    user_data:        rawptr,

    thread_semaphore: sync.Sema,

    game_directory:   string,

    mutex:            sync.Mutex,
    cond:             sync.Cond,
    reload_requested: bool,
    active_threads:   i32,
    parked_threads:   i32,
}


EventData :: struct {
    user_index: int,
    user_data: rawptr,
}

permanent_library_load :: proc (path: string) {
    templib, ok := dynlib.load_library(path)
    if !ok {
        fmt.printfln("Failed loading %v", path)
    }
}

