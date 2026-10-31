#!/usr/bin/env python3

import os, sys, subprocess, shlex, platform, shutil, glob, dataclasses, time


REPO_ROOT = os.path.dirname(os.path.dirname(__file__))

@dataclasses.dataclass
class Options:
    version:      str
    release_path: str
    game_src:     str
    game_head:     str
    project_name: str
    target:       str  = f"{platform.system().lower()}-x86_64"
    hotreload:    bool = False
    run:          bool = False
    use_shared_libraries: bool = True
    package:      bool = False



def apply_exe_extension(options: Options, path: str):
    dirname = os.path.dirname(path)
    basename = os.path.basename(path)
    if basename.endswith(".exe") or basename.endswith(".out"):
        basename = os.path.splitext(basename)[0]

    if "windows" in options.target:
        return os.path.join(dirname, basename + ".exe")
    elif "linux" in options.target:
        return os.path.join(dirname, basename)
    else:
        assert False

def apply_dll_extension(options: Options, path: str):
    dirname = os.path.dirname(path)
    basename = os.path.basename(path)
    if basename.endswith(".dll"):
        basename = os.path.splitext(basename)[0]
    if basename.startswith("lib") and basename.endswith(".so"):
        basename = os.path.splitext(basename[3:])[0]
    if basename.endswith(".so"):
        basename = os.path.splitext(basename)[0]

    if "windows" in options.target:
        return os.path.join(dirname, basename + ".dll")
    elif "linux" in options.target:
        return os.path.join(dirname, "lib" + basename + ".so")
    else:
        assert False

def apply_lib_extension(options: Options, path: str):
    dirname = os.path.dirname(path)
    basename = os.path.basename(path)
    if basename.endswith(".lib"):
        basename = os.path.splitext(basename)[0]
    if basename.startswith("lib") and basename.endswith(".a"):
        basename = os.path.splitext(basename[3:])[0]
    if basename.endswith(".a"):
        basename = os.path.splitext(basename)[0]

    if "windows" in options.target:
        return os.path.join(dirname, basename + ".lib")
    elif "linux" in options.target:
        return os.path.join(dirname, "lib" + basename + ".a")
    else:
        assert False

def game_is_running(name):
    os = platform.system().lower()
    if os == "windows":
        proc = subprocess.run(["tasklist"], text=True,stdout=subprocess.PIPE)
        if proc.returncode:
            print(proc.stdout)
            exit(1)
        return name in proc.stdout
    elif platform.system() == "linux":
        proc = subprocess.run(["ps", "-A"], text=True,stdout=subprocess.PIPE)
        if proc.returncode:
            print(proc.stdout)
            exit(1)
        return name in proc.stdout

