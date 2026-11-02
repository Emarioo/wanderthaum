/*
    This file is responsible for saving and loading worlds.

    File extension is typically .wth (wanderthaum)


    @TODO How do we handle errors, crashes when saving world data.
       We do not want the user to loose progress.
*/

package central

import "core:fmt"
import "core:os"
import "base:runtime"
import "core:math/rand"
import "base:intrinsics"
import "core:c"

WorldFormat_Header :: struct {
    magic:          [4]u8, // "WTHB" (binary) or "WTHT" (text)
    format_version: u32,
    game_version:   u32,
    toc_count:      u32, // TOC = Table Of Contents
    toc_offset:     u64,
}

WorldFormat_TOC_Type :: enum u16 {
    ASSET_ARRAY,
    ENTITY_ARRAY,
}

WorldFormat_TOC_Entry :: struct {
    type:   WorldFormat_TOC_Type,
    flags:  u16,
    id:     u32,
    size:   u64, // represents the allocated size of the TOC entry. The data may not be fully utilized and reserved for growth by the TOC type.
    offset: u64,
}

WorldFormat_TOC_EntityArray :: struct {
    entity_count:  u32,
    _reserved:     u32,
    entity_offset: u64,
}

WorldFormat_Entity :: struct {
    id: u64,
    pos: vec3,
    scale: vec3,
    vel: vec3,
    force: vec3,

    hidden: bool,
    killed: bool,
    assetID: u64,
}

WorldFormat_TOC_AssetArray :: struct {
    asset_count:  u32,
    _reserved:    u32,
    asset_offset: u64,
}

WorldFormat_Asset :: struct {
    id:   u64,
    name: [64]u8, // @TODO Handle dynamic string?
}



World_Operation :: enum {
    SAVE_WORLD,
    LOAD_WORLD,
}


WorldFormat_State :: struct {
    file: ^os.File,
    gameState: ^GameState,
    path: string,
}


// saveAsText : bool = true

// set_save_world_text_mode :: proc (enabled: bool) {
//     saveAsText = enabled
// }

