

- [ ] Auto export blender models to .glb. This is done when the game is in focus and a change in blender file is detected. If game is unfocused and gains focus then we should export assets for the accumulated changes.
    We don't want to export everytime you save the blender file. Blender might not like it very much, things can get wierd? We can try at least? Question is what to export in the scene as well. A blender scene
    may have multiple models.

- [ ] Lighting. Not as important because we add some noise to otherwise flat-colored cubes which make them easier to differentiate.


- [ ] Vulkan: Textures on models

- [ ] Vulkan: Depth stencil buffer

- [ ] Vulkan: Wireframes

- [ ] Vulkan: When starting with vulkan backend, reloading code, switching to opengl backend we crash.

- [ ] Make a little scene with blocks. Scene is a camp with some shops, a flat area where players spawn. A path outwards to more areas.

- [ ] Sound

- [ ] Multiplayer

- [ ] Think about where we can utilize multithreading

- [ ] We have some string memory leaks here and there.

- [x] Entity storage

- [x] Entity collision (AABB)

- [x] Separate player camera and editor camera. Player should be its own entity that you play as. Then you can hop into editor mode which is a separate camera.

- [x] Editor undo creating and deletion. This should also mean proper datastructure for entities and hash map to lookup ids instead of indices. (reason we use random IDs and not indices or numbered IDs is because multiplayer, anyone can generate an entity and it doesn't not have to go through a centralized ID manager)

- [x] Editor redo.

- [x] Editor duplicate entities (mostly needed for cubes and walls)



# BELOW IS OLD STUFF


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