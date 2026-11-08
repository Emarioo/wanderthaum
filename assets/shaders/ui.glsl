#vertex
#version 330 core

layout (location = 0) in vec2 aPos;

struct RectPushConstants {
    vec4 color;
    vec2 window;
    vec2 pos;
    vec2 size;
};

#ifdef VULKAN
    layout(push_constant) uniform constants {
        RectPushConstants fields;
    } pc;
#else
    struct constants {
        RectPushConstants fields;
    };
    uniform constants pc;
#endif

void main()
{
    // fTexcoord = aPos;
    gl_Position = vec4(
        2*(pc.fields.pos.x + aPos.x * pc.fields.size.x) / pc.fields.window.x - 1.0,
        2*(pc.fields.pos.y + aPos.y * pc.fields.size.y) / pc.fields.window.y - 1.0,
        0.0, 1.0);
}

#fragment
#version 330 core
layout (location = 0) out vec4 FragColor;


struct RectPushConstants {
    vec4 color;
    vec2 window;
    vec2 pos;
    vec2 size;
};

#ifdef VULKAN
    layout(push_constant) uniform constants {
        RectPushConstants fields;
    } pc;
#else
    struct constants {
        RectPushConstants fields;
    };
    uniform constants pc;
#endif


void main()
{
    vec4 result = pc.fields.color;
    // vec4 result = vec4(1);
    // result *= texture(uSampler, fTexcoord);
    // result *= vec4(fTexcoord,0,1);
    FragColor = result;
} 