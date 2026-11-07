/*

    Entry point of the game.

        There are three ways to run it
           wanderthaum.exe (normal client game mode)
           wanderthaum.exe --server --port 8789 (port is optional, there is a default)
           wanderthaum.exe --test TEST_FILE (test file describe world, simulated inputs and other environmental things)

*/

package game_head

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import "base:runtime"

import "../engine/driver"

main :: proc () {

    exe_dir, err123       := os.get_executable_directory(context.allocator)
    if err123 != os.General_Error.None {
        fmt.println("Could not get executable directory ", err123)
    }

    was_allocation: bool
    exe_dir, was_allocation = strings.replace_all(exe_dir, "\\", "/")

    err: runtime.Allocator_Error
    gamecode_lib_path : string 
    when ODIN_OS == .Linux {
        gamecode_lib_path, err  = filepath.join([]string{ exe_dir, "/libgamecode.so" })
    } else {
        gamecode_lib_path, err     = filepath.join([]string{ exe_dir, "/gamecode.dll" })
    }

    // @TODO If we want to compile statically then this needs to change a bit.
    driver.start(gamecode_lib_path)

}
