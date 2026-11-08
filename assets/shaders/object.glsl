#vertex
#version 450

layout (location = 0) in vec3 vPos;
layout (location = 1) in vec3 vNormal;
layout (location = 2) in vec2 vTexcoord;

layout (location = 0) out vec3 fPos;
layout (location = 1) out vec3 fLocalPos;
layout (location = 2) out vec3 fNormal;
layout (location = 3) out vec2 fTexcoord;


struct Constants {
    mat4 uTransform;
    mat4 uProjection;
	vec3 diffuse_color;
	int use_diffuseMap;
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
	fPos = vec3(transform * vec4(vPos,1));
	fLocalPos = vPos;
	fNormal = vNormal;
	fTexcoord = vTexcoord;
	
	gl_Position = CONST.uProjection * vec4(fPos,1);
}

#fragment
#version 450

layout (location = 0) in vec3 fPos;
layout (location = 1) in vec3 fLocalPos;
layout (location = 2) in vec3 fNormal;
layout (location = 3) in vec2 fTexcoord;

layout (location = 0) out vec4 FragColor;

struct Constants {
    mat4 uTransform;
    mat4 uProjection;
	vec3 diffuse_color;
	int use_diffuseMap;
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

#ifdef VULKAN
	layout(set = 0, binding = 0) uniform sampler2D diffuse_map;
#else
	uniform sampler2D diffuse_map;
#endif


// Deterministic 3D hash
float hash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth 3D value noise
float noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);

    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash(i + vec3(0, 0, 0));
    float n100 = hash(i + vec3(1, 0, 0));
    float n010 = hash(i + vec3(0, 1, 0));
    float n110 = hash(i + vec3(1, 1, 0));
    float n001 = hash(i + vec3(0, 0, 1));
    float n101 = hash(i + vec3(1, 0, 1));
    float n011 = hash(i + vec3(0, 1, 1));
    float n111 = hash(i + vec3(1, 1, 1));

    float x00 = mix(n000, n100, f.x);
    float x10 = mix(n010, n110, f.x);
    float x01 = mix(n001, n101, f.x);
    float x11 = mix(n011, n111, f.x);

    float y0 = mix(x00, x10, f.y);
    float y1 = mix(x01, x11, f.y);

    return mix(y0, y1, f.z);
}



void main() {
	vec3 normal = normalize(fNormal);
	vec3 result = vec3(1);
	if (CONST.use_diffuseMap == 1) {
		result *= texture(diffuse_map, fTexcoord).rgb;
	} else {
		float n1 = noise(fPos * 3.0);
		float n2 = noise(fPos * 12.0);
		float variation = 0.96 + n1 * 0.06 + n2 * 0.02;

		float edgeDistance;
		if (abs(fNormal.x) > 0.5) {
			edgeDistance = min(0.5 - abs(fLocalPos.y),
							0.5 - abs(fLocalPos.z));
		} else if (abs(fNormal.y) > 0.5) {
			edgeDistance = min(0.5 - abs(fLocalPos.x),
							0.5 - abs(fLocalPos.z));
		} else {
			edgeDistance = min(0.5 - abs(fLocalPos.x),
							0.5 - abs(fLocalPos.y));
		}

		float edge = 1.0 - smoothstep(0.0, 0.025, edgeDistance);
		vec3 color = CONST.diffuse_color * variation;
		color *= 1.0 - edge * 0.15;
		result = color;
	}
	
	FragColor = vec4(result, 1);
}