def compile_game(options: Options):    
    if game_is_running(options.project_name) and not options.hotreload:
        print("Game is running, hot reloading instead")
        options.hotreload = True


    # Ensure intermediate directory exists (where we dump object files)
    # don't need 'int' at the moment
    # os.makedirs(f"{REPO_ROOT}/int", exist_ok=True)

    # Ensure release directory exists
    os.makedirs(options.release_path, exist_ok=True)

    odin_path = get_odin_root()


    game_exe = apply_exe_extension(options, f"{options.release_path}/{options.project_name}")
    gamecode_dll = apply_dll_extension(options, f"{options.release_path}/gamecode")

    base_odin_flags = f"-debug -o:none"
    driver_odin_flags = f"{base_odin_flags}"
    game_odin_flags = f"{base_odin_flags} -define:GLFW_SHARED=true"

    OS = platform.system().lower()

    if OS == "windows":
        if not options.hotreload:
            for f in glob.glob(f"{options.release_path}/*.pdb"):
                os.remove(f)

        # The program freezes when i use this for some reason. Players don't want Windows to start a console so
        # we will need it in the end.
        # driver_odin_flags += " -subsystem:windows"
        timestamp = int(time.time()) % (60*60*24)
        # game_odin_flags += f" -pdb-name:game_code-{timestamp}.pdb"
        game_odin_flags += f" -pdb-name:{options.release_path}/gamecode-{timestamp}.pdb"

        if not options.hotreload:
            glfw_path = f"{odin_path}vendor\\glfw\\lib\\glfw3.dll"
            try:
                shutil.copy(glfw_path, f"{options.release_path}/glfw3.dll")
            except:
                    pass # we assume dll is in use
        # cgltf_path_dll = glob.glob(f"{ROOT}/lib/cgltf/{OS}/shared/cgltf.dll")
        # if len(cgltf_path_dll) > 0:
        #     cgltf_path = cgltf_path_dll[0]
        #     cgltf_path_pdb = glob.glob(f"{ROOT}/lib/cgltf/{OS}/shared/cgltf.pdb")[0]
        #     try:
        #         shutil.copy(cgltf_path, f"bin/{os.path.basename(cgltf_path)}")
        #         shutil.copy(cgltf_path_pdb, f"bin/{os.path.basename(cgltf_path_pdb)}")
        #     except:
        #         pass # we assume dll is in use
        # try:
        #     shutil.copy(glfw_path, "bin/glfw3.dll")
        # except:
        #         pass # we assume dll is in use
    # else:
    #     # take glfw from system path?
    #     # glfw_path = f"{odin_path}vendor/glfw/lib/glfw3.so"
    #     assimp_path = f"{LIB_DIR}/libassimp.so"
    #     try:
    #         shutil.copy(assimp_path, f"bin/{os.path.basename(assimp_path)}.6")
    #     except:
    #         pass # we assume dll is in use
        # try:
        #     shutil.copy(glfw_path, "bin/libglfw3.so")
        # except:
        #         pass # we assume dll is in use

    if not options.hotreload:
        # @TODO If we switch between package and not then we want to wipe the release folder to ensure no
        #    symlinks or other trash stays behind.
        if not options.package:
            # Instead of copying all assets to release folder we make symlinks. This way we won't accidently
            # edit temporary shaders in the release folder. The single source of truth will be odingame/assets.
            if OS == "windows":
                tmp = '\\'
                dst = f"{options.release_path.replace('/',tmp)}\\assets"
                if not os.path.exists(dst):
                    os.system(f"mklink /J {dst} {REPO_ROOT.replace('/',tmp)}\\assets")
            else:
                dst = f"{options.release_path}/assets"
                if not os.path.exists(dst):
                    os.symlink(f"{REPO_ROOT}/assets", dst, target_is_directory=True)
        else:
            # @TODO Clean the release directory and package into zip file, based on target (.tar.gz for linux, .zip for windows)
            #    Always clean directory to get rid of garbage.
            print("@TODO Implement build.py package")

    # run(f"odin build src/game {game_odin_flags}  -build-mode:dynamic -out:{gamecode_dll}")

    run(f"odin build {options.game_src} {game_odin_flags}  -build-mode:dynamic -out:{gamecode_dll}")

    if options.hotreload:
        print("FOR HOTRELOADING TO WORK YOU MUST COPY libglfw.so.3 to release directory (where game shared library and executable is)")

    if not options.hotreload:
        # run(f"odin {'run' if options.run else 'build'} src/driver {'-keep-executable' if options.run else ''} {driver_odin_flags} -out:{game_exe}")
        run(f"odin build {options.game_head} {driver_odin_flags} -out:{game_exe}")
        if options.run:
            if OS == "windows":
                tmp = '\\'
                run(f"{game_exe.replace('/',tmp)}")
            else:
                run(f"{game_exe}")


def get_odin_root():
    cmd = "odin root"
    proc = subprocess.run(shlex.split(cmd), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        print("Failed:", cmd)
        print(proc.stdout)
        exit(1)
    return proc.stdout

def run(cmd):
    # print(cmd)
    if platform.system() == "Linux":
        res = os.system(cmd) >> 8
    else:
        res = os.system(cmd)
    if res != 0:
        print(f"failed: {cmd}")
        exit(1)
