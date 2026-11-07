package graphics

import "core:fmt"

import gl "vendor:OpenGL"


opengl_load_shader :: proc (backend: rawptr, vertex_text, fragment_text : string, shader: ^opengl_Shader) -> bool {
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



opengl_make_mesh :: proc (backend: rawptr, vertices: []f32, indices: []u32, mesh: ^Mesh) -> bool {

    vao, vbo, ibo: u32

    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &vbo)
    if len(indices) > 0 {
        gl.GenBuffers(1, &ibo)
    }

    mesh.vertexLayout.internal = opengl_VertexArrayObject{ vao }
    mesh.vertexBuffer.internal = opengl_VertexBuffer{ vbo }
    mesh.indexBuffer.internal = opengl_IndexBuffer{ ibo }

    gl.BindVertexArray(vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)

    if len(indices) > 0 {
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(indices[0]), raw_data(indices), gl.STATIC_DRAW)
    }

    // position attribute
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

    return true
}
