package engine

import "core:fmt"
import "core:time"
import "core:math/rand"
// import "core:math/linalg"
import "core:sync"
import "core:container/xar"
// import "core:mem"
import "core:mem/virtual"

import "./util"
import "./graphics"
import "./graphics/shaderc"

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

Resource_Gate :: struct {
    switching: bool,
    active:    u32,
    completed: sync.Sema,
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
    // recording: Recording,
    storage: AssetStorage,

    running: bool,
    has_init_render: bool,

    reset_opengl_globals: bool,
    reset_glfw_globals: bool,
    reset_vulkan_globals: bool,
    someRenderMutex: sync.Mutex,

    // if this differs from current backend then the engine
    // will switch and destroy all graphics objects.
    // it may take some time and threads has to synchronous
    // which is why we queue it.
    queued_renderbackend: graphics.RenderBackend,
    switchingBackend: bool,
    destroyed_all_render_resources: bool,
    destroyed_all_input_resources: bool,

    switchingBackend_gate: Resource_Gate,

    game_directory: string,

    server_mode: bool,


}


resource_enter :: proc(gate: ^Resource_Gate) -> bool {
    for {
        if sync.atomic_load(&gate.switching) {
            return false
        }

        sync.atomic_add(&gate.active, 1)

        if !sync.atomic_load(&gate.switching) {
            return true
        }

        sync.atomic_sub(&gate.active, 1)
    }
}

resource_leave :: proc(gate: ^Resource_Gate) {
    old := sync.atomic_sub(&gate.active, 1)

    if old == 1 && sync.atomic_load(&gate.switching) {
        sync.sema_post(&gate.completed)
    }
}

resource_begin_switch :: proc(gate: ^Resource_Gate) {
    sync.atomic_store(&gate.switching, true)
}

resource_wait :: proc(gate: ^Resource_Gate) {
    for sync.atomic_load(&gate.active) != 0 {
        sync.sema_wait(&gate.completed)
    }
}

resource_end_switch :: proc(gate: ^Resource_Gate) {
    sync.atomic_store(&gate.switching, false)
}

engine_init :: proc (state: ^EngineState) {
    err := virtual.arena_init_growing(&state.world_arena)
    if err != nil {
        fmt.println("Could not init arena!")
        return
    }
    xar.init(&state.entities, virtual.arena_allocator(&state.world_arena))

    state.queued_renderbackend = state.render_state.graphicsState.renderBackend
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



hotreload_load :: proc (state: ^EngineState) {
    if state.render_state.graphicsState.renderBackend == .VULKAN {
        state.render_state.graphicsState.vulkanBackend.compiler = shaderc.compiler_initialize()
        if state.render_state.graphicsState.vulkanBackend.compiler == nil {
            fmt.println("Failed to initialize shaderc compiler")
            return
        }
    }
}


hotreload_unload :: proc (state: ^EngineState) {
    state.reset_opengl_globals = true
    state.reset_vulkan_globals = true
    state.reset_glfw_globals = true

    if state.render_state.graphicsState.renderBackend == .VULKAN {
        if state.render_state.graphicsState.vulkanBackend.compiler != nil {
            shaderc.compiler_release(state.render_state.graphicsState.vulkanBackend.compiler)
        }
    }
}

get_graphics_backend :: proc (state: ^EngineState) -> graphics.RenderBackend {
    return state.render_state.graphicsState.renderBackend
}

set_graphics_backend :: proc (state: ^EngineState, backend: graphics.RenderBackend) {
    if !sync.atomic_load(&state.switchingBackend) {
        state.queued_renderbackend = backend
        sync.atomic_store(&state.switchingBackend, true)
        state.destroyed_all_render_resources = true
        resource_begin_switch(&state.switchingBackend_gate)
        fmt.println("Switching Graphics API to: ", backend)
    }

    /*
        This is how we switch the graphics backend while the game is running:
        
            - We leverage an engine architecture that initializes uninitialized systems. For example:
              The input thread detects that we have no window so it creates one.
              The render thread detects that our OpenGL or Vulkan context are uninitialized so it initializes them.
            
            - What we need to do is safely destroy current resources and set fields to nil and uninitialized. While we do
              this the normal render/input execution path is disabled. We enable it when all resources have been destroyed.
              The engine will then behave as described by the first point.

    */
}
