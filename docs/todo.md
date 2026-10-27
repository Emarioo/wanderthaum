
Things to do in the project.
Some things are derived from the roadmap others are nice things to have during development.

- Saving loading world
- Optimizations, multit-hreading
- Lighting rendering
- Terrain rendering, efficient memory usage, cpu usage
- Hotreloading textures, shaders, models
- World editing, moving models
- Deterministic entity updates
- Recording user input (keys, mouse)
- Save and load game state
- Step game ticks, back and forth.
- Custom physics (since we want to step back game ticks and physics?)
- Proximity chat, sound engine in general
- All systems working with multiplayer

Developer experience is important.
Ease of adding models, changing world, terrain, textures, shaders.
Moving and creating entities when game updates are paused





- [ ] Remove unnecessary code and docs from wander/orbis/thaum project.






# Unsorted


# Important
- [ ] Loading *Iuno* model stutters the game. It takes 50ms (including console prints). Solutions are: load a few meshes in each frame instead of all meshes. Use opengl pixel, storage buffer objects, give gpu memory mapped data. This would be asynchronous instead of serial glBufferData and glTexImage2D calls?

- [ ] Add tracy profiler

# Game world
- [ ] Decide on beginner experience, procedural terrain or a pre-made town?
- [ ] Protoype world in Krita. buildings, blocks, monsters areas. nothing detailed.
- [ ] Model the prototype in blender. we care about speed not quality.



# Engine stuff
- [ ] Entity movement from AI pathfinding and User input, how to connect them.
- [ ] Network architecture? server verifies. If a person is messing with the connection (hacking) we don't care how buggy their client gets.
- [ ] Modding support and architecture. Even if the game won't have mods it's good to modularize the game to keep things neat.

# Improve develop experience
- [ ] Game remembers window pos,size and monitor it's own. (i usally want it on second monitor but it always appears on my coding monitor, annoying)
- [ ] Process to auto export blender models. build.py exports through **Blender CLI** if blender files are new. For this we need to declare which blender files we have in the game, and where in assets they should go. Maybe just `art/models/X -> assets/models/X`. In art we may have sub folders for the models though. There is also how to deal with mods, can they auto export?.
- [ ] When reloading game code we unload dll, load dll. this happens on main thread and we block other threads from running. since loading dll is File IO this can cause visible stutter. To fix this the driver should ask a worker thread to load new dll, this won't affect main or render thread -> no stutter. Driver knows when worker is done and starts calling the **driver_event** from new dll. Then asks worker to unload the previous dll, once again this won't block other threads. The driver still needs to sync all threads and block them from executing during the switch. As long as we don't have any heavy assets processing going on a worker this will be fine. The main and render thread runs above 60hz so we won't notice stutter, workers don't have such a restriction. Each worker tick could take 500ms if there is a lot of work to be done. (if we ensure tasks can be done incrementally then even workers won't cause stutters during the switch)

# Done
- [x] Key in the game to hotreload code. (instead of typing build.py hot in a terminal)








# Real time editing in blender and export to game
https://lotusspring.substack.com/p/how-i-wrote-the-fastest-blender-exporter