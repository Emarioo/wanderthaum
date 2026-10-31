/*
    This file is responsible for saving and loading worlds.

    File extension is typically .wth (wanderthaum)
*/

package central

import "core:fmt"
import "core:os"
import "base:runtime"
import "base:intrinsics"
import "core:c"

World_Header :: struct {
    magic:          [4]u8, // "WTHB" (binary) or "WTHT" (text)
    format_version: u32,
    game_version:   u32,
}

World_Operation :: enum {
    SAVE_WORLD,
    LOAD_WORLD,
}

// saveAsText : bool = true

// set_save_world_text_mode :: proc (enabled: bool) {
//     saveAsText = enabled
// }

sync_world :: proc (path: string, operation: World_Operation, data: rawptr) -> bool {

    err: os.Error
    file: ^os.File
    readBytes: int
    writtenBytes: int

    // @TODO Before saving we should make a copy so we don't start overriding and crash

    if operation == .LOAD_WORLD {
        header: World_Header
        readBytes: int
        
        file, err = os.open(path, {.Read})
        if err != nil {
            fmt.println("Could not open ", path)
            return false
        }

        readBytes, err = os.read(file, (transmute([^]byte)(&header))[:size_of(header)])
        
        if err != nil {
            fmt.println("Could not read ", path)
            return false
        }
        
        if readBytes != size_of(header) {
            fmt.println("Could not read whole world header (", readBytes,"/", size_of(header),"), ", path)
            return false
        }

        fmt.println(header)


        // @TODO When loading world we need to check if game version is different from current
        //   if so we should try to transform it into current version.
        //   Not sure if we do this here.

    } else if operation == .SAVE_WORLD {
        header: World_Header
        
        // file, err = os.open(path, {.Read, .Write, .Create})
        file, err = os.open(path, {.Write, .Create})
        if err != nil {
            fmt.println("Could not open ", path)
            return false
        }

        // Try to read header if it exists
        // readBytes, err = os.read(file, (transmute([^]byte)(&header))[:size_of(header)])
        // if err != nil {
        //     fmt.println("Could not read ", path)
        //     return false
        // }

        // if readBytes != size_of(header) {
        //     // Not valid
        //     // Can't perform efficient saving where we only save things that updated.
        // }
        
        header.magic = "WTHB"
        header.format_version = 1
        header.game_version = 1

        os.write(file, (transmute([^]byte)(&header))[:size_of(header)])

        fmt.println(header)
    }

    err = os.close(file)
    
    return true
}
