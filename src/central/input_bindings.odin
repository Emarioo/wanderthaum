package central

import "../engine"
import "vendor:glfw"

Input_Action :: enum {
    POINTER_X, // mouse position
    POINTER_Y,

    PRIMARY_ACTION,   // left mouse
    SECONDARY_ACTION, // right mouse
    THIRD_ACTION,     // middle mouse
    
    SCROLL_X,         // middle mouse
    SCROLL_Y,         // middle mouse

    MOVE_FORWARD,
    MOVE_LEFT,
    MOVE_RIGHT,
    MOVE_BACKWARD,
    MOVE_UP,
    MOVE_DOWN,
    MOVE_SPRINT,

    RELOAD_ASSETS,
    SAVE_WORLD,
    LOAD_WORLD,

    EDITOR_TOGGLE,
    EDITOR_TOOL0,
    EDITOR_TOOL1,
    EDITOR_TOOL2,
    EDITOR_TOOL3,
    EDITOR_TOOL4,
    EDITOR_TOOL5,
    EDITOR_SPAWN_CUBE,
    EDITOR_UNDO,
    EDITOR_REDO,
    EDITOR_APPEND_SELECT,
    EDITOR_DELETE,

    EDITOR_PLANE_XY,
    EDITOR_PLANE_XZ,
    EDITOR_PLANE_YZ,
    EDITOR_AXIS_X,
    EDITOR_AXIS_Y,
    EDITOR_AXIS_Z,
    EDITOR_AXIS_CAMERA,
    
    ESCAPE,

    MAX_COUNT,
}

isKeyPressed :: proc (actor: ^engine.Input_Actor, action: Input_Action) -> bool {
    return engine.isKeyPressed(actor, cast(engine.Input_Generic_Action)action)
}

isKeyDown :: proc (actor: ^engine.Input_Actor, action: Input_Action) -> bool {
    return engine.isKeyDown(actor, cast(engine.Input_Generic_Action)action)
}

getScrolledY :: proc (actor: ^engine.Input_Actor) -> int {
    return engine.getPressedValue(actor, cast(engine.Input_Generic_Action)Input_Action.SCROLL_Y)
}

generate_default_bindings :: proc (keymap: ^engine.Input_KeyAction_Map) {

    clear(&keymap.entries)

    append(&keymap.entries, {key = glfw.KEY_W,               action = cast(engine.Input_Generic_Action)Input_Action.MOVE_FORWARD})
    append(&keymap.entries, {key = glfw.KEY_A,               action = cast(engine.Input_Generic_Action)Input_Action.MOVE_LEFT})
    append(&keymap.entries, {key = glfw.KEY_S,               action = cast(engine.Input_Generic_Action)Input_Action.MOVE_BACKWARD})
    append(&keymap.entries, {key = glfw.KEY_D,               action = cast(engine.Input_Generic_Action)Input_Action.MOVE_RIGHT})
    append(&keymap.entries, {key = glfw.KEY_SPACE,           action = cast(engine.Input_Generic_Action)Input_Action.MOVE_UP})
    append(&keymap.entries, {key = glfw.KEY_C,               action = cast(engine.Input_Generic_Action)Input_Action.MOVE_DOWN})
    append(&keymap.entries, {key = glfw.KEY_LEFT_SHIFT,      action = cast(engine.Input_Generic_Action)Input_Action.MOVE_SPRINT})

    append(&keymap.entries, {key = glfw.KEY_F1,              action = cast(engine.Input_Generic_Action)Input_Action.RELOAD_ASSETS})
    append(&keymap.entries, {key = glfw.KEY_F2,              action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOGGLE})
    append(&keymap.entries, {key = glfw.KEY_F3,              action = cast(engine.Input_Generic_Action)Input_Action.SAVE_WORLD})
    append(&keymap.entries, {key = glfw.KEY_F4,              action = cast(engine.Input_Generic_Action)Input_Action.LOAD_WORLD})

    append(&keymap.entries, {key = glfw.KEY_1,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOOL0})
    append(&keymap.entries, {key = glfw.KEY_2,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOOL1})
    append(&keymap.entries, {key = glfw.KEY_3,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOOL2})
    append(&keymap.entries, {key = glfw.KEY_4,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOOL3})
    append(&keymap.entries, {key = glfw.KEY_5,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOOL4})
    append(&keymap.entries, {key = glfw.KEY_6,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_TOOL5})
    append(&keymap.entries, {key = glfw.KEY_K,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_SPAWN_CUBE})

    append(&keymap.entries, {key = glfw.KEY_Z, shift = true, action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_REDO})
    append(&keymap.entries, {key = glfw.KEY_Z,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_UNDO})

    append(&keymap.entries, {key = glfw.KEY_X, shift = true, action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_PLANE_YZ})
    append(&keymap.entries, {key = glfw.KEY_X,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_AXIS_X})

    append(&keymap.entries, {key = glfw.KEY_Y, shift = true, action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_PLANE_XZ})
    append(&keymap.entries, {key = glfw.KEY_Y,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_AXIS_Y})

    append(&keymap.entries, {key = glfw.KEY_Z, shift = true, action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_PLANE_XY})
    append(&keymap.entries, {key = glfw.KEY_Z,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_AXIS_Z})

    append(&keymap.entries, {key = glfw.KEY_V,               action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_AXIS_CAMERA})

    append(&keymap.entries, {key = glfw.KEY_LEFT_SHIFT,      action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_APPEND_SELECT})
    append(&keymap.entries, {key = glfw.KEY_DELETE,          action = cast(engine.Input_Generic_Action)Input_Action.EDITOR_DELETE})

    
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_LEFT_MOUSE,   action = cast(engine.Input_Generic_Action)Input_Action.PRIMARY_ACTION})
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_RIGHT_MOUSE,  action = cast(engine.Input_Generic_Action)Input_Action.SECONDARY_ACTION})
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_MIDDLE_MOUSE, action = cast(engine.Input_Generic_Action)Input_Action.THIRD_ACTION})
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_POINTER_X,    action = cast(engine.Input_Generic_Action)Input_Action.POINTER_X})
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_POINTER_Y,    action = cast(engine.Input_Generic_Action)Input_Action.POINTER_Y})
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_SCROLLED_X,   action = cast(engine.Input_Generic_Action)Input_Action.SCROLL_X})
    append(&keymap.entries, {key = engine.PHYSICAL_KEY_SCROLLED_Y,   action = cast(engine.Input_Generic_Action)Input_Action.SCROLL_Y})
}
