package central

import "core:fmt"
import "core:math"
import "core:sync"
import "core:time"
import "core:math/linalg/glsl"
import "core:math/linalg"
import "core:strings"
import "core:os"

import "../engine/util"
import "../engine"

AUTOSAVE_PERIOD :: 30 * time.Second

GRAVITY :: -0.6

game_init :: proc (state: ^GameState) {
    
    engine.engine_init(&state.engineState)

    // @TODO Try reading settings from a file
    generate_default_bindings(&state.keymap)

    engine.set_default_keymap(&state.engineState, &state.keymap)
    engine.create_input_actor(&state.engineState, &state.keymap)

    state.default_world_path = strings.clone(string("temp_world.wth"))

    loaded_world := sync_world(state.default_world_path, .LOAD_WORLD, state)
    state.lastAutosaveTime = time.now()

    try_create_player(state)
    

    assets_path := strings.concatenate({state.engineState.game_directory, "/assets"})
    util.watcher_init(&state.engineState.storage.art_watcher, assets_path)


    
    // entity, _ := create_entity(&state.engineState)
    // entity.asset = state.engineState.render_state.cube_asset

    // look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
    //             glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
    // look_vector := glsl.normalize_vec3(look_mat[2].xyz) * -1
    
    // entity.pos = editor.editorCamera_pos + look_vector * 5
}

try_create_player :: proc (state: ^GameState) {
    state.player_id = engine.INVALID_ENTITY_ID

    for i in 0..<engine.get_entity_count(&state.engineState) {
        entity := engine.get_entity_by_index(&state.engineState, i)
        if entity.type == .PLAYER {
            state.player_id = entity.id
            break
        }
    }
    if state.player_id == engine.INVALID_ENTITY_ID {
        player, player_id := engine.create_entity(&state.engineState)
        player.type = .PLAYER
        engine.set_entity_gravity(player, true)
        state.player_id = player_id
        player.asset = engine.register_asset_empty(&state.engineState, "cube")
    }
}

apply_force :: proc (state: ^GameState) {
    speed: f32 = 0.4
    jumpForce: f32 = 9.2 // allows us to jump slightly more than 1 unit
    render := &state.engineState.render_state

    actor := &state.engineState.inputState.actors[0]
    if isKeyDown(actor, .MOVE_SPRINT) {
        if state.editor.editorMode == .FREECAM {
            speed *= 5
        } else {
            speed *= 2.2
        }
    }


    player := engine.get_entity(&state.engineState, state.player_id)

    rot: vec3
    if player != nil && state.editor.editorMode != .FREECAM {
        rot = engine.euler_from_entity_rot(player)
        // fmt.println(rot)
    } else {
        rot = render.input_rotation
    }

    forward_mat := glsl.mat4Rotate(vec3{0,1,0}, rot.y)
    right_mat := glsl.mat4Rotate(vec3{0,1,0}, rot.y + math.PI/2)
    forward_vector := glsl.normalize_vec3(forward_mat[2].xyz)
    right_vector := glsl.normalize_vec3(right_mat[2].xyz)
    up_vector := vec3{0,1,0}


    force : vec3

    if isKeyDown(actor, .MOVE_FORWARD) {
        // forward
        force += -forward_vector * speed
    }
    if isKeyDown(actor, .MOVE_RIGHT) {
        // right
        force += right_vector * speed
    }
    if isKeyDown(actor, .MOVE_BACKWARD) {
        // back
        force += forward_vector * speed
    }
    if isKeyDown(actor, .MOVE_LEFT) {
        // left
        force += -right_vector * speed
    }
    if state.editor.editorMode == .FREECAM {
        if isKeyDown(actor, .MOVE_UP) {
            // up
            force += up_vector * speed
        }
        if isKeyDown(actor, .MOVE_DOWN) {
            // down
            force += -up_vector * speed
        }
    } else {
        if isKeyDown(actor, .MOVE_UP) {
            // Only allowed to jump if on ground recently
            if player != nil && time.diff(player.lastTimeOnGround, time.now()) < 70 * time.Millisecond {
                force += up_vector * jumpForce
                player.lastTimeOnGround = {}
            }
        }
    }
    
    // Apply friction
    state.editor.editorCamera_vel *= 0.92

    if state.editor.editorMode != .FREECAM {
        if player != nil {
            player.force += force
        }
        player_rot := state.engineState.render_state.input_rotation
        // player.rot = linalg.quaternion_from_euler_angles_f32(player_rot.y + math.PI, -player_rot.x, player_rot.z, .YXZ)
        // player.rot = linalg.quaternion_from_euler_angles_f32(player_rot.y + math.PI, 0, 0, .YXZ)
        player.rot = linalg.quaternion_from_euler_angles_f32(player_rot.y, 0, 0, .YXZ)
    } else {
        state.editor.editorCamera_vel += force
        state.editor.editorCamera_rot = state.engineState.render_state.input_rotation
    }

    state.editor.editorCamera_pos += state.editor.editorCamera_vel * state.engineState.fixedDelta
    

    // Put events into recorder
    // only care about event changes. Key started or stopped being pressed.

    
    // tick_record: ^TickRecord = &state.recording.tick_records[len(state.recording.tick_records)-1]
    // for i in 0..<len(render.move) {
    //     if render.prev_move[i] != render.move[i] {
    //         append(&tick_record.actions, Action{})
    //         action := &tick_record.actions[len(tick_record.actions)-1]
    //         action.kind = cast(i32)i
    //         action.state = cast(i32)render.move[i]
    //     }
    // }
}



