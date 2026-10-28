package util

import "core:os"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:strings"
import "core:mem"
import "core:thread"
import "core:sync"
import "base:runtime"

import "core:sys/windows"



_watcher_init :: proc (watcher: ^Watcher) -> bool {
    root_path: cstring16 = windows.utf8_to_wstring(watcher.root)
   
    dir_handle := windows.CreateFileW(root_path, windows.FILE_LIST_DIRECTORY, windows.FILE_SHARE_DELETE|windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE, nil, windows.OPEN_EXISTING, windows.FILE_FLAG_BACKUP_SEMANTICS, nil)
    if dir_handle == windows.INVALID_HANDLE_VALUE {
        error := windows.GetLastError()
        fmt.printfln("ERROR CreateFileW, %v", error)
        return false
    }
    
    flags : u32 = windows.FILE_NOTIFY_CHANGE_LAST_WRITE | windows.FILE_NOTIFY_CHANGE_FILE_NAME | windows.FILE_NOTIFY_CHANGE_DIR_NAME
    handle := windows.FindFirstChangeNotificationW(transmute(^u16)root_path, true, flags)
    if handle == windows.INVALID_HANDLE_VALUE {
        error := windows.GetLastError()
        windows.CloseHandle(dir_handle)
        fmt.printfln("ERROR FindFirstChangeNotificationW, %v", error)
        return false
    }

    watcher.directory_handle = transmute(u64)dir_handle
    watcher.notification_handle = transmute(u64)handle
    return true
}


_watcher_thread_main :: proc (thread: ^thread.Thread) {
    watcher: ^Watcher = cast(^Watcher)thread.data
    buffer := make([]u8, 20 * (size_of(windows.FILE_NOTIFY_INFORMATION) + 500))

    for {
        res: bool
        waitStatus := windows.WaitForSingleObject(transmute(windows.HANDLE)watcher.notification_handle, windows.INFINITE)

        if waitStatus != windows.WAIT_OBJECT_0 {
            fmt.printfln("WaitForSingleObject, status not WAIT_OBJECT_0")
            break
        }

        bytes : u32 = 0
        res = cast(bool)windows.ReadDirectoryChangesW(transmute(windows.HANDLE)watcher.directory_handle, raw_data(buffer), cast(u32)len(buffer), true, windows.FILE_NOTIFY_CHANGE_LAST_WRITE |windows.FILE_NOTIFY_CHANGE_FILE_NAME | windows.FILE_NOTIFY_CHANGE_DIR_NAME, &bytes, nil, nil)

        if !res {
            // Directory was deleted or something?
            // fmt.printfln("ERROR ReadDirectoryChangesW")
            break
        }

        if bytes == 0 {
            // buffer to small
            // make a bigger buffer and try again.
            // we need to notify user of the Watcher that this happens.
            // In a hotreloading system (either code or assets) the user needs to write and save the assets or code again
            // to reload.
        } else {
            sync.mutex_lock(&watcher.events_mutex)
            
            offset: i32
            
            events: ^[dynamic]WatchEvent
            if watcher.use_events_0 {
                events = &watcher.events_0
            } else {
                events = &watcher.events_1
            }
            event: WatchEvent
            for {
                info := cast(^windows.FILE_NOTIFY_INFORMATION) mem.ptr_offset(raw_data(buffer), offset)
                offset += cast(i32)info.NextEntryOffset
                err : runtime.Allocator_Error
                event.path, err = windows.wstring_to_utf8_alloc(transmute(cstring16)&info.FileName, cast(int)info.FileNameLength/2, context.allocator)
                if err != .None {
                    fmt.printfln("_watcher_thread_main: allocator wstring_to_utf8_alloc %v", err)
                } else {

                    skip: bool
                    switch info.Action {
                        case windows.FILE_ACTION_ADDED:
                            event.type = .ADDED
                            // fmt.printfln("added %v", event.path)
                        case windows.FILE_ACTION_REMOVED:
                            event.type = .REMOVED
                            // fmt.printfln("removed %v", event.path)
                        case windows.FILE_ACTION_MODIFIED:
                            event.type = .MODIFIED
                            // fmt.printfln("modified %v", event.path)
                        case windows.FILE_ACTION_RENAMED_OLD_NAME:
                            event.type = .RENAMED
                            event.old_path = event.path
                            // fmt.printfln("renamed old %v", event.path)
                        case windows.FILE_ACTION_RENAMED_NEW_NAME:
                            skip = true
                            (events^)[len(events^)-1].path = event.path
                            // fmt.printfln("renamed new %v", event.path)
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
                        new_path, was_allocation := strings.replace_all(event.path, "\\", "/")
                        if was_allocation {
                            delete(event.path)
                        }
                        event.path = new_path
                        
                        new_path, was_allocation = strings.replace_all(event.old_path, "\\", "/")
                        if was_allocation {
                            delete(event.old_path)
                        }
                        event.old_path = new_path
                        
                        append(events, event)
                        // @TODO Memory leak when skipping event since we allocated path
                    }
                }

                if info.NextEntryOffset == 0 {
                    break
                }
            }

            sync.mutex_unlock(&watcher.events_mutex)
        }

        res = cast(bool)windows.FindNextChangeNotification(transmute(windows.HANDLE)watcher.notification_handle)
        if !res {
            fmt.printfln("ERROR FindNextChangeNotification")
            break
        }
    }

    delete(buffer)

    res := windows.CloseHandle(transmute(windows.HANDLE)watcher.directory_handle)
    if !res {
        // fmt.println("ERROR CloseHandle")
    }
    res = windows.FindCloseChangeNotification(transmute(windows.HANDLE)watcher.notification_handle)
    if !res {
        // fmt.println("ERROR FindCloseChangeNotification")
    }
    
    sync.mutex_lock(&watcher.events_mutex)
    delete(watcher.events_0)
    delete(watcher.events_1)
    watcher.directory_handle = 0
    watcher.notification_handle = 0
    sync.mutex_unlock(&watcher.events_mutex)
}

_watcher_cleanup :: proc (watcher: ^Watcher) {
    res := windows.CloseHandle(transmute(windows.HANDLE)watcher.directory_handle)
    if !res {
        fmt.println("ERROR CloseHandle")
    }

    thread.join(watcher.thread)
    thread.destroy(watcher.thread)

    // Thread cleans itself up.
    // Unless it exited abnormally.
}
