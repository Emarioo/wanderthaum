
package central

import "core:fmt"

import "core:math/linalg/glsl"

import gl "vendor:OpenGL"

Editor_Tool :: enum {
    SELECT,
    MOVE,
    SCALE,
    ROTATE
}

Editor_Axis_Mode :: enum {
    AXIS_CAMERA,
    AXIS_X,
    AXIS_Y,
    AXIS_Z,
    PLANE_XZ,
    PLANE_XY,
    PLANE_YZ,
}

Editor_Event_Type :: enum {
    SELECT_OBJECT,
    DESELECT_OBJECT,
    MOVE_OBJECT,
    SCALE_OBJECT,
    // CHANGE_TOOl,
}

Editor_Event_Data :: struct {
    entityID: u64,
    previous_dataPoint: vec3,
}

Editor_Event :: struct {
    eventType: Editor_Event_Type,
    // previous_tool: Editor_Tool,
    affectedObjects: [dynamic]Editor_Event_Data,
}

Editor_State :: struct {
    editorEnabled: bool,

    tool: Editor_Tool,
    axisMode: Editor_Axis_Mode,
    dragging: bool,

    averageObjectPos: vec3,
    origin_editorPos: vec3,
    startDragPoint: vec3,
    
    selectedObjects: [dynamic]u64,

    eventHistory: [dynamic]Editor_Event,

    editorCamera_pos: vec3,
    editorCamera_rot: vec3,

}

calculate_move_pos :: proc (gameState: ^GameState) -> (bool, vec3) {
    editor := &gameState.editor

    look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
                glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
    look_vector := glsl.normalize_vec3(look_mat[2].xyz) * -1

    if editor.axisMode == .AXIS_CAMERA {
        distance := glsl.length(editor.averageObjectPos - editor.origin_editorPos)
        return true, editor.editorCamera_pos + look_vector * distance
    }

    plane_normal: vec3
    #partial switch editor.axisMode {
        case .PLANE_XY: plane_normal = {0,0,1}
        case .PLANE_XZ: plane_normal = {0,1,0}
        case .PLANE_YZ: plane_normal = {1,0,0}
        case .AXIS_X:   plane_normal = {0,0,1}
        case .AXIS_Y:   plane_normal = {1,0,1}
        case .AXIS_Z:   plane_normal = {0,1,0}
    }

    hit: bool
    intersect_point: vec3
    hit, intersect_point = ray_plane_intersection(editor.editorCamera_pos, look_vector, editor.averageObjectPos, plane_normal)
    
    if !hit {
        return false, {}
    }

    #partial switch editor.axisMode {
        case .AXIS_X: intersect_point = {intersect_point.x,0,0}
        case .AXIS_Y: intersect_point = {0,intersect_point.y,0}
        case .AXIS_Z: intersect_point = {0,0,intersect_point.z}
    }

    return true, intersect_point
}

average_object_pos :: proc (gameState: ^GameState) -> vec3 {
    editor := &gameState.editor

    if len(editor.selectedObjects) == 0 {
        return {}
    }

    pos: vec3
    for i in 0..<len(editor.selectedObjects) {
        id := editor.selectedObjects[i]
        entity := get_entity(&gameState.engine, cast(u32)id)
        pos += entity.pos
    }
    return pos / cast(f32)len(editor.selectedObjects)
}

