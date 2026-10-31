
package central

import "core:fmt"

import "core:math/linalg/glsl"

Editor_Tool :: enum {
    SELECT,
    MOVE,
    SCALE,
    ROTATE
}

Editor_Event_Type :: enum {
    SELECT_OBJECT,
    DESELECT_OBJECT,
    MOVE_OBJECT,
    SCALE_OBJECT,
    CHANGE_TOOl,
}

Editor_Event_Data :: struct {
    object: int,
    previous_dataPoint: vec3,
}

Editor_Event :: struct {
    eventType: Editor_Event_Type,
    previous_tool: Editor_Tool,
    affectedObjects: [dynamic]Editor_Event_Data,
}

Editor_State :: struct {
    editorEnabled: bool,

    tool: Editor_Tool,
    
    selectedObjects: [dynamic]int,

    eventHistory: [dynamic]Editor_Event,

    editorCamera_pos: vec3,
    editorCamera_rot: vec3,

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
    } else if isKeyPressed(actor, .EDITOR_TOOL1) {
        editor.tool = .MOVE
    } else if isKeyPressed(actor, .EDITOR_TOOL2) {
        editor.tool = .SCALE
    }

    editor.editorCamera_rot = gameState.engine.render_state.camera_rotation
    editor.editorCamera_pos = gameState.engine.render_state.camera_position

    if gameState.editor.editorEnabled {

        
        if isKeyPressed(actor, .PRIMARY_ACTION) {
            // do stuff based on tool
        }
        if isKeyPressed(actor, .EDITOR_SPAWN_CUBE) {
            // create entity 5 m in front of camera

            fmt.printfln("Spawn cube")


            entity, _ := create_entity(&gameState.engine)
            entity.asset = gameState.engine.render_state.cube_asset

            look_mat := glsl.mat4Rotate(vec3{0,1,0}, editor.editorCamera_rot.y) *
                        glsl.mat4Rotate(vec3{1,0,0}, editor.editorCamera_rot.x)
            look_vector := glsl.normalize_vec3(look_mat[2].xyz)
            
            // fmt.println("Stuff",look_vector)
            entity.pos = editor.editorCamera_pos + look_vector * -5
            // entity.pos = { 5, 0, 5 }
        }
    }


    // UI stuff

    // Lines and axis for cube and resize things

}






render_editor :: proc () {

    // UI stuff

    // Lines and axis for cube and resize things

}




