
package central

import "core:fmt"

import "core:math/linalg/glsl"
import "core:math"

import gl "vendor:OpenGL"

Editor_Tool :: enum {
    SELECT,
    MOVE,
    SCALE,
    ROTATE,
    ASSET_PICKER,
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
    MOVE_OBJECT,
    SCALE_OBJECT,
    ROTATE_OBJECT,
    CHANGE_ASSET_OBJECT,
    CREATE_OBJECT,
    DELETE_OBJECT,
}

Editor_Event_Data :: struct {
    entityID: u64,
    // use union here
    previous_dataPoint: vec3,
    previous_asset: ^Asset,
}

Editor_Event :: struct {
    eventType: Editor_Event_Type,
    affectedObjects: [dynamic]Editor_Event_Data,
}

Editor_State :: struct {
    editorEnabled: bool,

    tool: Editor_Tool,
    axisMode: Editor_Axis_Mode,
    dragging: bool,

    averageObjectPos: vec3,
    origin_editorPos: vec3,
    true_startDragPoint: vec3,
    startDragPoint: vec3,
    
    selectedObjects: [dynamic]u64,

    eventHistory: [dynamic]Editor_Event,
    latestEvent: Editor_Event,
    eventHistoryIndex: int,

    editorCamera_pos: vec3,
    editorCamera_vel: vec3,
    editorCamera_rot: vec3,

    asset_index: int,
    asset_max: int,
    assetsToPick: [dynamic]^Asset,

}

begin_event :: proc (gameState: ^GameState, eventType: Editor_Event_Type) {
    editor := &gameState.editor
    editor.latestEvent.eventType = eventType
}
push_event_datapoint :: proc (gameState: ^GameState, entityID: u64, dataPoint: vec3) {
    editor := &gameState.editor
    event := &editor.latestEvent
    append(&event.affectedObjects, { entityID = entityID, previous_dataPoint = dataPoint })
}

push_event_asset :: proc (gameState: ^GameState, entityID: u64, asset: ^Asset) {
    editor := &gameState.editor
    event := &editor.latestEvent
    append(&event.affectedObjects, { entityID = entityID, previous_asset = asset })
}
push_event_empty :: proc (gameState: ^GameState, entityID: u64) {
    editor := &gameState.editor
    event := &editor.latestEvent
    append(&event.affectedObjects, { entityID = entityID })
}
end_event :: proc (gameState: ^GameState) {
    editor := &gameState.editor
    if len(editor.latestEvent.affectedObjects) > 0 {
        // @TODO Put a limit on undo history
        
        // If we undo-ed a bunch and then cause an event this will
        // clear future history that you could have redo-ed.
        for editor.eventHistoryIndex < len(editor.eventHistory) {
            delete(editor.eventHistory[len(editor.eventHistory)-1].affectedObjects)
            pop(&editor.eventHistory)
        }
        append(&editor.eventHistory, editor.latestEvent)
        editor.eventHistoryIndex = len(editor.eventHistory)
    }
    editor.latestEvent.affectedObjects = {}
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

    entity_count := 0
    pos: vec3
    for i in 0..<len(editor.selectedObjects) {
        id := editor.selectedObjects[i]
        entity := get_entity(&gameState.engine, cast(u32)id)
        // if !valid_entity(&gameState.engine, entity) {
        //     continue
        // }
        pos += entity.pos
        entity_count += 1
    }
    return pos / cast(f32)entity_count
}

