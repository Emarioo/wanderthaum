package central

import "core:time"
// import "core:math"
// import "core:math/linalg"
import "core:math/linalg"

import "./util"

GameState :: struct {
    engine: EngineState,
    editor: Editor_State,

    player_rot: vec3,

    player_id: EntityID,
    default_world_path: string,
}
