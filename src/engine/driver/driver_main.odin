/*
    TODO: Hotreloading
    TODO: Rendering rectangles
    TODO: Record and store user input
*/

package driver

import "core:fmt"
import "core:dynlib"
import "core:os"
import "core:path/filepath"
import "core:time"
import "core:strings"
import "core:sync"
import "core:thread"
import "base:runtime"

ENABLE_HOTRELOAD :: #config(ENABLE_HOTRELOAD, true)


start :: proc (fresh_lib_path: string) {
    // fmt.println("Hello, sailor!")
    ok                     : bool
    
    exe_dir, err123       := os.get_executable_directory(context.allocator)
    if err123 != os.General_Error.None {
        fmt.printfln("Could not get executable directory %v", err123)
    }

    was_allocation: bool
    exe_dir, was_allocation = strings.replace_all(exe_dir, "\\", "/")

    // Load dynamic libraries game_code dll depends on so that they don't get unloaded
    // when game code is unloaded. We could move this to engine or game code if we wish.
    libraries: [dynamic]string

    temp_lib_path  : string
    tempfirst_lib_path  : string
    when ODIN_OS == .Linux {
        temp_lib_path, err   = filepath.join([]string{ exe_dir, "/lib_gamecode.so"  })
        tempfirst_lib_path, err  = filepath.join([]string{ exe_dir, "/lib_fgamecode.so"  })
        
        append(&libraries, "libglfw.so.3")
        // @TODO Load vulkan
        // permanent_library_load("libGL.so")
        // permanent_library_load("glfw")
        // permanent_library_load("GL")
    } else {
        err: runtime.Allocator_Error
        temp_lib_path, err      = filepath.join([]string{ exe_dir, "/_gamecode.dll"  })
        tempfirst_lib_path, err = filepath.join([]string{ exe_dir, "/_fgamecode.dll"  })

        append(&libraries, "glfw3.dll")
        append(&libraries, "OpenGL32.dll")
        // @TODO Load vulkan
        // append(&libraries, "vulkan-1.dll")
    }

    for lib in libraries {
        permanent_library_load(lib)
    }

    last_modification_time : time.Time
    last_timestamp_check   : time.Time
    file_info              : os.File_Info
    library                : dynlib.Library
    address                : rawptr
    error                  : os.Error
    data: DriverData
    event_data: EventData
    data.running = true
    data.thread_main = thread_main
    data.game_directory = exe_dir

    if ENABLE_HOTRELOAD {
        copy_file(fresh_lib_path, tempfirst_lib_path)

        library, ok = dynlib.load_library(tempfirst_lib_path)
        if !ok {
            fmt.println(library)
            fmt.eprintln(dynlib.last_error())
            fmt.println("Could not load library", tempfirst_lib_path)
            os.exit(1)
        }
        
        address, ok = dynlib.symbol_address(library, "driver_event")
        if !ok {
            fmt.println("Could not find 'driver_event' in", tempfirst_lib_path)
            os.exit(1)
        }
        data.driver_event = cast(proc(event: EventKind, event_data: ^EventData, data: ^DriverData)) address


        file_info, error = os.stat(fresh_lib_path, context.allocator)
        assert(error == os.General_Error.None)
        last_modification_time = file_info.modification_time
        last_timestamp_check   = time.now()
        os.file_info_delete(file_info, context.allocator)
    }


    // we need to load glfw3.dll and assimp.dll dynamically so they don't unload
    // when we unload the game.dll

    data.driver_event(EventKind.EVENT_LOAD, &event_data, &data)
    data.driver_event(EventKind.EVENT_START, &event_data, &data)

    
    {
        thr := thread.create(data.thread_main)
        thr.data = &data
        thr.user_index = cast(int)ThreadType.INPUT
        append(&data.threads, thr)
        thread.start(thr)
    }
    {
        thr := thread.create(data.thread_main)
        thr.data = &data
        thr.user_index = cast(int)ThreadType.RENDER_0
        append(&data.threads, thr)
        thread.start(thr)
    }
    {
        thr := thread.create(data.thread_main)
        thr.data = &data
        thr.user_index = cast(int)ThreadType.WORKER_0
        append(&data.threads, thr)
        thread.start(thr)
    }

    keep_game_dll := true
    {
        // Watcher (with its threads) has to be started in non-reloadable code which is the driver.
        // Network threads will also need this.
        // game_state := cast(^game.GameState) event_data.user_data
        // util.watcher_init(&game_state.engine.art_watcher, "art")

        // If we don't want this then one option is to keep the first game_code.dll, on reload watcher and networking threads will
        // keep running in the old game code since it won't be unloaded and functions invalidated. For our driver event rendering, update code
        // we call functions from the new game code.
        // This can get a little messy and buggy at runtime bug hot reload is only for developers anyway and won't happen at runtime?
        // With this approach we don't have to have game specific code in the driver.
    }

    for data.running {

        // Detect reload of dll
        if ENABLE_HOTRELOAD {
            now := time.now()
            reload_ms :: 500 * time.Millisecond
            // Check if dynamic library was rebuilt every 500ms
            if time.diff(last_timestamp_check, now) > reload_ms {
                last_timestamp_check = now
                file_info, error = os.stat(fresh_lib_path, context.allocator)
                defer os.file_info_delete(file_info, context.allocator)

                if error == os.General_Error.None && time.time_to_unix_nano(file_info.modification_time) > time.time_to_unix_nano(last_modification_time) {

                    // Send signal to other thread saying DO NOT SEND TICK EVENT AND STALL
                    // Wait until all threads are stalling

                    sync.atomic_store(&data.reload_requested, true)

                    sync.mutex_lock(&data.mutex)
                    for sync.atomic_load(&data.parked_threads) < sync.atomic_load(&data.active_threads) {
                        sync.cond_wait(&data.cond, &data.mutex)
                    }
                    sync.mutex_unlock(&data.mutex)

                    last_modification_time = file_info.modification_time
                    
                    data.driver_event(EventKind.EVENT_UNLOAD, &event_data, &data)

                    if !keep_game_dll {
                        ok = dynlib.unload_library(library)
                        if !ok {
                            fmt.println("Could not unload library", temp_lib_path)
                            os.exit(1)
                        }
                    } else {
                        // Only keep first game dll (it creates file watchers threads which will keep executing valid code since we don't invalidate the old dll)
                        // For network threads we need some other solution since they may be created after the first dll was replaced.
                        // Subseque
                        keep_game_dll = false
                    }

                    copy_file(fresh_lib_path, temp_lib_path)
                    
                    library, ok = dynlib.load_library(temp_lib_path)
                    if !ok {
                        // Reloaded too fast? try again.
                        time.sleep(1000 * time.Millisecond)
                        library, ok = dynlib.load_library(temp_lib_path)
                        if !ok {
                            fmt.println("Could not load library", temp_lib_path)
                            os.exit(1)
                        }
                    }
                    
                    address, ok = dynlib.symbol_address(library, "driver_event")
                    if !ok {
                        fmt.println("Could not find 'driver_event' in", temp_lib_path)
                        os.exit(1)
                    }
                    data.driver_event = cast(proc(event: EventKind, event_data: ^EventData, data: ^DriverData)) address

                    data.driver_event(EventKind.EVENT_LOAD, &event_data, &data)

                    // Send signal to other thread saying STOP STALL, KEEP SENDING TICK EVENTS
                    sync.atomic_store(&data.reload_requested, false)
                    sync.cond_broadcast(&data.cond)
                } else {
                    // game code dll is not newer or doesn't exist
                }
            }
        }
        
        // Tick update
        data.driver_event(EventKind.EVENT_TICK, &event_data, &data)
    }

    data.driver_event(EventKind.EVENT_STOP, &event_data, &data)
    data.driver_event(EventKind.EVENT_UNLOAD,&event_data, &data)
}

