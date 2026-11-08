#vertex
#version 450

layout (location = 0) in vec2 aPos;

struct Constants {
    vec4 color;
    vec2 window;
    vec2 pos;
    vec2 size;
};

#ifdef VULKAN
    layout(push_constant)
    uniform constants {
        Constants fields;
    } pc;
    #define CONST pc.fields
#else
    uniform Constants CONST;
#endif

void main()
{
    // fTexcoord = aPos;
    gl_Position = vec4(
        2*(CONST.pos.x + aPos.x * CONST.size.x) / CONST.window.x - 1.0,
        2*(CONST.pos.y + aPos.y * CONST.size.y) / CONST.window.y - 1.0,
        0.0, 1.0);
}

#fragment
#version 450

layout (location = 0) out vec4 FragColor;

struct Constants {
    vec4 color;
    vec2 window;
    vec2 pos;
    vec2 size;
};

#ifdef VULKAN
    layout(push_constant)
    uniform constants {
        vec4 color;
        vec2 window;
        vec2 pos;
        vec2 size;
    } CONST;
#else
    uniform Constants CONST;
#endif


void main()
{
    vec4 result = CONST.color;
    // vec4 result = vec4(1);
    // result *= texture(uSampler, fTexcoord);
    // result *= vec4(fTexcoord,0,1);
    FragColor = result;
} 