
# Overview of Making Spells

Spells can be made by players in **Spell Table**.

Or maybe they can be made and modified on the fly? (would be neat, we'll see)


## Nodes in a spell

    Spell has nodes
    you connect nodes
    nodes can have an affect
        apply acceleration/velocity on entity
        set thing on fire
        give entitiy a buff/debuff
        summon creature, rock
    it can take mouse direction as input
    it can add vectors, matrix multiplication
    dot product, cross product?
    sleep, timeout nodes
    repeat, loop, branch, if, then

Two types of spells, can be combined.

A spell can affect world at cast time.
It can affect world after cast time.

A fireball spell would do nothing while player casts the spell, then once done fireball is made and velocity is set and it moves.

**Rock Projectile**
```
def on_cast_done():
    pos = caster.pos + caster.lookdir*3.5
    rot = vec3(0,0,0)
    vel = caster.lookdir * 50
    summon_rock(pos, rot, vel)
```


**Force Field**
```
def on_casting():
    pos = caster.pos
    dist = 4
    ents = fetch_entities_in_sphere(pos, dist)
    for ent in ents:
        caster.acc += caster.vel - ent.vel - (ent.pos - caster.pos) / timestep
```

# Random Thoughts

Spell making can be a little scuffed.
For example spawning a rock at the players position without adding
player's look vector and some distance away from the player the rock
would spawn on the player's feat and possibly hurt them instantly.

This is why you can find spells in chests, so you don't have to make spells yourself.