update_state :: proc (state: ^GameState) {
    // if len(state.recording.tick_records) > 0 {
    //     // If previous tick had
    //     tick_record: ^TickRecord = &state.recording.tick_records[len(state.recording.tick_records)-1]
    //     if len(tick_record.actions) > 0 {
    //         append(&state.recording.tick_records, TickRecord{})
    //     }
    // } else {
    //     append(&state.recording.tick_records, TickRecord{})
    // }
    // tick_record: ^TickRecord = &state.recording.tick_records[len(state.recording.tick_records)-1]
    // tick_record.frame = state.current_tick

    // fmt.println("State")
    actor := &state.engineState.inputState.actors[0]
    if actor.actions[Input_Action.RELOAD_ASSETS].pressed > 0 {

        // The engine should handle reloading game code and assets at the same time.
        // Good way to stress test it.

        when ODIN_OS == .Windows {
            args := []string{
                "python",
                "build.py",
                "hot",
            }
        } else {
            args := []string{
                "python3",
                "build.py",
                "hot",
            }
        }
        // fmt.println("RELOADING GAME CODE")

        handle, err := os.process_start(
            os.Process_Desc{
                working_dir = "",
                command = args,
                env =  []string{},
                stderr = os.stderr,
                stdout = os.stdout,
                stdin = os.stdin,
            }
        )
        if err == os.ERROR_NONE {
            state: os.Process_State
            state, err = os.process_wait(handle)
            if err != os.ERROR_NONE {
                fmt.printfln("process_wait: %v", err)
            }
        } else {
            fmt.printfln("process_start: %v", err)
        }

        sync.lock(&state.engineState.storage.assets_mutex)
        for key, asset in state.engineState.storage.assets_by_name {
            engine.reload_asset(&state.engineState, asset)
        }
        sync.unlock(&state.engineState.storage.assets_mutex)
    }

    if isKeyPressed(actor, .SAVE_WORLD) {
        sync_world(state.default_world_path, .SAVE_WORLD, state)
        state.lastAutosaveTime = time.now()
    }
    if isKeyPressed(actor, .LOAD_WORLD) {
        sync_world(state.default_world_path, .LOAD_WORLD, state)
        try_create_player(state)
    }

    nowTime := time.now()
    if time.diff(state.lastAutosaveTime, nowTime) > AUTOSAVE_PERIOD {
        sync_world(state.default_world_path, .SAVE_WORLD, state)
        finishTime := time.now()
        state.lastAutosaveTime = nowTime
        fmt.printfln("Autosaved %v in %v", state.default_world_path, time.diff(nowTime, finishTime))
    }
    
    if isKeyPressed(actor, .DEBUG_KEY) {
        for i in 0..<engine.get_entity_count(&state.engineState) {
            ent := engine.get_entity_by_index(&state.engineState, i)
            fmt.println(ent)
        }
        fmt.println(state.engineState.entity_id_map)
    }
    
    if isKeyPressed(actor, .OPENGL_BACKEND) {
        engine.set_graphics_backend(&state.engineState, .OPENGL)
    }
    if isKeyPressed(actor, .VULKAN_BACKEND) {
        engine.set_graphics_backend(&state.engineState, .VULKAN)
    }


    tick_editor(state)

    // apply player force
    apply_force(state)

    // Update positions
    for i in 0..<engine.get_entity_count(&state.engineState) {
        ent := engine.get_entity_by_index(&state.engineState, i)

        if !engine.valid_entity(&state.engineState, ent) {
            continue
        }

        if !engine.is_static_entity(ent) && engine.has_entity_gravity(ent) {
            ent.force.y += GRAVITY
        }

        // @TODO SIMD
        ent.vel += ent.force
        ent.pos += ent.vel * state.engineState.fixedDelta
        ent.force = {0,0,0}

        FRICTION :: 0.85
        ent.vel.x *= FRICTION
        ent.vel.z *= FRICTION

        FLOOR_Y :: -10.0

        if ent.pos.y < FLOOR_Y {
            ent.pos.y = FLOOR_Y
            // ent.vel.y = 0
            ent.vel.y *= -0.3
            ent.lastTimeOnGround = time.now()
        }

    }


    // @TODO Optimize below with sparse trees?

    // Resolve collisions
    for i in 0..<engine.get_entity_count(&state.engineState) {
        a := engine.get_entity_by_index(&state.engineState, i)

        if !engine.valid_entity(&state.engineState, a) {
            continue
        }

        for j in i+1..<engine.get_entity_count(&state.engineState) {
            b := engine.get_entity_by_index(&state.engineState, j)

            if !engine.valid_entity(&state.engineState, b) {
                continue
            }
            resolve_collision(a, b)
        }
    }
}

