package central

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

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4
mat4 :: glsl.mat4


Vertex :: struct {
    // See object.glsl shader
    pos:      vec3,
    normal:   vec3,
    texcoord: vec2,
}   

Material :: struct {
    diffuse:      vec3,
    // specular : vec3,
    base_texture: Texture,
    useTexture: bool,
}

Mesh :: struct {
    vao, vbo, ibo: u32,
    index_count: i32,
    unused: bool,

    material: Material,
    vertex_data: []f32,
    indices:  []u32,
}

Model :: struct {
    meshes: [dynamic]Mesh,
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


// cleanup_model :: proc (model: ^Model) {
//     cgltf.free(model.raw_data)
//     model.raw_data = nil

//     for i in 0..<len(model.meshes) {
//         mesh := &model.meshes[i]
//         gl.DeleteVertexArrays(1, &mesh.vao)
//         gl.DeleteBuffers     (1, &mesh.vbo)
//         gl.DeleteBuffers     (1, &mesh.ibo)

//         gl.DeleteTextures(1, &mesh.material.base_texture.id)

//         delete(mesh.vertices)
//         delete(mesh.indices)
//     }
//     clear(&model.meshes)
// }


load_model :: proc (path : string, model: ^Model) {
    // assumes model is clean and zeroed.

    cpath := strings.unsafe_string_to_cstring(path)
    options: cgltf.options
    c: runtime.Context = context
    options.file.user_data = &c
    options.file.read = override_file_read
    options.file.release = override_file_release
    data, result := cgltf.parse_file(options, cpath)

    if result != .success {
        fmt.printfln("cgltf failed, could not parse %v", path)
        return
    }

    result = cgltf.load_buffers(options, data, cpath)
    if result != .success {
        fmt.printfln("cgltf failed, could not load buffers %v", path)
        return
    }

    scene := data.scenes[0]
    node := scene.nodes[0]
    mesh := node.mesh

    next_mesh_index: i32

    for &mesh in model.meshes {
        mesh.unused = true
    }

    for pi in 0..<len(mesh.primitives) {
        primitive := &mesh.primitives[pi]

        assert(primitive.type == .triangles)
        assert(primitive.attributes[0].type == .position)
        assert(primitive.attributes[1].type == .normal)
        assert(primitive.attributes[0].data.count == primitive.attributes[1].data.count)
        assert(primitive.attributes[0].data.component_type == .r_32f)
        assert(primitive.attributes[1].data.component_type == .r_32f)
        assert(primitive.indices.component_type == .r_16u)
        
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
        if primitive.material.has_pbr_metallic_roughness {
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

        material: Material

        // @TODO material depends on 
        if primitive.material.has_pbr_metallic_roughness && primitive.material.pbr_metallic_roughness.base_color_texture.texture != nil {
            bytes := slice.from_ptr(cast(^u8)mem.ptr_offset(cast(^u8)primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.buffer.data, primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.offset), cast(int) primitive.material.pbr_metallic_roughness.base_color_texture.texture.image_.buffer_view.size)
            load_texture(bytes, &material.base_texture)
            material.useTexture = true
        } else {
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
            append(&model.meshes, Mesh{})
        }
        mesh := &model.meshes[next_mesh_index]
        next_mesh_index += 1
        mesh.unused = false

        mesh.vertex_data = f32_vertices
        mesh.indices = indices
        mesh.material = material
        mesh.index_count = cast(i32)len(indices)
    }

    cgltf.free(data)
}

load_model_render :: proc (model: ^Model) {
    for i := len(model.meshes)-1; i >= 0; i -= 1 {
        mesh := &model.meshes[i]

        if mesh.vao != 0 {
            gl.DeleteVertexArrays(1, &mesh.vao)
            gl.DeleteBuffers     (1, &mesh.vbo)
            gl.DeleteBuffers     (1, &mesh.ibo)
            if mesh.material.base_texture.id != 0 {
                gl.DeleteTextures(1, &mesh.material.base_texture.id)
            }
        }
        if mesh.unused {
            unordered_remove(&model.meshes, i)
            continue
        }

        gl.GenVertexArrays(1, &mesh.vao)
        gl.GenBuffers     (1, &mesh.vbo)
        gl.GenBuffers     (1, &mesh.ibo)

        gl.BindVertexArray(mesh.vao)


        start := time.now()
        gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
        gl.BufferData(gl.ARRAY_BUFFER, len(mesh.vertex_data) * size_of(f32), raw_data(mesh.vertex_data), gl.STATIC_DRAW)

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(mesh.indices) * size_of(u32), raw_data(mesh.indices), gl.STATIC_DRAW)
        // position attribute
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(f32) * 8, cast(uintptr)0)
        gl.EnableVertexAttribArray(0)

        // normal attribyte
        gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(f32) * 8, cast(uintptr)(3*size_of(f32)))
        gl.EnableVertexAttribArray(1)
            
        // texture coordinate attribute
        gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, size_of(f32) * 8, cast(uintptr)(6*size_of(f32)))
        gl.EnableVertexAttribArray(2)

        gl.BindVertexArray(0)

        
        if mesh.material.base_texture.id == 0 {
            init_texture_render(&mesh.material.base_texture)
        }
        end := time.now()

        
        // fmt.printfln("%v", time.diff(start, end))
        
        delete(mesh.vertex_data)
        delete(mesh.indices)
    }
}
