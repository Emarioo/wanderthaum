package central

import "core:time"
// import "core:math"
// import "core:math/linalg"
import "core:sync"

import "./util"

MAX_ENTITIES :: 1024

FIXED_UPDATE_DELTA :: 1.0/60.0


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

EngineState :: struct {

    entities:       [MAX_ENTITIES]Entity,
    entities_count: u32,

    startTime:    time.Time,
    lastTime:     time.Time,
    accDeltaTime: f32,
    delta:        f32,
    fixedDelta:   f32,

    current_tick: u32, // 60 ticks per second, unsigned 32-bit int can hold ~2.2 years of game time (2^32/60/60/60/24/365)

    render_state: RenderState,
    recording: Recording,
    storage: AssetStorage,

    running: bool,
    has_init_render: bool,

    reset_opengl_globals: bool,
    reset_glfw_globals: bool,

    game_directory: string,
}

Entity :: struct {
    pos: vec3,
    vel: vec3,
    force: vec3,
}

create_entity :: proc (state: ^EngineState) -> (^Entity, u32) {
    index := state.entities_count
    state.entities_count += 1
    ent := &state.entities[index]

    ent.pos = {0,0,0}
    ent.vel = {0,0,0}
    ent.force = {0,0,0}

    return ent, index
}

get_entity :: proc (state: ^EngineState, index: u32) -> ^Entity {
    return &state.entities[index]
}