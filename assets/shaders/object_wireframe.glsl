#vertex
#version 450

layout (location = 0) in vec3 vPos;


struct Constants {
    mat4 uTransform;
    mat4 uProjection;
    vec3 wireframe_color;
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
	mat4 transform = CONST.uTransform;
	vec3 fPos = vec3(transform * vec4(vPos,1));
	
	gl_Position = CONST.uProjection * vec4(fPos,1);
}

#fragment
#version 450

layout (location = 0) out vec4 FragColor;

struct Constants {
    mat4 uTransform;
    mat4 uProjection;
    vec3 wireframe_color;
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

void main() {
	FragColor = vec4(CONST.wireframe_color, 1);
}
