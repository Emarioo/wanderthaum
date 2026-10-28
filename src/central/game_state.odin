package central

import "core:time"
// import "core:math"
// import "core:math/linalg"
import "core:math/linalg"

import "./util"

GameState :: struct {
    engine: EngineState,

    player_index: u32,
}
