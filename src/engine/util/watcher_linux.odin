package util

import "core:os"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:mem"
import "core:thread"
import "core:sync"
import "core:strings"
import "base:runtime"

import "core:sys/linux"
import "core:sys/posix"

// @TODO Use IN_ONLYDIR
// @TODO Handle IN_IGNORED

INOTIFY_DEFAULT_EVENT_MASK : linux.Inotify_Event_Mask : { linux.Inotify_Event_Bits.CREATE, linux.Inotify_Event_Bits.DELETE, linux.Inotify_Event_Bits.DELETE_SELF , linux.Inotify_Event_Bits.MODIFY , linux.Inotify_Event_Bits.MOVE_SELF , linux.Inotify_Event_Bits.MOVED_FROM , linux.Inotify_Event_Bits.MOVED_TO }

_watcher_init :: proc (watcher: ^Watcher) -> bool {
    // @TODO Check if we already have inotify instance

    inotify_fd, err := linux.inotify_init()
    if inotify_fd < 0 {
        fmt.printfln("_watcher_init: inotify_init: %v", err)
        return false
    }
    watcher.inotify_instance = cast(i32)inotify_fd

    _watcher_add_path_recursive(watcher, watcher.root)

    return true
}

_watcher_add_path_recursive :: proc (watcher: ^Watcher, path: string) {
    root_wd, err := linux.inotify_add_watch(cast(linux.Fd)watcher.inotify_instance, strings.unsafe_string_to_cstring(path), INOTIFY_DEFAULT_EVENT_MASK)
    if err != .NONE {
        fmt.printfln("_watcher_init: inotify_init: %v", err)
        return
    }

    watcher.watches[cast(i32)root_wd] = strings.cut_clone(path, len(watcher.root)+1)

    dir := posix.opendir(strings.unsafe_string_to_cstring(path))
    if (dir == nil) {
        return
    }

    entry: ^posix.dirent
    for {
        entry = posix.readdir(dir)
        if entry == nil {
            break
        }
        name := strings.string_from_null_terminated_ptr(transmute([^]u8)&entry.d_name, cast(int)entry.d_reclen - 19)
        if (name == "." || name == "..") {
            continue
        }

        fullpath := strings.concatenate({path, "/", name})

        st: linux.Stat;
        if (linux.stat(strings.unsafe_string_to_cstring(fullpath), &st) == .NONE && linux.S_ISDIR(st.mode)) {
            _watcher_add_path_recursive(watcher, fullpath);
        }
    }

    posix.closedir(dir);
}


_watcher_thread_main :: proc (thread: ^thread.Thread) {
    watcher: ^Watcher = cast(^Watcher)thread.data
    buffer := make([]u8, 20 * (size_of(linux.Inotify_Event) + 500))

    for {
        res: bool
        bytes, err := linux.read(cast(linux.Fd)watcher.inotify_instance, buffer)
        if bytes < 0 {
            fmt.printfln("_watcher_thread_main: read: error %v", err)
            break
        }

        if bytes == 0 {
            fmt.printfln("_watcher_thread_main: read: zero bytes? %v", err)
            break
        }


        sync.mutex_lock(&watcher.events_mutex)
        
        offset: int
        
        events: ^[dynamic]WatchEvent
        if watcher.use_events_0 {
            events = &watcher.events_0
        } else {
            events = &watcher.events_1
        }
        event: WatchEvent
        for offset < bytes {
            info := cast(^linux.Inotify_Event) mem.ptr_offset(raw_data(buffer), offset)
            offset += cast(int)size_of(linux.Inotify_Event) + cast(int)info.len
            filename := strings.string_from_null_terminated_ptr(transmute(^u8)&info.name, cast(int)info.len)

            dir := watcher.watches[cast(i32)info.wd]
            event.path = strings.join({dir, filename}, "/")

            skip: bool
            if .CREATE in info.mask {
                event.type = .ADDED
            } else if .DELETE in info.mask {
                event.type = .REMOVED
            } else if .MODIFY in info.mask {
                event.type = .MODIFIED
            } else if .DELETE_SELF in info.mask {
                skip = true
            } else if .MOVE_SELF in info.mask {
                skip = true
            } else if .MOVED_FROM in info.mask {
                skip = true
            } else if .MOVED_TO in info.mask {
                skip = true
            } else {
                skip = true
            }

            if (!skip) {
                for ev in events^ {
                    // if ev.type == event.type && ev.path == event.path {
                    if ev.path == event.path {
                        // if we had ADDED, then we also get MODIFIED from windows for some reason
                        // we want to normalize and skip duplicates
                        skip = true
                    }
                }
            }
            if !skip {
                append(events, event)
            }

        }

        sync.mutex_unlock(&watcher.events_mutex)
    }

    delete(buffer)

    linux.close(cast(linux.Fd)watcher.inotify_instance)
}

_watcher_cleanup :: proc (watcher: ^Watcher) {
    linux.close(cast(linux.Fd)watcher.inotify_instance)
    
    thread.join(watcher.thread)
    thread.destroy(watcher.thread)
    
    // Thread cleans itself up.
    // Unless it exited abnormally.
}
