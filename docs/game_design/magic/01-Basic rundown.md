
# Overview of Magic System

***Magic stems from the practitioner's desire to affect the world.***

- move entities
- create entities
- change properties

## Catalysts

Magic requires magical energy.
A player with an empty inventory has no magical energy.
Catalysts contain energy.

Primitive catalysts are raw magical crystals and metals.
Refined catalysts are staffs and wands that incorporate crystals and metals.

Catalysts have the following properties:

- **Energy Stored** is the currently stored energy in the catalyst.
    
- **Energy Capacity** is the maximum amount of stored energy. (excess energy is lost)

- **Energy Generation** is the amount of stored energy passively added every second.

Different values for the properties create limits for the magic. Cooldown, range, power, complexity.

## Spells

Spells define what a catalyst shall do with the energy.

Spells have the following properties:

- **Energy Usage** is the energy consumed every second during casting.
- **Cast Time** is the time it takes to prime or cast the spell, your player cannot perform any other action. You can cancel the spell at anytime.
- **Cast Cooldown** is the time until you have to wait to cast the spell again.

Cancelling a spell will not restore consumed energy.

The spell will be cancelled if the stored energy is to low. Specifically this condition `cancel = catalyst.energy_stored < spell.energy_usage * tick_timestep` (tick_timestep is 0.0167 since the game is updated 60 times per second).

Note that you may have 90% of the energy you need and will therefore consume that energy but then the last milliseconds of the cast time you run out of energy and some particle affects and sound to indicate that the spell cancelled. You may have 95% energy and because the energy generation is high and the cast time is long that is enough to create the missing energy you needed.

## Catalysts, Spells and Energy Philosophy

Energy generation on catalysts are high to create responsive spells that can be used often rather then once every 30 seconds.

The world, monsters, terrain, items, loot needs to be balanced with the high frequency casting in mind. To prevent the magic system from being overpowered.

Complex spells such as summoning monsters require a lot of energy. A catalyst with high energy capacity or generation would let you cast such spells.

# Random thoughts

The magic system isn't exactly inventing something new but it is well established, well thought out, and works well in a game (fun, moderate complexity, challenging for those who seek it)

To practise magic, you require a catalyst. As with any skill, it can be improved through practice.
There is no artificial level holding you back. New players can therefore demonstrate magical talent exceeding expectations.


Some catalysts are more efficient at certain categories of magic (fire, movement) and as higher limits (range, power, less cooldown). **Are these specific properties? Fire Energy Generation...?**


To keep the magic system engaging and useful the energy generation is quite high. This means you can
throw fire very 1-2 seconds. Not 5 at once and then 1 every 1 minute because of the high capacity.
This means balancing the power of the fire and the frequency of monsters and burnable things.
Otherwise it could be to overpowered.


Some spells may be special and has 30 second cooldowns because of low energy generation but they are quite
powerful if so. (summoning entities for example). Otherwise you could summon 120 monsters in 2 minutes (if cooldown was 1 second).
If you manage to create a catalyst with insane energy generation then we say "Well done, have fun spawning many monsters" we
hope our optimizations can keep up with the players' ambitions.

Complex magic like summoning entities require high capacity which most crystals don't have, a staff is needed.

Catalyst and magic energy is useless on it's own. Spells and catalysts are needed to affect the world.

If a spell's casting time isn't infinite then a tooltip shows `energy_per_second * casting_time`.
```yaml
Energy Usage:  120 E/s (44 E)
Cast Time:     0.2 s
Cast Cooldown: 1.0 s
```

When cancelling a spell energy is lost. This gives the player another area in which they can improve their magic skills. When casting you see energy being consumed each tick, this is satisfying especially if we give it a subtle sound. Restoring the energy on cancellation makes little since since energy has already been consumed.