thread_main :: proc (thread: ^thread.Thread) {
    data := cast(^DriverData)thread.data

    event_data: EventData
    event_data.user_index = thread.user_index
    event_data.user_data  = data.user_data

    sync.atomic_add(&data.active_threads, 1)

    for data.running {

        // Look for STOP SENDING TICK EVENT AND STALL
        // if this signal is active we wait here until it's not anymore

        if sync.atomic_load(&data.reload_requested) {
            sync.mutex_lock(&data.mutex)
            sync.atomic_add(&data.parked_threads, 1)

            if sync.atomic_load(&data.parked_threads) == sync.atomic_load(&data.active_threads) {
                sync.cond_signal(&data.cond)
            }

            for sync.atomic_load(&data.reload_requested) {
                sync.cond_wait(&data.cond, &data.mutex)
            }

            sync.atomic_sub(&data.parked_threads, 1)
            sync.mutex_unlock(&data.mutex)
            continue
        }

        data.driver_event(EventKind.EVENT_TICK, &event_data, data)
    }

    sync.atomic_sub(&data.active_threads, 1)
}

copy_file :: proc(src_path, dst_path: string) -> bool {
    src, ok := os.open(src_path, os.O_RDONLY)
    if ok != os.General_Error.None {
        fmt.printfln("Failed to open source file %v", src_path)
        return false
    }
    defer os.close(src)

    dst: ^os.File
    dst, ok = os.open(dst_path, os.O_CREATE | os.O_TRUNC | os.O_WRONLY, os.Permissions_All)
    if ok != os.General_Error.None {
        fmt.printfln("Failed to create destination file %v", dst_path)
        return false
    }
    defer os.close(dst)

    buf: [4096]u8
    for {
        bytes_read, read_ok := os.read(src, buf[:])
        if bytes_read == 0 || read_ok != os.General_Error.None {
            break
        }

        bytes_written, write_ok := os.write(dst, buf[:bytes_read])
        if write_ok != os.General_Error.None {
            fmt.printfln("Write failed %v", dst_path)
            return false
        }
    }

    return true
}