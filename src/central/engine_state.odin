package central

import "core:time"
import "core:math/rand"
// import "core:math/linalg"
import "core:sync"

import "./util"

MAX_ENTITIES :: 1024

FIXED_UPDATE_DELTA :: 1.0/60.0



EngineState :: struct {

    entities:       [MAX_ENTITIES]Entity,
    entities_count: u32,

    startTime:    time.Time,
    lastTime:     time.Time,
    accDeltaTime: f32,
    delta:        f32,
    fixedDelta:   f32,

    current_tick: u32, // 60 ticks per second, unsigned 32-bit int can hold ~2.2 years of game time (2^32/60/60/60/24/365)

    inputState: Input_State,
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
    id: u64,
    pos: vec3,
    scale: vec3,
    vel: vec3,
    force: vec3,

    hidden: bool,
    killed: bool,
    asset: ^Asset,
}

create_entity :: proc (state: ^EngineState) -> (^Entity, u32) {
    index := state.entities_count
    state.entities_count += 1
    ent := &state.entities[index]
    ent.id = rand.uint64()

    ent.pos = {0,0,0}
    ent.scale = {1,1,1}
    ent.vel = {0,0,0}
    ent.force = {0,0,0}

    return ent, index
}

copy_entity_data :: proc (state: ^EngineState, from: ^Entity, to: ^Entity) {
    to.pos = from.pos
    to.scale = from.scale
    to.vel = from.vel
    to.force = from.force
    to.hidden = from.hidden
    to.killed = from.killed
    to.asset = from.asset
}

get_entity :: proc (state: ^EngineState, index: u32) -> ^Entity {
    return &state.entities[index]
}

kill_entity :: proc (state: ^EngineState, entity: ^Entity) {
    entity.killed = true
}

valid_entity :: proc (state: ^EngineState, entity: ^Entity) -> bool {
    return !entity.killed
}