sync_world :: proc (path: string, operation: World_Operation, gameState: ^GameState) -> bool {

    err: os.Error
    file: ^os.File
    readBytes: int
    writtenBytes: int
    seekOffset: i64

    // @TODO Before saving we should make a copy so we don't start overriding and crash

    // @TODO We should validate values in the data. For example offset to TOC data is within range of the file.
    //   Seek should fail but still.

    if operation == .LOAD_WORLD {
        header: WorldFormat_Header
        readBytes: int

        
        file, err = os.open(path, {.Read})
        if err != nil {
            fmt.println("Could not open world ", path)
            return false
        }
        
        formatState: WorldFormat_State
        formatState.file = file
        formatState.gameState = gameState
        formatState.path = path

        read_offset : int = 0

        read_header(&formatState, &header) or_return
        read_offset += size_of(header)
        // fmt.println(header)

            
        tocEntry_asset: WorldFormat_TOC_Entry
        tocEntry_entity: WorldFormat_TOC_Entry
        read_toc_entry(&formatState, 0, &tocEntry_asset) or_return
        read_toc_entry(&formatState, 1, &tocEntry_entity) or_return
        // fmt.println(tocEntry_asset)
        // fmt.println(tocEntry_entity)

        
        assetArray: WorldFormat_TOC_AssetArray

        read_offset = cast(int)tocEntry_asset.offset
        read_bytes(&formatState, read_offset, (transmute([^]byte)(&assetArray))[:size_of(assetArray)]) or_return
        read_offset += size_of(assetArray)

        assetMap: map[u64]string

        for ai in 0..<assetArray.asset_count {
            assetItem: WorldFormat_Asset
            read_bytes(&formatState, read_offset, (transmute([^]byte)(&assetItem))[:size_of(assetItem)]) or_return
            read_offset += size_of(assetItem)
            // fmt.println(assetItem)

            name := string(assetItem.name[:])
            assetMap[assetItem.id] = name
        }

        entityArray: WorldFormat_TOC_EntityArray

        read_offset = cast(int)tocEntry_entity.offset
        read_bytes(&formatState, read_offset,  (transmute([^]byte)(&entityArray))[:size_of(entityArray)]) or_return
        read_offset += size_of(entityArray)

        // @TODO Properly kill/delete all entities?
        //   Maybe this is the proper way because we want to clear and refresh previous state completely.
        //   We don't want to kill and have background things happening. Since when we saved the entities
        //   we didn't kill it and don't expect background things to happen.
        gameState.engine.entities_count = 0

        for ai in 0..<entityArray.entity_count {
            entityItem: WorldFormat_Entity
            read_bytes(&formatState, read_offset, (transmute([^]byte)(&entityItem))[:size_of(entityItem)]) or_return
            read_offset += size_of(entityItem)
            // fmt.println(entityItem)

            entity, _ := create_entity(&gameState.engine)
            entity.id = entityItem.id
            entity.pos = entityItem.pos
            entity.scale = entityItem.scale
            entity.vel = entityItem.vel
            entity.force = entityItem.force
            entity.hidden = entityItem.hidden
            entity.killed = entityItem.killed
            assetName, exists := assetMap[entityItem.assetID]
            if exists {
                asset, exists := gameState.engine.storage.assets_by_name[assetName]
                if exists {
                    entity.asset = asset
                }
            }
        }

        // @TODO When loading we should not immediately update entity data.

        // @TODO When loading world we need to check if game version is different from current
        //   if so we should try to transform it into current version.
        //   Not sure if we do this here.

    } else if operation == .SAVE_WORLD {
        header: WorldFormat_Header
        
        // file, err = os.open(path, {.Read, .Write, .Create})
        file, err = os.open(path, {.Write, .Create})
        if err != nil {
            fmt.println("Could not open/save world ", path)
            return false
        }

        formatState: WorldFormat_State
        formatState.file = file
        formatState.gameState = gameState
        formatState.path = path

        write_offset : int = 0
        
        header.magic = "WTHB"
        header.format_version = 1
        header.game_version = 1
        header.toc_count = 2
        header.toc_offset = cast(u64)(write_offset + size_of(header))

        write_header(&formatState, &header) or_return
        // fmt.println(header)


        tocEntry_asset: WorldFormat_TOC_Entry
        tocEntry_asset.type = .ASSET_ARRAY
        tocEntry_asset.flags = 0
        tocEntry_asset.id = rand.uint32()
        tocEntry_asset.size = 0
        // tocEntry_asset.offset = 0; set later
        
        tocEntry_entity: WorldFormat_TOC_Entry
        tocEntry_asset.type = .ENTITY_ARRAY
        tocEntry_asset.flags = 0
        tocEntry_asset.id = rand.uint32()
        tocEntry_asset.size = 0
        // tocEntry_asset.offset = 0; set later


        write_offset = size_of(header) + 2 * size_of(tocEntry_asset)

        assetArray: WorldFormat_TOC_AssetArray
        assetArray.asset_count = cast(u32) len(gameState.engine.storage.assets_by_name)
        assetArray.asset_offset = cast(u64)(write_offset + size_of(assetArray))
        
        tocEntry_asset.offset = cast(u64)write_offset
        write_bytes(&formatState, write_offset, (transmute([^]byte)(&assetArray))[:size_of(assetArray)]) or_return
        write_offset += size_of(assetArray)
        // fmt.println(assetArray)

        for name, asset in gameState.engine.storage.assets_by_name {
            assetItem: WorldFormat_Asset
            assetItem.id = asset.id
            assetItem.name = {}
            copy(assetItem.name[:], name)


            write_bytes(&formatState, write_offset, (transmute([^]byte)(&assetItem))[:size_of(assetItem)]) or_return
            write_offset += size_of(assetItem)
            // fmt.println(assetItem)
        }
        
        entityArray: WorldFormat_TOC_EntityArray
        entityArray.entity_count = cast(u32) gameState.engine.entities_count
        entityArray.entity_offset = cast(u64)(write_offset + size_of(entityArray))

        tocEntry_entity.offset = cast(u64)write_offset
        write_bytes(&formatState, write_offset, (transmute([^]byte)(&entityArray))[:size_of(entityArray)]) or_return
        write_offset += size_of(entityArray)
        // fmt.println(entityArray)

        for ei in 0..<gameState.engine.entities_count {
            entity := &gameState.engine.entities[ei]

            entityItem: WorldFormat_Entity
            entityItem.id = entity.id
            entityItem.pos = entity.pos
            entityItem.scale = entity.scale
            entityItem.vel = entity.vel
            entityItem.force = entity.force
            entityItem.hidden = entity.hidden
            entityItem.killed = entity.killed
            if entity.asset != nil {
                entityItem.assetID = entity.asset.id
            } else {
                // Player entity currently has no asset
                entityItem.assetID = 0
            }

            write_bytes(&formatState, write_offset, (transmute([^]byte)(&entityItem))[:size_of(entityItem)]) or_return
            write_offset += size_of(entityItem)
            // fmt.println(entityItem)
        }
        
        write_toc_entry(&formatState, 0, &tocEntry_asset) or_return
        write_toc_entry(&formatState, 1, &tocEntry_entity) or_return
        // fmt.println(tocEntry_asset)
        // fmt.println(tocEntry_entity)
    }

    err = os.close(file)
    
    return true
}



