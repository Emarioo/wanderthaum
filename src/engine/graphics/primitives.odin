/*
    Platform agnostic
*/

package graphics

import "core:fmt"
import "core:os"
import "core:strings"

import "core:math/linalg/glsl"

import gl "vendor:OpenGL"

load_shader :: proc (state: ^GraphicsState, path : string, shader: ^Shader) {
    bytes: []byte
    ok: bool
    err: os.Error
    bytes, err = os.read_entire_file(path, context.allocator)
    if err != nil {
        fmt.eprintln("Could not open",path)
        os.exit(1)
    }

    text := string(bytes)
    vertex_index   := strings.index(text, "#vertex") // don't pattern match \n, on Windows we have \r\n while on linux just \n
    fragment_index := strings.index(text, "#fragment")

    vertex_text := text[vertex_index+8:fragment_index]
    fragment_text := text[fragment_index+10:]

    switch state.renderBackend {
        case .OPENGL:
            internal_shader: opengl_Shader
            ok = opengl_load_shader(nil, vertex_text, fragment_text, &internal_shader, path)
            shader.internal = internal_shader

        case .VULKAN:
            internal_shader: vulkan_Shader
            ok = vulkan_make_shader_from_glsl(&state.vulkanBackend, vertex_text, fragment_text, &internal_shader, path)
            shader.internal = internal_shader

    }
    if !ok {
        fmt.eprintln("Failed loading shaders from", path)
    }
    // fmt.printf("Loaded shader '%s'\n", path)
}


destroy_shader :: proc (state: ^GraphicsState, shader: ^Shader) {
    
    switch state.renderBackend {
        case .OPENGL:
            tmp_shader, has_shader := shader.internal.(opengl_Shader)
            if has_shader {
                gl.DeleteProgram(tmp_shader.program)
            }
        case .VULKAN:

    }
    shader.internal = nil
}




make_mesh :: proc (state: ^GraphicsState, vertices: []f32, indices: []u32, attributes: []VertexAttribute, mesh: ^Mesh) {

    if len(attributes) > len(mesh.vertexLayout.attributes) {
        panic("Vertex buffer is limited to N attributes (currently 8 if this is up-to-date)")
    }

    mesh.vertexLayout.attributeCount = cast(u8)len(attributes)
    mesh.vertexLayout.stride = 0
    for i in 0..<len(attributes) {
        mesh.vertexLayout.attributes[i] = attributes[i]
        mesh.vertexLayout.attributesOffsets[i] = mesh.vertexLayout.stride
        count, esize, is_float := get_vertex_format_details(attributes[i].format)
        mesh.vertexLayout.stride += cast(u16)(count * esize)
    }

    mesh.vertexBuffer.vertex_count = cast(u32)(len(vertices) * size_of(f32) / cast(int)mesh.vertexLayout.stride)
    mesh.indexBuffer.index_count = cast(u32)len(indices)

    switch state.renderBackend {
        case .OPENGL:
            opengl_make_mesh(nil, vertices, indices, mesh)

        case .VULKAN:
            vulkan_make_mesh(&state.vulkanBackend, vertices, indices, mesh)
    }
    
    if mesh.material.useTexture {
        make_texture(state, &mesh.material.base_texture)
    }
}


make_texture :: proc (state: ^GraphicsState, texture: ^Texture) {

    switch state.renderBackend {
        case .OPENGL:
            opengl_make_texture(nil, texture)

        case .VULKAN:
            vulkan_make_texture(&state.vulkanBackend, texture)

    }
}

destroy_mesh :: proc (state: ^GraphicsState, mesh: ^Mesh) {
    
    switch state.renderBackend {
        case .OPENGL:
            tmp_va, has_va := mesh.vertexLayout.internal.(opengl_VertexArrayObject)
            tmp_vb, has_vb := mesh.vertexBuffer.internal.(opengl_VertexBuffer)
            tmp_ib, has_ib := mesh.indexBuffer.internal.(opengl_IndexBuffer)
            if has_va {
                gl.DeleteVertexArrays(1, &tmp_va.vao)
            }
            if has_vb {
                gl.DeleteBuffers     (1, &tmp_vb.vbo)
            }
            if has_ib {
                gl.DeleteBuffers     (1, &tmp_ib.ibo)
            }

        case .VULKAN:
            
    }
    
    mesh.vertexLayout.internal = nil
    mesh.vertexBuffer.internal = nil
    mesh.indexBuffer.internal = nil

    destroy_texture(state, &mesh.material.base_texture)
}


destroy_texture :: proc (state: ^GraphicsState, texture: ^Texture) {
    
    switch state.renderBackend {
        case .OPENGL:
            tmp_texture, has_texture := texture.internal.(opengl_Texture)
            
            if !has_texture {
                tmp_texture = {}
            }
            if tmp_texture.id != 0 {
                gl.DeleteTextures(1, &tmp_texture.id)
            }
        case .VULKAN:

    }
    texture.internal = nil
}

