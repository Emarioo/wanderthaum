package central

import "core:fmt"
import "core:time"
import "core:math/rand"
// import "core:math/linalg"
import "core:sync"
import "core:container/xar"
// import "core:mem"
import "core:mem/virtual"

import "./util"

// MAX_ENTITIES :: 1024

FIXED_UPDATE_DELTA :: 1.0/60.0


EntityID :: u64
INVALID_ENTITY_ID : EntityID : 0

ENTITY_FLAG_PLAYER :: 1 << 0

Entity :: struct {
    id: EntityID,
    pos: vec3,
    scale: vec3,
    vel: vec3,
    force: vec3,

    flags: u8,
    hidden: bool,
    killed: bool,
    asset: ^Asset,
}

EngineState :: struct {

    entities: xar.Array(Entity, 10),
    entity_id_map: map[EntityID]^Entity,

    world_arena: virtual.Arena,

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

engine_init :: proc (state: ^EngineState) {
    err := virtual.arena_init_growing(&state.world_arena)
    if err != nil {
        fmt.println("Could not init arena!")
        return
    }
    xar.init(&state.entities, virtual.arena_allocator(&state.world_arena))
}

get_entity_count :: proc (state: ^EngineState) -> int {
    return xar.array_len(state.entities)
}

get_entity_by_index :: proc (state: ^EngineState, index: int) -> ^Entity {
    return xar.get_ptr(&state.entities, index)
}

entity_clear :: proc (state: ^EngineState) {
    xar.clear(&state.entities)
}

create_entity_from_id :: proc (state: ^EngineState, id: EntityID) -> ^Entity {
    entity, err := xar.push_back_elem_and_get_ptr(&state.entities, {})

    if err != nil {
        return nil
    }

    entity.id    = id
    entity.pos   = {0,0,0}
    entity.scale = {1,1,1}
    entity.vel   = {0,0,0}
    entity.force = {0,0,0}

    state.entity_id_map[entity.id] = entity

    return entity
}

create_entity :: proc (state: ^EngineState) -> (^Entity, EntityID) {
    id := rand.uint64()
    entity := create_entity_from_id(state, id)
    if entity == nil {
        return nil, INVALID_ENTITY_ID
    }
    return entity, id
}

copy_entity_data :: proc (state: ^EngineState, from: ^Entity, to: ^Entity) {
    to.pos = from.pos
    to.scale = from.scale
    to.vel = from.vel
    to.force = from.force
    to.hidden = from.hidden
    to.killed = from.killed
    to.flags = from.flags
    to.asset = from.asset
}

get_entity :: proc (state: ^EngineState, id: EntityID) -> ^Entity {
    entity, found := state.entity_id_map[id]
    if !found {
        return nil
    }
    return entity
}

kill_entity :: proc (state: ^EngineState, entity: ^Entity) {
    entity.killed = true
}

valid_entity :: proc (state: ^EngineState, entity: ^Entity) -> bool {
    if entity == nil {
        return false
    }
    return !entity.killed
}
