package graphics

import "core:fmt"

import gl "vendor:OpenGL"


opengl_load_shader :: proc (backend: rawptr, vertex_text, fragment_text : string, shader: ^opengl_Shader, path: string) -> bool {
    ok: bool

    shader.program, ok = gl.load_shaders_source(vertex_text, fragment_text)
    if !ok {
        return false
        // os.exit(1)
    }
    shader.uniforms = gl.get_uniforms_from_program(shader.program)

    // fmt.printf("Loaded shader '%s'\n", path)
    return true
}


// Replaces previous buffers if they exist
opengl_make_mesh :: proc (backend: rawptr, vertices: []f32, indices: []u32, mesh: ^Mesh) -> bool {

    tmp_va, has_va := mesh.vertexLayout.internal.(opengl_VertexArrayObject)
    tmp_vb, has_vb := mesh.vertexBuffer.internal.(opengl_VertexBuffer)
    tmp_ib, has_ib := mesh.indexBuffer.internal.(opengl_IndexBuffer)
    if !has_va {
        tmp_va = {}
    }
    if !has_vb {
        tmp_vb = {}
    }
    if !has_vb {
        tmp_ib = {}
    }

    if tmp_va.vao != 0 {
        gl.DeleteVertexArrays(1, &tmp_va.vao)
        gl.DeleteBuffers     (1, &tmp_vb.vbo)
        if tmp_ib.ibo != 0 {
            gl.DeleteBuffers     (1, &tmp_ib.ibo)
        }
    }
    
    gl.GenVertexArrays(1, &tmp_va.vao)
    gl.GenBuffers     (1, &tmp_vb.vbo)
    gl.GenBuffers     (1, &tmp_ib.ibo)

    gl.BindVertexArray(tmp_va.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, tmp_vb.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)

    if len(indices) > 0 {
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, tmp_ib.ibo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(indices[0]), raw_data(indices), gl.STATIC_DRAW)
    }

    for i in 0..<mesh.vertexLayout.attributeCount {
        count, element_size, is_float := get_vertex_format_details(mesh.vertexLayout.attributes[i].format)
        type: u32 = gl.FLOAT
        if !is_float {
            type = gl.UNSIGNED_INT
        }
        gl.VertexAttribPointer(cast(u32)mesh.vertexLayout.attributes[i].location, cast(i32)count, type, gl.FALSE, cast(i32)mesh.vertexLayout.stride, cast(uintptr)mesh.vertexLayout.attributesOffsets[i])
        gl.EnableVertexAttribArray(cast(u32)mesh.vertexLayout.attributes[i].location)
    }
    
    gl.BindVertexArray(0)

    mesh.vertexLayout.internal = tmp_va 
    mesh.vertexBuffer.internal = tmp_vb 
    mesh.indexBuffer.internal = tmp_ib

    return true
}

opengl_make_texture :: proc (backend: rawptr, texture: ^Texture) {
    
    tmp_texture, has_texture := texture.internal.(opengl_Texture)
    
    if !has_texture {
        tmp_texture = {}
    }
    if tmp_texture.id != 0 {
        gl.DeleteTextures(1, &tmp_texture.id)
    }

    gl.GenTextures(1, &tmp_texture.id)
    gl.BindTexture(gl.TEXTURE_2D, tmp_texture.id)

    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    // gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    // start := time.now()
    // gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, cast(i32)texture.width, cast(i32)texture.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, texture.raw_data)
    // Colors become pale if we use gl.RGBA8. I think (or rather AI thinks) glTF stores textures in sRGB format or as sRGB corrected.
    // This was not an issue at first but since we added gl.Enable(gl.FRAMEBUFFER_SRGB) it became an issue because we color corrected them
    // twice or something. Reason for gl.Enable(gl.FRAMEBUFFER_SRGB) is because it matches with how our vulkan setup renders things.
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, cast(i32)texture.width, cast(i32)texture.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, texture.raw_data)
    // gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, cast(i32)texture.width, cast(i32)texture.height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    // end := time.now()
    
    // fmt.printfln("texture %v", time.diff(start, end))

    gl.BindTexture(gl.TEXTURE_2D, 0)

    texture.internal = tmp_texture
}
