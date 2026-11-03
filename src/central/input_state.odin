
package central


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

Input_Action_State :: struct {
    value:   i32, // state of the action, usually 0 or 1 for key up or down. Or X/Y position for mouse. For controllers it is MININT/MAXINT which represent joystick range -1.0 .. 1.0, or 0.0 .. 1.0 for triggers.
    pressed: i32,
}

Input_Actor :: struct {
    actions: [Input_Action.MAX_COUNT]Input_Action_State,
    
    // actions we modify during tick and set next tick
    temp_actions: [Input_Action.MAX_COUNT]Input_Action_State,
}

Input_State :: struct {
    actors: [dynamic]Input_Actor,
}

isKeyPressed :: proc (actor: ^Input_Actor, action: Input_Action) -> bool {
    return actor.actions[action].pressed > 0
}

isKeyDown :: proc (actor: ^Input_Actor, action: Input_Action) -> bool {
    return actor.actions[action].value > 0
}

getScrolledY :: proc (actor: ^Input_Actor) -> int {
    return cast(int)actor.actions[Input_Action.SCROLL_Y].pressed
}