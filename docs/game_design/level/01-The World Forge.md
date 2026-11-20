
We want the game to stand out so we do not present the player with classic 2d menu, settings and world menus.

When you start the game for the first time you begin at *The World Forge*. It is a small scene where you can
create new worlds, add and join servers. Created worlds (including servers) appear as portals you can enter.
When you get close you are sucked in and start in the first area if it's your first time in that world, otherwise continue from where you were.

You go back to *The World Forge* by talking to NPCs if it's a small village or camp you are in. Big cities might have portals.

When you close and start the game again it will resume where you left off. If you were on a server then it will try to connect. If it fails
you will begin at *The World Forge*.

We still have a menu for settings, keybindings, and credits because you want to modify or look at those at any time.
Game may or may not pause when doing so.

Worlds differ in appearence depending on what they are. Worlds you own has a stable, grounded feeling. Servers have a glow. Servers that are offline might have a 
darker dormant shadow.


The plan is that players are in their own world forge and it is not shared. Perhaps you can see ghosts of others player that are in the
world forge if you are connected to the internet. We would need a server specifically for this that retransmits player locations.


We can add more feature into the world forge for dungeon settings or world template and mods and things.
But we begin with prototype and maybe we'll need to make large refactors later.

The world forge could change over time with more NPCs and buildings as you progress but i don't plan on having any progression except
the worlds. New game versions may add stuff. Maybe some special events. A test version of the game might come with a test world server you should join.

One aspect that could be important is giving *The World Forge* room for exploration. Add some game hints here and there, some cool lore or items to look at and
imagine what they are used for and how you make or find them in the game. We don't want world forge to feel out of place, irrelevant or annyoing. It should
not feel like a booring lobby even though that is what it's for.

# Questions

**How does headless server with no graphics come into play?** <br>
You run the executable with `wanderthaum.exe --headless --world <path>` and it will start a dedicated server.
You start the game with `wanderthaum.exe`. You go to the forge in *The World Forge* scene and add a new server with IP and PORT.
localhost and no port would use default port for the game.
It is now created in the scene and you can walk into the portal. You tell your friends to do the same but with your public IP.

**How does your character look like?** <br>
Customization spots in the world and the world forge seems good.
Not sure what kind of default clothes you have, i guess we randomize the character at first.
Or perhaps randomize a couple of themes so you don't get completely random clothes that don't match.

# Features to implement
- Multiplayer.
- Running multiple worlds at the same time during transition.
