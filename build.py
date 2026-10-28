#!/usr/bin/env python3

import os, sys, subprocess, shlex, platform, shutil, glob

import tools.build_core as build_core

REPO_ROOT = os.path.dirname(__file__)

def main():
    VERSION = "0.0.1"
    TARGET = f"{platform.system().lower()}-x86_64"

    options = build_core.Options(
        version = "0.0.1",
        release_path = f"{REPO_ROOT}/releases/wanderthaum-{VERSION}-{TARGET}",
        game_src = "src/central",
        project_name = "wanderthaum",
    )
    
    # options = build_core.Options(
    #     version = "0.0.1",
    #     release_path = f"{REPO_ROOT}/releases/vulkantest-{VERSION}-{TARGET}",
    #     game_src = "src/vulkantest",
    #     project_name = "vulkantest",
    # )



    if "hot" in sys.argv:
        options.hotreload = True

    if "run" in sys.argv:
        options.run = True

    if "package" in sys.argv:
        options.package = True

    if "distribute" in sys.argv:
        # @TODO Send distribution to test devs automatically through launcher with a network connection.
        #    Hotreload and so on.
        pass


    build_core.compile_game(options)

if __name__ == "__main__":
    main()