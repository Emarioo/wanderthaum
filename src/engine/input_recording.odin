/*
    recording

    Slow inefficient layout for recorded data but
    I have to start somewhere.
*/

package engine;

Action :: struct {
    kind: i32,
    state: i32, // down, up, pressed
}

TickRecord :: struct {
    frame: u32,
    actions: [dynamic]Action,
    // All affects on the game
}

Recording :: struct {
    // we record user input

    frame_start: u32,
    tick_records: [dynamic]TickRecord,

    // With the same input we can achieve the same output.
    // difficult with multiplayer.
}

