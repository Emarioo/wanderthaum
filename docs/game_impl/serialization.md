

The game has save files which store the state of the world.

An empty save file has nothing in it. Players would in this case be spectators free floating.

The game creates new save files from a template. The template contains the static
terrain, shops, fences, and dungeons.

The save file is complete with all information about the world. We do not separate the static
data into it's own save file. This makes it easier to load. It also allows you
to create your own modded save files.

However, this means that game updates which implement new content won't be added to the existing save file.
To fix this we will compare current game version with the save file's game version and add in missing content.
This can get dicey but it should be solvable. I think its worthwhile the simplicity of one save file.

# The save file format

The format supports text and binary mode.


