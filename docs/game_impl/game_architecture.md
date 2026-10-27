
Python as the build system.

```bash
./build.py
```

This will
1. Compile driver and game code
2. Generate runtime assets from source assets (export from .kra, .blend files)
3. Package game into `releases/orbus-0.0.1-linux-x86_64`


# Repository structure
```
releases
    orbus-0.0.1-linux-x86_64
        ...
art                         - Raw art sources for the game
assets                      - Exported models, textures, for the game
docs 
lib/libs/extern             - Third-party code.
src                         - Source code
    driver
        main.odin           - Entry point for driver
    engine
        input.odin
        rendering.odin
    orbus
        game_entry.odin     - Entry point for game (exports "driver_event" called by driver)
        terrain.odin
tools                       - Build system scripts
    fetch_dependencies.py
build.py                    - Main build script
```

# Distributed structure

```
odingame-0.0.1-linux-x86_64
    orbus.exe
    glfw3.dll
    stb_image.dll
    cgltf.dll
    settings.txt
    assets
        models
            tree.glb
        shaders
            object.glsl
        textures
            splash.png
    mods
        minimap
            minimap.dll
            settings.txt
            assets
                textures
                    waypoint.png
    data
        world.data
```

# Game architecture

Game executable has two components. The driver as an executable and the game code as a shared library.

The driver loads the game code at runtime and reloads it when a file modification is detected.
This allows for changing code such as player speed or enemy pathfinding while the game is running and reloading it.

For a smooth experience we create 4 threads. RENDER, INPUT, TICK, and WORKER. We use GLFW which can block on window resize
events (because of Windows API). On window resizing we block the input thread where all the others can render and update the game.
