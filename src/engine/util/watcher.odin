/*
    Naive implementation of platform independent file system watcher.

    It can miss events with the wrong timing.

    Good enough for our purposes.


    Some limiations:
    - Does not consider symlinks
    - Does not consider mounting
    - 
*/

package util

import "core:os"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:mem"
import "core:thread"
import "core:sync"
import "base:runtime"

WatchEventType :: enum {
    ADDED,
    REMOVED,
    MODIFIED,
    RENAMED,
}

WatchEvent :: struct {
    type: WatchEventType,
    path: string,
    old_path: string, // only valid if renamed
}

Watcher :: struct {
    thread: ^thread.Thread,
    root: string,

    events_mutex: sync.Mutex,
    use_events_0: bool,
    events_0: [dynamic]WatchEvent,
    events_1: [dynamic]WatchEvent,

    // Windows
    notification_handle: u64,
    directory_handle: u64,

    // Linux
    inotify_instance: i32, 
    watches: map[i32]string,

}

// @TODO Add recursive flag if needed. Personally I always want recursive.
// @TODO Provide callback parameter if user doesn't want to poll?
watcher_init :: proc (watcher: ^Watcher, root_path: string) -> bool {
    watcher.thread = thread.create(_watcher_thread_main)
    watcher.thread.data = watcher
    watcher.root = root_path // clone?

    res := _watcher_init(watcher)
    if !res {
        return false
    }

    thread.start(watcher.thread)
    return true
}

watcher_poll :: proc (watcher: ^Watcher) -> []WatchEvent {
    sync.mutex_lock(&watcher.events_mutex)
    events: ^[dynamic]WatchEvent
    if watcher.use_events_0 {
        events = &watcher.events_0
        for i in 0..<len(watcher.events_1) {
            delete(watcher.events_1[i].path)
            delete(watcher.events_1[i].old_path)
        }
        clear(&watcher.events_1)
    } else {
        events = &watcher.events_1
        for i in 0..<len(watcher.events_0) {
            delete(watcher.events_0[i].path)
            delete(watcher.events_0[i].old_path)
        }
        clear(&watcher.events_0)
    }
    watcher.use_events_0 = !watcher.use_events_0
    sync.mutex_unlock(&watcher.events_mutex)

    return (events^)[:]
}

watcher_cleanup :: proc (watcher: ^Watcher) {
    _watcher_cleanup(watcher)
}
