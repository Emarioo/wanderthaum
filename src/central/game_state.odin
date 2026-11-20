package central

import "core:time"
// import "core:math"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:sync"

import "../engine/util"
import "../engine"

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4
mat4 :: glsl.mat4

GameState :: struct {
    engineState: engine.EngineState,
    editor: Editor_State,
    keymap: engine.Input_KeyAction_Map,

    lastAutosaveTime: time.Time,
    autosaveEnabled: bool,

    default_world_path: string,

    // Per player data
    thirdPersonDistance: f32,
    lastPlayerCameraRot: vec3,
    player_id: engine.EntityID,

    worldManager: WorldManager,
}
