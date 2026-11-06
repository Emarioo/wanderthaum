
package engine

import "vendor:glfw"

Input_Generic_Action :: u32 // game code defines an enum Input_Action or similar

PHYSICAL_KEY_LEFT_MOUSE :: glfw.KEY_LAST + 1
PHYSICAL_KEY_RIGHT_MOUSE :: glfw.KEY_LAST + 2
PHYSICAL_KEY_MIDDLE_MOUSE :: glfw.KEY_LAST + 3

PHYSICAL_KEY_POINTER_X :: glfw.KEY_LAST + 9
PHYSICAL_KEY_POINTER_Y :: glfw.KEY_LAST + 10
PHYSICAL_KEY_SCROLLED_X :: glfw.KEY_LAST + 11
PHYSICAL_KEY_SCROLLED_Y :: glfw.KEY_LAST + 12


Input_KeyAction_Map_Entry :: struct {
    key: u32, // in future we may support multiple keys pressed down at once.
    shift: bool,
    control: bool,
    action: Input_Generic_Action,
}

// The key map tells the input system (GLFW) how
// to convert a key into an action.
// Current system does not support arbitrarily changing the entries.
// You have to create a completely new keymap and replace it.
// Then if no other actors use the keymap you can delete it.
Input_KeyAction_Map :: struct {
    entries: [dynamic]Input_KeyAction_Map_Entry,
}

Input_Action_State :: struct {
    value:   i32, // state of the action, usually 0 or 1 for key up or down. Or X/Y position for mouse. For controllers it is MININT/MAXINT which represent joystick range -1.0 .. 1.0, or 0.0 .. 1.0 for triggers.
    pressed: i32,
}

Input_Actor :: struct {
    keymap: ^Input_KeyAction_Map,
    actions: [dynamic]Input_Action_State,
    
    // actions we modify during tick and set next tick
    temp_actions: [dynamic]Input_Action_State,
}

Input_State :: struct {
    actors: [dynamic]Input_Actor,

    defaultKeymap: ^Input_KeyAction_Map,
}

isKeyPressed :: proc (actor: ^Input_Actor, action: Input_Generic_Action) -> bool {
    return actor.actions[action].pressed > 0
}

isKeyDown :: proc (actor: ^Input_Actor, action: Input_Generic_Action) -> bool {
    return actor.actions[action].value > 0
}

getPressedValue :: proc (actor: ^Input_Actor, action: Input_Generic_Action) -> int {
    return cast(int)actor.actions[action].pressed
}

set_default_keymap :: proc (state: ^EngineState, keymap: ^Input_KeyAction_Map) {
    state.inputState.defaultKeymap = keymap
}

create_input_actor :: proc (state: ^EngineState, keymap: ^Input_KeyAction_Map = nil) {
    actualKeymap := keymap
    if keymap == nil {
        actualKeymap = state.inputState.defaultKeymap
    }
    append(&state.inputState.actors, { keymap = actualKeymap })

    actor := &state.inputState.actors[len(state.inputState.actors)-1]

    resize(&actor.actions, len(actor.keymap.entries))
    resize(&actor.temp_actions, len(actor.keymap.entries))
}
