
Game architecture tries to be modular. Swap out systems, easier to optimize, reuse systems in other projects.

In a game there are core systems we need.
- Resource System (textures, models, sound, terrain)
- Game Main Driver (dll hotreload)
- 

# Resource System
Static assets. We load them from disc, do some processing into 


# Game Main Driver
Hot reload dynmamic libraries.
When reloading game dll we need to preserve global data from game itself but also libraries like glfw, glad, cgltf we need to preserve global data.

# Game State System

Save the state of the game. Close the game. And load it at that exact frame. All entities, terrain, chests, momentum, input is restored.

Rewing the state of the game. Jump of a rock, you fall through the ground. Go back a couple of frames, step forward to the moment it happens and investigate the entities position, velocity, collision data
to figure out the problem.




# Asset system

Reload on change


## Efficient and stutter-free asset processing.

In the game we have a list of assets (models, shaders, textures).

At startup we register new assets from a path to the file. player model, ui shader, texture for background in main menu. Assets that we always want loaded.

In gameplay when joining a world, rentering a biome we register relevant assets that we don't have and unload assets we don't need anymore.

If the assets are updated on disc, then we will automatically reload the asset.

To use the assets they need to be converted from file format (.glb, .png, .glsl) to objects in the GPU. This requires processing (File IO, CPU computation on worker thread, GPU calls on render thread).

During processing we will allocate memory and gpu objects for the data we get from the file format. Some of this memory and some GPU objects may be intermediate and temporary and not needed for the final asset. For example when we reload a model it will have two mesh objects. One for the current that we are rendering and one for the one that we are processing. Without old mesh object any entity that uses the asset would not have any mesh object to render while it's processing.

To achieve efficient processing without stutters we need to keep old gpu objects for some time and reuse memory and buffers.



**Resources**
https://www.songho.ca/opengl/gl_pbo.html

## From testing

Allocating a buffer object (texture or vertex or indices) with nullptr as data takes some time but doing it with data to copy over takes more time.




# Driver, engine, game packages and main, render, input, worker threads

The systems and packages are neatly packaged having implementation details and a clean API for us.

For example.
The driver package looks like this:


```

main :: proc () {
    // start in main function of your executable

    driver: DriverData

    driver_init(&driver, )


    driver_start(&driver)

}

```
