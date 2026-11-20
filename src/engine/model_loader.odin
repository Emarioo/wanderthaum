package engine

// import "../cgltf"
import "vendor:cgltf"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:math/linalg/glsl"
import "core:math"
import "core:mem"
import "core:c"
import "base:runtime"
import "core:time"
import gl "vendor:OpenGL"
import stb_image "vendor:stb/image"

import "./graphics"

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4
mat4 :: glsl.mat4


Vertex :: struct {
    // See object.glsl shader
    pos:      vec3,
    normal:   vec3,
    texcoord: vec2,
    //  joints: [4]u16,
    //  weights: [4]f32,
}   

// Model_Node :: struct {
//     name: string,

//     mesh_inex: i32,
//     skin_index: i32,
//     parent: i32,
//     children: [dynamic]i32,

//     pos: vec3,
//     rot: glsl.quat,
//     scale: vec3,
// }

// Skin :: struct {
//     joints: [dynamic]i32,
//     inverse_bind_matrices: [dynamic]mat4,
//     skeleton: i32,
// }

// Animation :: struct {
//     name: string,
//     duration: f32,

// }

Collider :: struct {
    // @TODO Cylinder
    min_point: vec3, // bounding box
    max_point: vec3,
}

Model :: struct {
    meshes: [dynamic]graphics.Mesh,
    // nodes: [dynamic]Model_Node, // first node is the root node
    // skins: [dynamic]Skin,
    // animations: [dynamic]Animation,

    // overall bounding box
    min_point: vec3,
    max_point: vec3,
    // specific bounding box
    colliders: [dynamic]Collider,
    
}


override_file_read :: proc "c" (memory_options: ^cgltf.memory_options, file_options: ^cgltf.file_options, path: cstring, size: ^uint, data: ^rawptr) -> cgltf.result {
    context = (cast(^runtime.Context)file_options.user_data)^
    
    filepath := string(path)
    file_data, err := os.read_entire_file(filepath, context.allocator)
    if err != nil {
        return .file_not_found
    }
    
    size^ = len(file_data)
    data^ = transmute(rawptr)raw_data(file_data)
    
    return .success
}

override_file_release :: proc "c" (memory_options: ^cgltf.memory_options, file_options: ^cgltf.file_options, data: rawptr) {
    context = (cast(^runtime.Context)file_options.user_data)^

    bytes := slice.bytes_from_ptr(data, 0)
    delete(bytes)
}


NodeEntry :: struct {
    node: ^cgltf.node,
    is_collider: bool,
    // transform: matrix[4,4]f32,
}

// find_mesh_node :: proc (node: ^cgltf.node, transform: matrix[4,4]f32, nodes: ^[dynamic]NodeEntry) {
find_mesh_node :: proc (node: ^cgltf.node, nodes: ^[dynamic]NodeEntry, parent_is_collider: bool, has_explicit_collider: ^bool) {
    if strings.contains(strings.string_from_null_terminated_ptr(transmute([^]byte)node.name, 256), "rigidbodies") {
        // wuthering waves models' has this node with
        // a bunch of capsule meshes which we don't care about.
        return
    }
    is_collider := parent_is_collider
    if strings.contains(strings.string_from_null_terminated_ptr(transmute([^]byte)node.name, 256), "_collider") {
        is_collider = true
        has_explicit_collider^ = true
    }
    if node.mesh != nil {
        // fmt.println("NODE",node.name, is_collider, parent_is_collider, has_explicit_collider^)
        append(nodes, { node, is_collider })
        // append(nodes, { node, transform})
    }
    for child in node.children {
        // newTransform: matrix[4,4]f32
        // if child.has_matrix {
        //     newTransform = transform * transmute(matrix[4,4]f32)child.matrix_
        // } else {
        //     panic("node has no matrix, derive it from pos, scale, rotate")
        // }
        find_mesh_node(child, nodes, is_collider, has_explicit_collider)
    }
}

