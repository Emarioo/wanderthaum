
// AUTO GENERATED, DO NOT MODIFY, IT WILL BE OVERWRITTEN
package spell;

import "core:math/linalg/glsl"

vec3 :: glsl.vec3

Entity :: struct {
    pos: vec3,
    vel: vec3,
    rot: vec3,
    acc: vec3,
}
Catalyst :: struct {
    energy: f32,
    capacity: f32,
    generation: f32,
}

SpellContext :: struct {
    caster: ^Entity,
    catalyst: ^Catalyst,
    closest_entity : proc (origin: vec3, min_distance: f32, max_distance: f32) -> ^Entity,
    entities_in_sphere : proc (origin: vec3, min_distance: f32, max_distance: f32) -> []^Entity,
}

@(export) on_begin :: proc(ctx: ^SpellContext) {
    incantator := ctx.caster
    catalyst := ctx.catalyst
    pulsus :: 1.0/60.0
    closest_entity := ctx.closest_entity
    entities_in_sphere := ctx.entities_in_sphere

    incantator.acc += vec3({0,1,0})
    }