tick_editor :: proc (gameState: ^GameState) {
    editor := &gameState.editor
    actor := &gameState.engine.inputState.actors[0]
    if isKeyPressed(actor, .EDITOR_TOGGLE) {
        // fmt.println("Toggle editor")
        end_event(gameState)
        editor.dragging = false
        gameState.editor.editorEnabled = !gameState.editor.editorEnabled

        if gameState.editor.editorEnabled {
            gameState.engine.render_state.camera_rotation = editor.editorCamera_rot
        } else {
            gameState.engine.render_state.camera_rotation = gameState.player_rot
        }
    }

    if isKeyPressed(actor, .EDITOR_TOOL0) {
        end_event(gameState)
        editor.tool = .SELECT
        editor.dragging = false
    } else if isKeyPressed(actor, .EDITOR_TOOL1) {
        end_event(gameState)
        editor.tool = .MOVE
        editor.dragging = false
        begin_event(gameState, .MOVE_OBJECT)
    } else if isKeyPressed(actor, .EDITOR_TOOL2) {
        end_event(gameState)
        editor.tool = .SCALE
        editor.dragging = false
        begin_event(gameState, .SCALE_OBJECT)
    } else if isKeyPressed(actor, .EDITOR_TOOL3) {
        end_event(gameState)
        editor.tool = .ROTATE
        editor.dragging = false
        begin_event(gameState, .ROTATE_OBJECT)
    } else if isKeyPressed(actor, .EDITOR_TOOL4) {
        end_event(gameState)
        editor.tool = .ASSET_PICKER
        editor.dragging = false
        begin_event(gameState, .CHANGE_ASSET_OBJECT)
        
        clear(&editor.assetsToPick)
        editor.asset_index = 0

        currentAsset: ^Asset = nil
        if len(editor.selectedObjects) > 0 {
            entity := get_entity(&gameState.engine, cast(u32)editor.selectedObjects[len(editor.selectedObjects)-1])
            currentAsset = entity.asset
        }

        index := 0
        for _, asset in gameState.engine.storage.assets_by_name {
            if asset.type != .MODEL {
                continue
            }
            append(&editor.assetsToPick, asset)
            if asset == currentAsset {
                editor.asset_index = index
            }
            index += 1
        }
        editor.asset_max = len(editor.assetsToPick)
        // fmt.println(editor.assetsToPick)
    } else if isKeyPressed(actor, .EDITOR_TOOL5) {
        end_event(gameState)
        // editor.dragging = false
        
        begin_event(gameState, .CREATE_OBJECT)

        for i in 0..<len(editor.selectedObjects) {
            id := editor.selectedObjects[i]
            entity := get_entity(&gameState.engine, cast(u32)id)
            if !valid_entity(&gameState.engine, entity) {
                continue
            }
            
            new_entity, new_entity_id := create_entity(&gameState.engine)
            copy_entity_data(&gameState.engine, entity, new_entity)

            push_event_empty(gameState, cast(u64)new_entity_id)
        }

        end_event(gameState)
    }

    if gameState.editor.editorEnabled {

        look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
                    glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
        look_vector_normal := glsl.normalize_vec3(look_mat[2].xyz) * -1
        // @TODO If cursor isn't locked then we calculate look vector differently
        
        if isKeyPressed(actor, .EDITOR_DELETE) {
            end_event(gameState)
            
            begin_event(gameState, .DELETE_OBJECT)

            for i in 0..<len(editor.selectedObjects) {
                id := editor.selectedObjects[i]
                entity := get_entity(&gameState.engine, cast(u32)id)
                if !valid_entity(&gameState.engine, entity) {
                    continue
                }
                kill_entity(&gameState.engine, entity)
                push_event_empty(gameState, cast(u64)id)
            }
            clear(&editor.selectedObjects)

            end_event(gameState)
        }

        if editor.tool == .SELECT {
            if isKeyDown(actor, .PRIMARY_ACTION) {
                if !isKeyDown(actor, .EDITOR_APPEND_SELECT) && isKeyPressed(actor, .PRIMARY_ACTION) {
                    clear(&editor.selectedObjects)
                }

                any_selection := false

                for ei in 0..<gameState.engine.entities_count {
                    entityID := cast(u64)ei // @TODO Use proper ID

                    entity := get_entity(&gameState.engine, cast(u32)entityID)
                    if !valid_entity(&gameState.engine, entity) {
                        continue
                    }
                    // @TODO Select bounding box of the entity, sphere is simple for now.
                    // hit, distance := ray_sphere_intersection(editor.editorCamera_pos, look_vector_normal, entity.pos, 0.5)
                    
                    min_pos, max_pos := get_min_max_point(entity)
                    hit, distance := ray_aabb_intersection(editor.editorCamera_pos, look_vector_normal, min_pos, max_pos)

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
                            append(&editor.selectedObjects, entityID)
                        }
                        any_selection = true
                    }
                }
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
            // @TODO When scrolling and axis mode is camera increase, decrease the distance from the camera.

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
                    end_event(gameState)
                    editor.dragging = false
                }
                valid, dragPoint := calculate_move_pos(gameState)
                if valid {
                    move_diff := dragPoint - editor.startDragPoint

                    if (len(editor.latestEvent.affectedObjects) == 0 && glsl.length(move_diff) > 0.001) {
                        for i in 0..<len(editor.selectedObjects) {
                            id := editor.selectedObjects[i]
                            entity := get_entity(&gameState.engine, cast(u32)id)
                            if !valid_entity(&gameState.engine, entity) {
                                continue
                            }
                            push_event_datapoint(gameState, id, entity.pos)
                        }
                    }

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
                editor.true_startDragPoint = editor.startDragPoint
                if valid {
                    editor.dragging = true
                }
            }

            updateAxisMode(editor, actor)

            if editor.dragging {
                if !isKeyDown(actor, .PRIMARY_ACTION) {
                    end_event(gameState)
                    editor.dragging = false

                    // @TODO Add event
                }
                valid, dragPoint := calculate_move_pos(gameState)
                if valid {
                    move_diff := dragPoint - editor.startDragPoint

                    if (len(editor.latestEvent.affectedObjects) == 0 && glsl.length(move_diff) > 0.001) {
                        for i in 0..<len(editor.selectedObjects) {
                            id := editor.selectedObjects[i]
                            entity := get_entity(&gameState.engine, cast(u32)id)
                            if !valid_entity(&gameState.engine, entity) {
                                continue
                            }
                            push_event_datapoint(gameState, id, entity.scale)
                        }
                    }

                    if editor.true_startDragPoint.x < editor.averageObjectPos.x {
                        move_diff.x *= -1
                    }
                    if editor.true_startDragPoint.y < editor.averageObjectPos.y {
                        move_diff.y *= -1
                    }
                    if editor.true_startDragPoint.z < editor.averageObjectPos.z {
                        move_diff.z *= -1
                    }

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
        
        if editor.tool == .ASSET_PICKER {
            scroll := getScrolledY(actor)

            if (len(editor.latestEvent.affectedObjects) == 0 && scroll != 0) {
                for i in 0..<len(editor.selectedObjects) {
                    id := editor.selectedObjects[i]
                    entity := get_entity(&gameState.engine, cast(u32)id)
                    if !valid_entity(&gameState.engine, entity) {
                        continue
                    }
                    push_event_asset(gameState, id, entity.asset)
                }
            }

            editor.asset_index = (editor.asset_index + scroll) %% editor.asset_max
            asset := editor.assetsToPick[editor.asset_index]
            for ei in editor.selectedObjects {
                entity := get_entity(&gameState.engine, cast(u32)ei)
                if !valid_entity(&gameState.engine, entity) {
                    continue
                }
                entity.asset = asset
            }
        }

        if isKeyPressed(actor, .EDITOR_SPAWN_CUBE) {
            end_event(gameState)
            // create entity 5 m in front of camera
            // fmt.printfln("Spawn cube")

            begin_event(gameState, .CREATE_OBJECT)
            
            entity, entity_index := create_entity(&gameState.engine)
            entity.asset = gameState.engine.render_state.cube_asset

            look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
                        glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
            look_vector := glsl.normalize_vec3(look_mat[2].xyz) * -1
            
            entity.pos = editor.editorCamera_pos + look_vector * 5

            push_event_empty(gameState, cast(u64)entity_index)

            end_event(gameState)
        }
        
        if isKeyPressed(actor, .EDITOR_UNDO) {
            end_event(gameState)

            if editor.eventHistoryIndex > 0 {
                editor.eventHistoryIndex -= 1
                lastEvent := &editor.eventHistory[editor.eventHistoryIndex]
                for i in 0..<len(lastEvent.affectedObjects) {
                    point := &lastEvent.affectedObjects[i]
                    entity := get_entity(&gameState.engine, cast(u32)point.entityID)
                    #partial switch lastEvent.eventType {
                        case .MOVE_OBJECT:
                            tmp := entity.pos
                            entity.pos = point.previous_dataPoint
                            point.previous_dataPoint = tmp
                        case .SCALE_OBJECT:
                            tmp := entity.scale
                            entity.scale = point.previous_dataPoint
                            point.previous_dataPoint = tmp
                        case .CHANGE_ASSET_OBJECT:
                            tmp := entity.asset
                            entity.asset = point.previous_asset
                            point.previous_asset = tmp
                        case .CREATE_OBJECT:
                            entity.killed = true
                        case .DELETE_OBJECT:
                            entity.killed = false
                    }
                }
            }
        }

        if isKeyPressed(actor, .EDITOR_REDO) {
            end_event(gameState)

            if editor.eventHistoryIndex < len(editor.eventHistory) {
                lastEvent := &editor.eventHistory[editor.eventHistoryIndex]
                for i in 0..<len(lastEvent.affectedObjects) {
                    point := &lastEvent.affectedObjects[i]
                    entity := get_entity(&gameState.engine, cast(u32)point.entityID)
                    #partial switch lastEvent.eventType {
                        case .MOVE_OBJECT:
                            tmp := entity.pos
                            entity.pos = point.previous_dataPoint
                            point.previous_dataPoint = tmp
                        case .SCALE_OBJECT:
                            tmp := entity.scale
                            entity.scale = point.previous_dataPoint
                            point.previous_dataPoint = tmp
                        case .CHANGE_ASSET_OBJECT:
                            tmp := entity.asset
                            entity.asset = point.previous_asset
                            point.previous_asset = tmp
                        case .CREATE_OBJECT:
                            entity.killed = false
                        case .DELETE_OBJECT:
                            entity.killed = true
                    }
                }
                editor.eventHistoryIndex += 1
            }
        }
    }

}






