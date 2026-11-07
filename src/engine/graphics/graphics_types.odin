package graphics

import vk "vendor:vulkan"
import gl "vendor:OpenGL"

import "core:math/linalg/glsl"



vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4
mat4 :: glsl.mat4



VertexBuffer :: struct {
    vertex_count: i32,
    vertex_data: []f32,
    
    internal: union {
        opengl_VertexBuffer,
        vulkan_VertexBuffer,
    }
}

IndexBuffer :: struct {
    index_count: i32,
    indices:  []u32,
    
    internal: union {
        opengl_IndexBuffer,
        vulkan_IndexBuffer,
    }
}

VertexFormat :: enum u8 {
    FLOAT32_1,
    FLOAT32_2,
    FLOAT32_3,
    FLOAT32_4,
    UINT32_1,
    UINT32_2,
    UINT32_3,
    UINT32_4,
}

VertexAttribute :: struct {
    location: u8,
    format: VertexFormat,
}

VertexLayout :: struct {
    attributeCount: u8,
    attributes: [8]VertexAttribute,
    attributesOffsets: [8]u16,
    stride: u16,

    internal: union {
        opengl_VertexArrayObject,
        // vulkan has no VAO
        // we construct necessary objects during pipeline creation from the attributes above.
    }
}

Texture :: struct {
    width: u32,
    height: u32,
    raw_data: [^]u8,

    // @NOCHECKIN opengl specific ID!!!
    id: u32,
}

Material :: struct {
    diffuse:      vec3,
    // specular : vec3,
    base_texture: Texture,
    useTexture: bool,
}

Mesh :: struct {
    vertexBuffer: VertexBuffer,
    indexBuffer: IndexBuffer,
    vertexLayout: VertexLayout,

    unused: bool,

    material: Material,
}

Shader :: struct {
    internal: union {
        opengl_Shader,
        vulkan_Shader,
    }
}


get_vertex_format_details :: proc (f: VertexFormat) -> (count: u32, element_size: u32, is_float: bool) {
    count = 1 + cast(u32)f % 4
    element_size = 4
    is_float = cast(int)f < cast(int)VertexFormat.UINT32_1
    return
}



//#################################
//        OPENGL
//#################################


opengl_VertexBuffer :: struct {
    vbo: u32,
}

opengl_IndexBuffer :: struct {
    ibo: u32,
}

opengl_VertexArrayObject :: struct {
    vao: u32,
}



opengl_Shader :: struct {
    program: u32,
    uniforms: gl.Uniforms,
}



//#################################
//        VULKAN
//#################################



vulkan_VertexBuffer :: struct {
    buffer: vk.Buffer,
    bufferMemory: vk.DeviceMemory,
}

vulkan_IndexBuffer :: struct {
    buffer: vk.Buffer,
    bufferMemory: vk.DeviceMemory,
}


vulkan_Shader :: struct {
    vert_shader: vk.ShaderModule,
    frag_shader: vk.ShaderModule,
}
