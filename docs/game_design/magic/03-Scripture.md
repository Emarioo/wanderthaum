
# Writing spell

A spell can contain blocks of events that are executed on events.

```bash
#
#  Begin casting (once)
#
incipere
    # actions...
finis

#
#  Continuous casting (per tick)
#
permanere
    # actions...
finis

#
#  Completed casting (once)
#
perficere
    # actions...
finis 
```

## Predefined objects

Text can refer to predefined objects

|Name|Type|Description|
|-|-|-|
|incantator|Entity|The entity of the caster, lets you read and write the caster's properties|
|catalyst|Catalyst|Object of the caster's catalyst used when casting the spell, lets you read the catalysts properties|
|scriptura|Spell|Object of the caster's catalyst used when casting the spell, lets you read the catalysts properties|
|pulsus|float|"Small time quantum, pulse of the universe", timestep is 0.0167|


```c
struct Entity {
    pos: vec3
    vel: vec3
    rot: vec3
    acc: vec3
}
struct Catalyst {
    energy: float
    capacity: float
    generation: float
}
struct Spell {
    usage: float
    cast_time: float
    cooldown: float
}
```

**NOTE:** We may remove *scriptura*. the energy usage, cast_time, cooldown is determined by the text and by referencing those values in the text we can get a paradox.

## Predefined functions

|Signature|Description|
|-|-|
|closest_entity(origin: vec3, min_distance: float, max_distance: float) -> Entity|Get closest entity|
|closest_non_human(origin: vec3, min_distance: float, max_distance: float) -> Entity|Get closest non human entity (excludes NPCs)|
|closest_creature(origin: vec3, min_distance: float, max_distance: float) -> Entity|Get closest living entity (projectiles, rocks, items)|
|entities_in_sphere(origin: vec3, min_distance: float, max_distance: float) -> Entity[]|Get list of entities in sphere|

normalize, length functions...

## Spell content

math notation for +* vectors

for entity loop...

## Spell energy usage

Computed upfront from spell text?

Does usage change depending on how many entities we for loop
over?

## Spell failure
Might be bad but it could be interesting if a spell failure
could corrupt the spell. Adding some characters, removing some,
adding some # hints about where the spell broke (if you try to `incantator = closest_entity()`)