tick_editor :: proc (gameState: ^GameState) {
    editor := &gameState.editor
    actor := &gameState.engine.inputState.actors[0]
    if isKeyPressed(actor, .EDITOR_TOGGLE) {
        fmt.println("Toggle editor")

        gameState.editor.editorEnabled = !gameState.editor.editorEnabled
    }

    if isKeyPressed(actor, .EDITOR_TOOL0) {
        editor.tool = .SELECT
        editor.dragging = false
    } else if isKeyPressed(actor, .EDITOR_TOOL1) {
        editor.tool = .MOVE
        editor.dragging = false
    } else if isKeyPressed(actor, .EDITOR_TOOL2) {
        editor.tool = .SCALE
        editor.dragging = false
    }

    editor.editorCamera_rot = gameState.engine.render_state.camera_rotation
    editor.editorCamera_pos = gameState.engine.render_state.camera_position

    if gameState.editor.editorEnabled {

        look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
                    glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
        look_vector_normal := glsl.normalize_vec3(look_mat[2].xyz) * -1
        // @TODO If cursor isn't locked then we calculate look vector differently
        
        if isKeyPressed(actor, .EDITOR_DELETE) {
            for i in 0..<len(editor.selectedObjects) {
                id := editor.selectedObjects[i]
                entity := get_entity(&gameState.engine, cast(u32)id)
                kill_entity(&gameState.engine, entity)
            }
            clear(&editor.selectedObjects)
        }

        if editor.tool == .SELECT {
            if isKeyDown(actor, .PRIMARY_ACTION) {
                
                // event: Editor_Event
                // event.eventType = .DESELECT_OBJECT
                // for i in 0..<len(editor.selectedObjects) {
                //     id := editor.selectedObjects[i]
                //     append(&event.affectedObjects, { id, {} })
                //     fmt.println("Deselect", id)
                // }
                if !isKeyDown(actor, .EDITOR_APPEND_SELECT) && isKeyPressed(actor, .PRIMARY_ACTION) {
                    // for i in 0..<len(editor.selectedObjects) {
                    //     id := editor.selectedObjects[i]
                    //     // append(&event.affectedObjects, { id, {} })
                    //     // fmt.println("Deselect", id)
                    // }
                    clear(&editor.selectedObjects)
                }

                // append(&editor.eventHistory, event)

                // event: Editor_Event
                // event.eventType = .SELECT_OBJECT

                any_selection := false

                for ei in 0..<gameState.engine.entities_count {
                    entityID := cast(u64)ei // @TODO Use proper ID

                    entity := get_entity(&gameState.engine, cast(u32)entityID)
                    if !valid_entity(&gameState.engine, entity) {
                        continue
                    }
                    // @TODO Select bounding box of the entity, sphere is simple for now.
                    hit, distance := ray_sphere_intersection(editor.editorCamera_pos, look_vector_normal, entity.pos, 0.5)
                    // if hit {
                    //     fmt.println("Hit",ei,distance)
                    // }
                    if hit && distance > 0.7 && distance < 60 {
                        alreadyExists := false
                        // @TODO Maintain sorted list of selected objects
                        for si in 0..<len(editor.selectedObjects) {
                            if editor.selectedObjects[si] == entityID {
                                alreadyExists = true
                                break
                            }
                        }
                        if !alreadyExists {
                            // append(&event.affectedObjects, { entityID, {} })
                            append(&editor.selectedObjects, entityID)
                            // fmt.println("Select", ei)
                        }
                        any_selection = true
                    }
                }

                // if !any_selection {
                //     event.eventType = .DESELECT_OBJECT
                //     for i in 0..<len(editor.selectedObjects) {
                //         id := editor.selectedObjects[i]
                //         append(&event.affectedObjects, { id, {} })
                //         fmt.println("Deselect", id)
                //     }
                //     clear(&editor.selectedObjects)
                // }

                // append(&editor.eventHistory, event)
            }
        }

        updateAxisMode :: proc (editor: ^Editor_State, actor: ^Input_Actor) {
            if isKeyPressed(actor, .EDITOR_PLANE_XZ) {
                editor.axisMode = .PLANE_XZ
            }
            if isKeyPressed(actor, .EDITOR_PLANE_XY) {
                editor.axisMode = .PLANE_XY
            }
            if isKeyPressed(actor, .EDITOR_PLANE_YZ) {
                editor.axisMode = .PLANE_YZ
            }
            if isKeyPressed(actor, .EDITOR_AXIS_X) {
                editor.axisMode = .AXIS_X
            }
            if isKeyPressed(actor, .EDITOR_AXIS_Y) {
                editor.axisMode = .AXIS_Y
            }
            if isKeyPressed(actor, .EDITOR_AXIS_Z) {
                editor.axisMode = .AXIS_Z
            }
            if isKeyPressed(actor, .EDITOR_AXIS_CAMERA) {
                editor.axisMode = .AXIS_CAMERA
            }
        }

        if editor.tool == .MOVE {

            if isKeyPressed(actor, .PRIMARY_ACTION) {
                editor.averageObjectPos = average_object_pos(gameState)
                editor.origin_editorPos = editor.editorCamera_pos
                valid: bool
                valid, editor.startDragPoint = calculate_move_pos(gameState)
                if valid {
                    editor.dragging = true
                }
            }
            
            updateAxisMode(editor, actor)

            if editor.dragging {
                if !isKeyDown(actor, .PRIMARY_ACTION) {
                    editor.dragging = false

                    // @TODO Add event
                }
                valid, dragPoint := calculate_move_pos(gameState)
                if valid {
                    move_diff := dragPoint - editor.startDragPoint

                    for i in 0..<len(editor.selectedObjects) {
                        id := editor.selectedObjects[i]
                        entity := get_entity(&gameState.engine, cast(u32)id)
                        if !valid_entity(&gameState.engine, entity) {
                            continue
                        }
                        entity.pos += move_diff
                    }
                    editor.startDragPoint = dragPoint
                }
            }
        }
        
        if editor.tool == .SCALE {

            if isKeyPressed(actor, .PRIMARY_ACTION) {
                editor.averageObjectPos = average_object_pos(gameState)
                editor.origin_editorPos = editor.editorCamera_pos
                valid: bool
                valid, editor.startDragPoint = calculate_move_pos(gameState)
                if valid {
                    editor.dragging = true
                }
            }

            updateAxisMode(editor, actor)

            if editor.dragging {
                if !isKeyDown(actor, .PRIMARY_ACTION) {
                    editor.dragging = false

                    // @TODO Add event
                }
                valid, dragPoint := calculate_move_pos(gameState)
                if valid {
                    move_diff := dragPoint - editor.startDragPoint

                    for i in 0..<len(editor.selectedObjects) {
                        id := editor.selectedObjects[i]
                        entity := get_entity(&gameState.engine, cast(u32)id)
                        if !valid_entity(&gameState.engine, entity) {
                            continue
                        }
                        entity.scale += 2*move_diff
                    }
                    editor.startDragPoint = dragPoint
                }
            }
        }

        if isKeyPressed(actor, .EDITOR_SPAWN_CUBE) {
            // create entity 5 m in front of camera
            fmt.printfln("Spawn cube")

            entity, _ := create_entity(&gameState.engine)
            entity.asset = gameState.engine.render_state.cube_asset

            look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
                        glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
            look_vector := glsl.normalize_vec3(look_mat[2].xyz) * -1
            
            entity.pos = editor.editorCamera_pos + look_vector * 5
        }
    }

}