render_editor :: proc (gameState: ^GameState) {
    editor := &gameState.editor
    // UI stuff
    // Lines and axis for cube and resize things






    if gameState.editor.editorEnabled {
        // gl.Disable(gl.CULL_FACE)
        gl.Enable(gl.CULL_FACE)
        // gl.Disable(gl.DEPTH_TEST)
        gl.Enable(gl.DEPTH_TEST)

        wireframe_color: vec3 = {1,0.2,0.2}
        
        for i in 0..<len(editor.selectedObjects) {
            id := editor.selectedObjects[i]
            entity := get_entity(&gameState.engine, cast(u32)id)
            if !valid_entity(&gameState.engine, entity) {
                continue
            }

            pos, scale := get_pos_scale(entity)
            scale += vec3{0.01,0.01,0.01}
            render_cube(&gameState.engine, pos, scale, wireframe_color)
        }

        
        // bounding_box_color: vec3 = {0.2,0.67,0.1}

        // for i in 0..<gameState.engine.entities_count {
        //     entity := get_entity(&gameState.engine, cast(u32)i)
        //     if !valid_entity(&gameState.engine, entity) {
        //         continue
        //     }

        //     pos, scale := get_pos_scale(entity)
        //     scale += vec3{0.01,0.01,0.01}
        //     render_cube(&gameState.engine, pos, scale, bounding_box_color)
        // }


        // @TODO Don't use OpenGL specifics here. We want to use Vulkan.
        gl.Disable(gl.CULL_FACE)
        gl.Disable(gl.DEPTH_TEST)


        // Render asset choices


        crosshair_color: [4]f32 = { 0.1, 0.9, 0.1, 1 }
        w : f32 = cast(f32)gameState.engine.render_state.width
        h : f32 = cast(f32)gameState.engine.render_state.height
        crosshair_size : f32 = 4

        render_rect(&gameState.engine, w/2 - crosshair_size/2, h/2 - crosshair_size/2, crosshair_size, crosshair_size, crosshair_color)


    }



}


