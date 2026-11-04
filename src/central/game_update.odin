package central

import "core:fmt"
import "core:math"
import "core:sync"
import "core:math/linalg/glsl"
import "core:strings"
import "core:os"

import "./util"



update_init :: proc (state: ^GameState) {
    
    append(&state.engine.inputState.actors, {})

    state.default_world_path = strings.clone(string("temp_world.wth"))

    loaded_world := sync_world(state.default_world_path, .LOAD_WORLD, state)
    
    if !loaded_world {
        player, player_index := create_entity(&state.engine)
        state.player_index = player_index
        // player.hidden = true
        player.asset = register_asset_empty(&state.engine, "cube")
    }

    assets_path := strings.concatenate({state.engine.game_directory, "/assets"})
    util.watcher_init(&state.engine.storage.art_watcher, assets_path)


    
    entity, _ := create_entity(&state.engine)
    entity.asset = state.engine.render_state.cube_asset

    // look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
    //             glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
    // look_vector := glsl.normalize_vec3(look_mat[2].xyz) * -1
    
    // entity.pos = editor.editorCamera_pos + look_vector * 5
}

apply_force :: proc (state: ^GameState) {
    speed: f32 = 0.5
    render := &state.engine.render_state

    actor := &state.engine.inputState.actors[0]
    if actor.actions[Input_Action.MOVE_SPRINT].value > 0 {
        speed *= 4
    }

    player := get_entity(&state.engine, state.player_index)



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
        state.player_rot = state.engine.render_state.camera_rotation
    } else {
        state.editor.editorCamera_vel += force * speed
        state.editor.editorCamera_rot = state.engine.render_state.camera_rotation
    }

    state.editor.editorCamera_pos += state.editor.editorCamera_vel * state.engine.fixedDelta
    

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
    actor := &state.engine.inputState.actors[0]
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

        sync.lock(&state.engine.storage.assets_mutex)
        for key, asset in state.engine.storage.assets_by_name {
            reload_asset(&state.engine, asset)
        }
        sync.unlock(&state.engine.storage.assets_mutex)
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
    for i in 0..<state.engine.entities_count {
        ent := &state.engine.entities[i]

        if !valid_entity(&state.engine, ent) {
            continue
        }
        
        // fmt.printfln("force %v %v %v", ent.force.x, ent.force.y, ent.force.z)

        // @TODO SIMD
        ent.vel += ent.force
        ent.pos += ent.vel * state.engine.fixedDelta
        ent.force = {0,0,0}

    }


    // @TODO Optimize below with sparse trees?

    // Resolve collisions
    for i in 0..<state.engine.entities_count {
        a := &state.engine.entities[i]

        if !valid_entity(&state.engine, a) {
            continue
        }

        for j in i+1..<state.engine.entities_count {
            b := &state.engine.entities[j]

            if !valid_entity(&state.engine, b) {
                continue
            }

            resolve_collision(a, b)
        }
    }
}

resolve_collision :: proc(a, b: ^Entity) {
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