render_editor :: proc (gameState: ^GameState) {
    editor := &gameState.editor
    // UI stuff
    // Lines and axis for cube and resize things






    if gameState.editor.editorEnabled {
        gl.Disable(gl.CULL_FACE)
        // gl.Enable(gl.CULL_FACE)
        // gl.Disable(gl.DEPTH_TEST)
        gl.Enable(gl.DEPTH_TEST)

        wireframe_color: vec3 = {1,0.2,0.2}
        
        for i in 0..<len(editor.selectedObjects) {
            id := editor.selectedObjects[i]
            entity := get_entity(&gameState.engine, cast(u32)id)
            if !valid_entity(&gameState.engine, entity) {
                continue
            }

            scale := entity.scale + vec3{0.01,0.01,0.01}
            
            render_cube(&gameState.engine, entity.pos, scale, wireframe_color)
        }



        // @TODO Don't use OpenGL specifics here. We want to use Vulkan.
        gl.Disable(gl.CULL_FACE)
        gl.Disable(gl.DEPTH_TEST)

        crosshair_color: [4]f32 = { 0.1, 0.9, 0.1, 1 }
        w : f32 = cast(f32)gameState.engine.render_state.width
        h : f32 = cast(f32)gameState.engine.render_state.height
        crosshair_size : f32 = 4

        render_rect(&gameState.engine, w/2 - crosshair_size/2, h/2 - crosshair_size/2, crosshair_size, crosshair_size, crosshair_color)


    }



}





ray_sphere_intersection :: proc(
    origin: vec3,
    direction: vec3, // Must be normalized
    center: vec3,
    radius: f32,
) -> (hit: bool, distance: f32) {
    // min_distance : f32 = 2.0 / 0.25 // make this a parameter if we have more use cases for this function
    // max_distance : f32 = 10.0 / 0.25

    // // Closest point on ray
    // t := glsl.dot(center - origin, direction)

    // // filter out close objects, for example the player/editor entity where the ray is coming from
    // if t < min_distance {
    //     return false
    // }
    // if t > max_distance {
    //     return false
    // }

    // closest := origin + direction * t
    // distance_sq := glsl.dot(center - closest, center - closest)

    // if distance_sq > radius * radius {
    //     return false
    // }
    // return true
    oc := center - origin

    t := glsl.dot(oc, direction)

    if t < 0 {
        return false, 0
    }

    closest := origin + direction * t
    distance_sq := glsl.dot(center - closest, center - closest)

    if distance_sq > radius * radius {
        return false, 0
    }

    thc_sq := radius * radius - distance_sq
    thc := glsl.sqrt(thc_sq)

    return true, t - thc
}

ray_plane_intersection :: proc(
    origin: vec3,
    direction: vec3,
    plane_point: vec3,
    plane_normal: vec3,
) -> (hit: bool, position: vec3) {
    denom := glsl.dot(direction, plane_normal)

    if abs(denom) < 0.0001 {
        return false, {}
    }

    t := glsl.dot(plane_point - origin, plane_normal) / denom

    if t < 0 {
        return false, {}
    }

    return true, origin + direction * t
}