write_header :: proc (state: ^WorldFormat_State, header: ^WorldFormat_Header) -> bool {
    offset := 0
    return write_bytes(state, offset, (transmute([^]byte)(header))[:size_of(header^)])
}
read_header :: proc (state: ^WorldFormat_State, header: ^WorldFormat_Header) -> bool {
    offset := 0
    return read_bytes(state, offset, (transmute([^]byte)(header))[:size_of(header^)])
}
write_toc_entry :: proc (state: ^WorldFormat_State, index: int, toc_entry: ^WorldFormat_TOC_Entry) -> bool {
    offset := size_of(WorldFormat_Header) + index * size_of(toc_entry^)
    return write_bytes(state, offset, (transmute([^]byte)(toc_entry))[:size_of(toc_entry^)])
}
read_toc_entry :: proc (state: ^WorldFormat_State, index: int, toc_entry: ^WorldFormat_TOC_Entry) -> bool {
    offset := size_of(WorldFormat_Header) + index * size_of(toc_entry^)
    return read_bytes(state, offset, (transmute([^]byte)(toc_entry))[:size_of(toc_entry^)])
}

write_bytes :: proc (state: ^WorldFormat_State, offset: int, bytes: []byte) -> bool {
    writtenBytes: int

    seekOffset, err := os.seek(state.file, cast(i64)offset, .Start)
    if err != nil || seekOffset != cast(i64)offset {
        fmt.println("Could not seek (", seekOffset,"/", offset,"), ", state.path)
        return false
    }
    
    writtenBytes, err = os.write(state.file, bytes)
    if err != nil || writtenBytes != len(bytes) {
        fmt.println("Could not write (", writtenBytes,"/", len(bytes),"), ", state.path)
        return false
    }

    return true
}

read_bytes :: proc (state: ^WorldFormat_State, offset: int, bytes: []byte) -> bool {
    readBytes: int

    seekOffset, err := os.seek(state.file, cast(i64)offset, .Start)
    if err != nil || seekOffset != cast(i64)offset {
        fmt.println("Could not seek (", seekOffset,"/", offset,"), ", state.path)
        return false
    }
    
    readBytes, err = os.read(state.file, bytes)
    if err != nil || readBytes != len(bytes) {
        fmt.println("Could not read (", readBytes,"/", len(bytes),"), ", state.path)
        return false
    }

    return true
}