entity_mass :: proc (entity: ^engine.Entity) -> f32 {
    box_min, box_max := get_min_max_point(entity)
    volume3 := box_max - box_min
    // return max(2 * (volume3.x*volume3.x + volume3.y* volume3.y + volume3.z*volume3.z), 0.01)
    // return max(2 * (volume3.x * volume3.y * volume3.z), 0.01)
    return max((volume3.x * volume3.y * volume3.z), 0.01)
}

resolve_collision :: proc(a, b: ^engine.Entity) {
    a_min, a_max := get_min_max_point(a)
    b_min, b_max := get_min_max_point(b)

    if !aabb_intersects(a_min, a_max, b_min, b_max) {
        return
    }

    a_mass := entity_mass(a)
    b_mass := entity_mass(b)
    // a_mass_factor: f32
    // if a_mass > b_mass {
    //     a_mass_factor = 0
    // } else {
    //     a_mass_factor = 1
    // }
    a_mass_factor := b_mass / (a_mass + b_mass)
    b_mass_factor := 1 - a_mass_factor

    // fmt.println(a_mass, b_mass)

    overlap := vec3{
        min(a_max.x, b_max.x) - max(a_min.x, b_min.x),
        min(a_max.y, b_max.y) - max(a_min.y, b_min.y),
        min(a_max.z, b_max.z) - max(a_min.z, b_min.z),
    }

    // Find the axis with the smallest overlap.
    axis := 0
    if overlap.y < overlap.x do axis = 1
    if overlap.z < overlap[axis] do axis = 2

    if axis == 1 {
        // @TODO Only the entity above should get ground time updated.
        a.lastTimeOnGround = time.now()
        b.lastTimeOnGround = time.now()
    }

    if !engine.is_static_entity(a) && !engine.is_static_entity(b) {
        // Determine which direction to push.
        if a.pos[axis] < b.pos[axis] {
            a.pos[axis] -= overlap[axis] * (1 - a_mass_factor)
            b.pos[axis] += overlap[axis] * (1 - b_mass_factor)
        } else {
            a.pos[axis] += overlap[axis] * (1 - a_mass_factor)
            b.pos[axis] -= overlap[axis] * (1 - b_mass_factor)
        }

        sum_vel := a.vel[axis] + b.vel[axis]

        // Remove velocity along the collision axis.
        a.vel[axis] = sum_vel * a_mass_factor
        b.vel[axis] = sum_vel * b_mass_factor
    } else if !engine.is_static_entity(a) && engine.is_static_entity(b) {
        // Determine which direction to push.
        if a.pos[axis] < b.pos[axis] {
            a.pos[axis] -= overlap[axis]
        } else {
            a.pos[axis] += overlap[axis]
        }

        // Remove velocity along the collision axis.
        a.vel[axis] = b.vel[axis]
    } else if engine.is_static_entity(a) && !engine.is_static_entity(b) {
        // Determine which direction to push.
        if a.pos[axis] < b.pos[axis] {
            b.pos[axis] += overlap[axis]
        } else {
            b.pos[axis] -= overlap[axis]
        }

        // Remove velocity along the collision axis.
        b.vel[axis] = a.vel[axis]
    } else {
        // static objects can overlap
    }
}

aabb_intersects :: proc(a_min, a_max, b_min, b_max: vec3) -> bool {
    return (
        a_min.x <= b_max.x && a_max.x >= b_min.x &&
        a_min.y <= b_max.y && a_max.y >= b_min.y &&
        a_min.z <= b_max.z && a_max.z >= b_min.z
    )
}
