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

Model :: struct {
    meshes: [dynamic]graphics.Mesh,
    // nodes: [dynamic]Model_Node, // first node is the root node
    // skins: [dynamic]Skin,
    // animations: [dynamic]Animation,

    min_point: vec3, // bounding box
    max_point: vec3,
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


find_mesh_node :: proc (node: ^cgltf.node) -> ^cgltf.node {
    if strings.contains(strings.string_from_null_terminated_ptr(transmute([^]byte)node.name, 256), "rigidbodies") {
        // wuthering waves models' has this node with
        // a bunch of capsule meshes which we don't care about.
        return nil
    }

    if node.mesh != nil {
        return node
    }
    for child in node.children {
        child_node := find_mesh_node(child)
        if child_node != nil {
            return child_node
        }
    }
    return nil
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
    node := find_mesh_node(scene.nodes[0])
    if node == nil {
        fmt.printfln("cgltf failed, could not find mesh node %v", path)
        return
    }

    // fmt.println("HANDLING", path)


    mesh := node.mesh

    next_mesh_index: i32

    for &mesh in model.meshes {
        mesh.unused = true
    }

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

        if primitive.attributes[0].data != nil && primitive.attributes[0].data.has_min && primitive.attributes[0].data.has_max {
            new_min_point := &primitive.attributes[0].data.min
            new_max_point := &primitive.attributes[0].data.max
            min_point.x = min(min_point.x, new_min_point[0])
            min_point.y = min(min_point.y, new_min_point[1])
            min_point.z = min(min_point.z, new_min_point[2])
            max_point.x = max(max_point.x, new_max_point[0])
            max_point.y = max(max_point.y, new_max_point[1])
            max_point.z = max(max_point.z, new_max_point[2])
            
            // fmt.println(path, min_point, max_point)
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
        if primitive.material.has_pbr_metallic_roughness && primitive.material.pbr_metallic_roughness.base_color_texture.texture != nil {
            index := 2 + primitive.material.pbr_metallic_roughness.base_color_texture.texcoord
            assert(primitive.attributes[index].type == cgltf.attribute_type.texcoord)
            // fmt.printfln("tex %v %v", primitive.material.name, primitive.material.pbr_metallic_roughness.base_color_texture.texcoord)
            texcoord_acc = primitive.attributes[index].data
        }
        
        for j in 0..<vertex_count {
            res := cgltf.accessor_read_float(position_acc, j, cast([^]f32)&vertices[j].pos, 3)
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
        if primitive.material.has_pbr_metallic_roughness && primitive.material.pbr_metallic_roughness.base_color_texture.texture != nil {
            bytes := slice.from_ptr(cast(^u8)mem.ptr_offset(cast(^u8)primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.buffer.data, primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.offset), cast(int) primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.size)
            load_texture(bytes, &material.base_texture)
            // fmt.println("YES TEXTURE")
            material.useTexture = true
        } else {
            // fmt.println("NO TEXTURE")
            material.useTexture = false
        }
        if primitive.material.has_pbr_metallic_roughness {
            material.diffuse = primitive.material.pbr_metallic_roughness.base_color_factor.xyz
        }

        // material.diffuse_color = {1,1,1}
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

    model.min_point = min_point
    model.max_point = max_point

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
