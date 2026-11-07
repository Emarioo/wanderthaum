package central

import "core:fmt"
import "core:math"
import "core:sync"
import "core:math/linalg/glsl"
import "core:strings"
import "core:os"

import "../engine/util"
import "../engine"


game_init :: proc (state: ^GameState) {
    
    engine.engine_init(&state.engineState)

    // @TODO Try reading settings from a file
    generate_default_bindings(&state.keymap)

    engine.set_default_keymap(&state.engineState, &state.keymap)
    engine.create_input_actor(&state.engineState, &state.keymap)

    state.default_world_path = strings.clone(string("temp_world.wth"))

    loaded_world := sync_world(state.default_world_path, .LOAD_WORLD, state)
    
    if !loaded_world {
        player, player_id := engine.create_entity(&state.engineState)
        player.flags |= engine.ENTITY_FLAG_PLAYER
        state.player_id = player_id
        // player.hidden = true
        player.asset = engine.register_asset_empty(&state.engineState, "cube")
    } else {
        for i in 0..<engine.get_entity_count(&state.engineState) {
            entity := engine.get_entity_by_index(&state.engineState, i)
            if (entity.flags & engine.ENTITY_FLAG_PLAYER) != 0 {
                state.player_id = entity.id
                break
            }
        }
    }

    assets_path := strings.concatenate({state.engineState.game_directory, "/assets"})
    util.watcher_init(&state.engineState.storage.art_watcher, assets_path)


    
    // entity, _ := create_entity(&state.engineState)
    // entity.asset = state.engineState.render_state.cube_asset

    // look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
    //             glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
    // look_vector := glsl.normalize_vec3(look_mat[2].xyz) * -1
    
    // entity.pos = editor.editorCamera_pos + look_vector * 5
}

apply_force :: proc (state: ^GameState) {
    speed: f32 = 0.5
    render := &state.engineState.render_state

    actor := &state.engineState.inputState.actors[0]
    if actor.actions[Input_Action.MOVE_SPRINT].value > 0 {
        speed *= 4
    }

    player := engine.get_entity(&state.engineState, state.player_id)



    // look_mat := glsl.mat4Rotate(vec3{0,1,0}, render.camera_rotation.y) *
    //             glsl.mat4Rotate(vec3{1,0,0}, render.camera_rotation.x)
    // look_vector := glsl.normalize_vec3(look_mat[2].xyz)

    forward_mat := glsl.mat4Rotate(vec3{0,1,0}, render.camera_rotation.y)
    right_mat := glsl.mat4Rotate(vec3{0,1,0}, render.camera_rotation.y + math.PI/2)
    forward_vector := glsl.normalize_vec3(forward_mat[2].xyz)
    right_vector := glsl.normalize_vec3(right_mat[2].xyz)
    up_vector := vec3{0,1,0}

    force : vec3

    if actor.actions[Input_Action.MOVE_FORWARD].value > 0 {
        // forward
        force += -forward_vector 
    }
    if actor.actions[Input_Action.MOVE_RIGHT].value > 0 {
        // right
        force += right_vector 
    }
    if actor.actions[Input_Action.MOVE_BACKWARD].value > 0 {
        // back
        force += forward_vector 
    }
    if actor.actions[Input_Action.MOVE_LEFT].value > 0 {
        // left
        force += -right_vector 
    }
    if actor.actions[Input_Action.MOVE_UP].value > 0 {
        // up
        force += up_vector
    }
    if actor.actions[Input_Action.MOVE_DOWN].value > 0 {
        // down
        force += -up_vector 
    }

    // Apply friction
    player.vel *= 0.85
    state.editor.editorCamera_vel *= 0.92

    if !state.editor.editorEnabled {
        player.force += force * speed
        state.player_rot = state.engineState.render_state.camera_rotation
    } else {
        state.editor.editorCamera_vel += force * speed
        state.editor.editorCamera_rot = state.engineState.render_state.camera_rotation
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
    }
    if isKeyPressed(actor, .LOAD_WORLD) {
        sync_world(state.default_world_path, .LOAD_WORLD, state)
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
        
        // fmt.printfln("force %v %v %v", ent.force.x, ent.force.y, ent.force.z)

        // @TODO SIMD
        ent.vel += ent.force
        ent.pos += ent.vel * state.engineState.fixedDelta
        ent.force = {0,0,0}

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

resolve_collision :: proc(a, b: ^engine.Entity) {
    a_min, a_max := get_min_max_point(a)
    b_min, b_max := get_min_max_point(b)

    if !aabb_intersects(a_min, a_max, b_min, b_max) {
        return
    }

    overlap := vec3{
        min(a_max.x, b_max.x) - max(a_min.x, b_min.x),
        min(a_max.y, b_max.y) - max(a_min.y, b_min.y),
        min(a_max.z, b_max.z) - max(a_min.z, b_min.z),
    }

    // Find the axis with the smallest overlap.
    axis := 0
    if overlap.y < overlap.x do axis = 1
    if overlap.z < overlap[axis] do axis = 2

    // Determine which direction to push.
    if a.pos[axis] < b.pos[axis] {
        a.pos[axis] -= overlap[axis] * 0.5
        b.pos[axis] += overlap[axis] * 0.5
    } else {
        a.pos[axis] += overlap[axis] * 0.5
        b.pos[axis] -= overlap[axis] * 0.5
    }

    // Remove velocity along the collision axis.
    a.vel[axis] = 0
    b.vel[axis] = 0
}

aabb_intersects :: proc(a_min, a_max, b_min, b_max: vec3) -> bool {
    return (
        a_min.x <= b_max.x && a_max.x >= b_min.x &&
        a_min.y <= b_max.y && a_max.y >= b_min.y &&
        a_min.z <= b_max.z && a_max.z >= b_min.z
    )
}