load_model :: proc (path : string, model: ^Model) {
    // assumes model is clean and zeroed.

    // @NOCHECKIN Fix

    cpath := strings.unsafe_string_to_cstring(path)
    options: cgltf.options
    c: runtime.Context = context
    options.file.user_data = &c
    options.file.read = override_file_read
    options.file.release = override_file_release
    data, result := cgltf.parse_file(options, cpath)

    if result != .success {
        fmt.printfln("cgltf failed %v, could not parse %v, result", result, path)
        return
    }

    result = cgltf.load_buffers(options, data, cpath)
    if result != .success {
        fmt.printfln("cgltf failed, could not load buffers %v", path)
        return
    }

    scene := data.scenes[0]


    // fmt.println("HANDLING", path)



    next_mesh_index: i32

    for &mesh in model.meshes {
        mesh.unused = true
    }

    nodes: [dynamic]NodeEntry
    defer delete(nodes)
    
    has_explicit_collider: bool
    find_mesh_node(scene.nodes[0], &nodes, false, &has_explicit_collider)
    if len(nodes) == 0 {
        fmt.printfln("cgltf failed, could not find mesh node %v", path)
        return
    }

    total_min_point := vec3{max(f32),max(f32),max(f32)}
    total_max_point := vec3{min(f32),min(f32),min(f32)}

    for nodeEntry in nodes {
        mesh := nodeEntry.node.mesh
        if mesh == nil {
            continue
        }

        nodeTransform: matrix[4,4]f32
        cgltf.node_transform_world(nodeEntry.node, cast([^]f32)&nodeTransform)

        // fmt.println("node",nodeEntry.node.name)
        
        min_point := vec3{max(f32),max(f32),max(f32)}
        max_point := vec3{min(f32),min(f32),min(f32)}
        
        for pi in 0..<len(mesh.primitives) {
            primitive := &mesh.primitives[pi]

            assert(primitive.type == .triangles)
            assert(primitive.attributes[0].type == .position)
            assert(primitive.attributes[1].type == .normal)
            assert(primitive.attributes[0].data.count == primitive.attributes[1].data.count)
            assert(primitive.attributes[0].data.component_type == .r_32f)
            assert(primitive.attributes[1].data.component_type == .r_32f)
            assert(primitive.indices.component_type == .r_16u)

            // @TODO min,max point should be transformed
            if nodeEntry.is_collider || !has_explicit_collider {
                if primitive.attributes[0].data != nil && primitive.attributes[0].data.has_min && primitive.attributes[0].data.has_max {
                    new_min_point := &primitive.attributes[0].data.min
                    new_max_point := &primitive.attributes[0].data.max
                    
                    (transmute(^[3]f32)new_min_point)^ = (nodeTransform * vec4{new_min_point[0], new_min_point[1], new_min_point[2], 1}).xyz
                    (transmute(^[3]f32)new_max_point)^ = (nodeTransform * vec4{new_max_point[0], new_max_point[1], new_max_point[2], 1}).xyz

                    min_point.x = min(min_point.x, new_min_point[0], new_max_point[0])
                    min_point.y = min(min_point.y, new_min_point[1], new_max_point[1])
                    min_point.z = min(min_point.z, new_min_point[2], new_max_point[2])
                    max_point.x = max(max_point.x, new_min_point[0], new_max_point[0])
                    max_point.y = max(max_point.y, new_min_point[1], new_max_point[1])
                    max_point.z = max(max_point.z, new_min_point[2], new_max_point[2])
                    
                    // fmt.println("col", nodeEntry.node.name, max_point - min_point)
                }
            }

            if nodeEntry.is_collider {
                continue
            }
            
            vertex_count := primitive.attributes[0].data.count
            index_count := primitive.indices.count
            vertices := make([]Vertex, vertex_count)
            indices  := make([]u32, index_count)
            
            // We assume POSITION is attribute[0]
            // We assume NORMAL is attribute[1]
            // We assume TEXCOORD0 is attribute[2]
            // We assume TEXCOORDn is attribute[2+n]
            position_acc   := primitive.attributes[0].data
            normal_acc     := primitive.attributes[1].data
            texcoord_acc   : ^cgltf.accessor
            if primitive.material != nil && primitive.material.has_pbr_metallic_roughness && primitive.material.pbr_metallic_roughness.base_color_texture.texture != nil {
                index := 2 + primitive.material.pbr_metallic_roughness.base_color_texture.texcoord
                assert(primitive.attributes[index].type == cgltf.attribute_type.texcoord)
                // fmt.printfln("tex %v %v", primitive.material.name, primitive.material.pbr_metallic_roughness.base_color_texture.texcoord)
                texcoord_acc = primitive.attributes[index].data
            }
            
            for j in 0..<vertex_count {
                
                pos_ptr := cast([^]f32)&vertices[j].pos
                res := cgltf.accessor_read_float(position_acc, j, pos_ptr, 3)
                
                vec_ptr := cast([^]vec3)&vertices[j].pos
                vec_ptr[0] = (nodeTransform * vec4{vec_ptr[0].x, vec_ptr[0].y, vec_ptr[0].z, 1}).xyz

                // @TODO Transform normal We shouldn't apply position, only transform and scale?
                res = cgltf.accessor_read_float(normal_acc, j, cast([^]f32)&vertices[j].normal, 3)
                if texcoord_acc != nil {
                    res = cgltf.accessor_read_float(texcoord_acc, j, cast([^]f32)&vertices[j].texcoord, 2)
                    // Needed if load_texture flips the texture on load.
                    // load_texture currently flips the texture because drawing images are upside-down otherwise.
                    // Do we want to move this quirk into the shaders instead?
                    vertices[j].texcoord.y = 1 - vertices[j].texcoord.y
                }
            }
            index_acc := primitive.indices
            for j in 0..<index_count {
                indices[j] = cast(u32)cgltf.accessor_read_index(index_acc, j)
            }

            material: graphics.Material

            // @TODO material depends on 
            if primitive.material != nil && primitive.material.has_pbr_metallic_roughness && primitive.material.pbr_metallic_roughness.base_color_texture.texture != nil {
                bytes := slice.from_ptr(cast(^u8)mem.ptr_offset(cast(^u8)primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.buffer.data, primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.offset), cast(int) primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.size)
                load_texture(bytes, &material.base_texture)
                // fmt.println("YES TEXTURE")
                material.useTexture = true
            } else {
                // fmt.println("NO TEXTURE")
                material.useTexture = false
            }
            if primitive.material != nil && primitive.material.has_pbr_metallic_roughness {
                material.diffuse = primitive.material.pbr_metallic_roughness.base_color_factor.xyz
            } else if !material.useTexture {
                // default color
                material.diffuse = {0.9,0.9,0.9}
            }

            // material.specular_color

            // fmt.printfln("append mesh %v, %v, %v", primitive.name, vertex_count, index_count)

            f32_vertices := slice.from_ptr(cast(^f32)slice.first_ptr(vertices), len(vertices) * size_of(Vertex) / size_of(f32))

            if next_mesh_index >= cast(i32)len(model.meshes) {
                append(&model.meshes, graphics.Mesh{})
            }
            mesh := &model.meshes[next_mesh_index]
            next_mesh_index += 1
            mesh.unused = false

            mesh.vertexBuffer.vertex_data = f32_vertices
            mesh.indexBuffer.indices = indices
            mesh.material = material
            mesh.indexBuffer.index_count = cast(u32)len(indices)
        }
        
        total_min_point.x = min(total_min_point.x, min_point.x)
        total_min_point.y = min(total_min_point.y, min_point.y)
        total_min_point.z = min(total_min_point.z, min_point.z)
        total_max_point.x = max(total_max_point.x, max_point.x)
        total_max_point.y = max(total_max_point.y, max_point.y)
        total_max_point.z = max(total_max_point.z, max_point.z)

        collider: Collider = {
            min_point,
            max_point,
        }
        append(&model.colliders, collider)
    }


    for i := len(model.meshes)-1; i >= 0; i -= 1 {
        if !model.meshes[i].unused {
            resize(&model.meshes, i + 1)
            break
        }
    }

    model.min_point = total_min_point
    model.max_point = total_max_point

    cgltf.free(data)
}