get_min_max_point :: proc (entity: ^Entity) -> (vec3, vec3) {
    min_pos : vec3
    max_pos : vec3 
    if entity.asset != nil && entity.asset.model != nil {
        min_pos = entity.pos + entity.asset.model.min_point * entity.scale
        max_pos = entity.pos + entity.asset.model.max_point * entity.scale
    } else {
        min_pos = entity.pos - entity.scale/2
        max_pos = entity.pos + entity.scale/2
    }
    return min_pos, max_pos
}

get_pos_scale :: proc (entity: ^Entity) -> (vec3, vec3) {
    min_pos, max_pos := get_min_max_point(entity)
    pos   := (max_pos + min_pos)/2
    scale := max_pos - min_pos
    return pos, scale
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

ray_aabb_intersection :: proc(
    origin: vec3,
    direction: vec3, // Must be normalized
    box_min: vec3,
    box_max: vec3,
) -> (hit: bool, distance: f32) {
    t_min : f32 = 0.0
    t_max := max(f32)

    for axis in 0..<3 {
        if direction[axis] == 0 {
            // Ray is parallel to this pair of planes.
            if origin[axis] < box_min[axis] || origin[axis] > box_max[axis] {
                return false, 0
            }
            continue
        }

        t1 := (box_min[axis] - origin[axis]) / direction[axis]
        t2 := (box_max[axis] - origin[axis]) / direction[axis]

        t_near := min(t1, t2)
        t_far  := max(t1, t2)

        t_min = max(t_min, t_near)
        t_max = min(t_max, t_far)

        if t_min > t_max {
            return false, 0
        }
    }

    return true, t_min
}