load_model_render :: proc (state: ^EngineState, model: ^Model) {
    
    for i := len(model.meshes)-1; i >= 0; i -= 1 {
        mesh := &model.meshes[i]

        attributes: []graphics.VertexAttribute = {
            { 0, .FLOAT32_3 },
            { 1, .FLOAT32_3 },
            { 2, .FLOAT32_2 },
        }

        graphics.make_mesh(&state.render_state.graphicsState, mesh.vertexBuffer.vertex_data, mesh.indexBuffer.indices, attributes, mesh)

        delete(mesh.vertexBuffer.vertex_data)
        mesh.vertexBuffer.vertex_data = nil
        delete(mesh.indexBuffer.indices)
        mesh.indexBuffer.indices = nil
        
        stb_image.image_free(mesh.material.base_texture.raw_data)
        mesh.material.base_texture.raw_data = nil
    }
}

destroy_model_render :: proc (state: ^EngineState, model: ^Model) {
    
    for i := len(model.meshes)-1; i >= 0; i -= 1 {
        mesh := &model.meshes[i]

        graphics.destroy_mesh(&state.render_state.graphicsState, mesh)
        
        if mesh.vertexBuffer.vertex_data != nil {
            delete(mesh.vertexBuffer.vertex_data)
            mesh.vertexBuffer.vertex_data = nil
        }
        if mesh.indexBuffer.indices != nil {
            delete(mesh.indexBuffer.indices)
            mesh.indexBuffer.indices = nil
        }
        if mesh.material.base_texture.raw_data != nil {
            stb_image.image_free(mesh.material.base_texture.raw_data)
            mesh.material.base_texture.raw_data = nil
        }
    }
}
