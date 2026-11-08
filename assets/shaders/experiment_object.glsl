#vertex
#version 330 core

layout (location = 0) in vec3 vPos;
layout (location = 1) in vec3 vNormal;
layout (location = 2) in vec2 vTexcoord;


out vec3 fPos;
out vec3 fLocalPos;
out vec3 fNormal;
out vec2 fTexcoord;
// flat out int fMaterial;

out vec4 fPosLightSpace;

uniform mat4 uTransform;
uniform mat4 uProjection;
uniform mat4 uLightSpaceMatrix;

void main()
{
	mat4 transform = uTransform;
	// if(uTransform[0][0]==0){ // do we use instancing?
	// 	transform = mat4(iPos1,iPos2,iPos3,iPos4);
	// }
	fPos = vec3(transform * vec4(vPos,1));
	fLocalPos = vPos;

	// fNormal = fPos-vec3(transform * vec4(vPos-vNormal, 1));
	fNormal = vNormal;

	fTexcoord = vTexcoord;
	// fMaterial = int(vTexture.z);
	fPosLightSpace = uLightSpaceMatrix * vec4(fPos, 1);

	//fNormal = mat3(transpose(inverse(transform)))*vNormal; // Do this on the cpu and pass into the shader via uniform, per vertex. if needed...
	
	gl_Position = uProjection * vec4(fPos,1);
};

#fragment
#version 330 core
out vec4 FragColor;

const int N_POINTLIGHTS = 4;
const int N_SPOTLIGHTS = 4;
const int N_MATERIALS = 8;

uniform int use_diffuseMap;
uniform sampler2D diffuse_map;
uniform vec3 diffuse_color;

struct Material {
	int useMap;
	sampler2D diffuse_map;
	vec3 diffuse_color;
	vec3 specular;
	float shininess;
};
struct DirLight {
	vec3 direction;

	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};
struct PointLight {
	vec3 position;

	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	float constant;
	float linear;
	float quadratic;
};
struct SpotLight {
	vec3 position;
	vec3 direction;

	vec3 ambient;
	vec3 diffuse;
	vec3 specular;

	float cutOff;
	float outerCutOff;
};

uniform PointLight uPointLights[N_POINTLIGHTS];
uniform SpotLight uSpotLights[N_SPOTLIGHTS];
uniform DirLight uDirLight;
uniform ivec3 uLightCount;
uniform vec3 uCameraPos;
uniform Material uMaterials[N_MATERIALS];
uniform sampler2D shadow_map;

in vec3 fPos;
in vec3 fLocalPos;
in vec3 fNormal;
in vec2 fTexcoord;
flat in int fMaterial;
in vec4 fPosLightSpace;


float ShadowBias(float shadow, float bias) {
	return shadow - bias > 0.0 ? 1.0 : 0.0;
}
vec3 CalcPointLight(PointLight light, vec3 normal, vec3 fragPos, vec3 viewDir, float shadow) {
	vec3 lightDir = normalize(light.position - fragPos);

	vec3 ambient = light.ambient;

	float diff = max(dot(normal, lightDir), 0);
	vec3 diffuse = light.diffuse * diff;

	vec3 halfwayDir = normalize(lightDir + viewDir);
	float spec = pow(max(dot(normal, halfwayDir), 0), 64*uMaterials[fMaterial].shininess);
	vec3 specular = light.specular * (spec * uMaterials[fMaterial].specular);
	
	float distance = length(light.position - fragPos);
	float attenuation = 1.0f / (light.constant +
		light.linear * distance +
		light.quadratic * (distance * distance));
	ambient *= attenuation;
	diffuse *= attenuation;
	specular *= attenuation;
	
	//float bias = max(0.05 * (1. - dot(normal, lightDir)), 0.005);
	return (ambient + (1 - shadow) * (diffuse + specular));
}
vec3 CalcDirLight(DirLight light, vec3 normal, vec3 viewDir, float shadow) {
	vec3 lightDir = normalize(-light.direction);

	vec3 ambient = light.ambient; // *color;

	float diff = max(dot(normal, lightDir), 0);
	vec3 diffuse = light.diffuse * diff;// *color;

	vec3 halfwayDir = normalize(lightDir + viewDir);
	float spec = pow(max(dot(normal, halfwayDir), 0), 64* uMaterials[fMaterial].shininess);
	vec3 specular = light.specular * (spec * uMaterials[fMaterial].specular);

	return (ambient + (1-shadow)*(diffuse + specular));
}
vec3 CalcSpotLight(SpotLight light, vec3 normal, vec3 fragPos, vec3 viewDir,float shadow) {
	vec3 lightDir = normalize(light.position - fragPos);

	float theta = dot(lightDir, normalize(-light.direction));

	vec3 ambient = light.ambient;// *color;
	if (theta > light.outerCutOff) {

		float diff = max(dot(normal, lightDir), 0);
		vec3 diffuse = light.diffuse * diff;// * color

		vec3 halfwayDir = normalize(lightDir + viewDir);
		float spec = pow(max(dot(normal, halfwayDir), 0), 64* uMaterials[fMaterial].shininess);
		vec3 specular = light.specular * (spec * uMaterials[fMaterial].specular);

		float epsilon = light.cutOff - light.outerCutOff;
		float intensity = clamp((theta - light.outerCutOff) / epsilon, 0, 1);

		diffuse *= intensity;
		specular *= intensity;
		return (ambient + (1 - shadow) * (diffuse + specular));
	} else {
		return ambient;
	}
}
float ShadowCalculation(vec4 fPosLightSpace) {
	// For different projection matrices
	vec3 projCoords = fPosLightSpace.xyz / fPosLightSpace.w;

	projCoords = projCoords * 0.5 + 0.5;
	if (projCoords.z>1) {
		return 0.0;
	}
	float bias = 0.005;
	float shadow = 0;
	vec2 texelSize = 1.f / textureSize(shadow_map, 0);
	for (int x = -1; x < 2;++x) {
		for (int y = -1; y < 2;++y) {
			float closestDepth = texture(shadow_map, projCoords.xy + vec2(x,y)*texelSize).r;
			shadow += projCoords.z - bias > closestDepth ? 1 : 0;
		}
	}
	
	return shadow/9.0;
	/*
	float closestDepth = texture(shadow_map, projCoords.xy).r;
	shadow = projCoords.z - bias > closestDepth ? 1 : 0;
	return shadow;
	*/
}



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
	// vec3 normal = texture(uMaterials.normal_map, fUV).rgb*fNormal;
	// normal = normalize((normal * 2 - 1));
	vec3 normal = normalize(fNormal);

	vec3 viewDir = normalize(uCameraPos - fPos);
	
	// float shadow = ShadowCalculation(fPosLightSpace);

	// vec3 result = vec3(0.5,0.5,0.5);
	vec3 result = vec3(1);
	// if(uLightCount.x==1)
	// 	result += CalcDirLight(uDirLight, normal, viewDir, 0);
	// for (int i = 0; i < uLightCount.y;i++) {
	// 	result += CalcPointLight(uPointLights[i], normal, fPos, viewDir, 0);
	// }
	// for (int i = 0; i < uLightCount.z; i++) {
	// 	result += CalcSpotLight(uSpotLights[i], normal, fPos, viewDir, 0);
	// }
	if (use_diffuseMap == 1) {
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
		vec3 color = diffuse_color * variation;
		color *= 1.0 - edge * 0.15;
		result = color;
	}
	
	// result *= uMaterials[fMaterial].diffuse_color;
	// if(uMaterials[fMaterial].useMap==1){
	// 	result *= texture(uMaterials[fMaterial].diffuse_map, fUV).rgb;
	// }
	FragColor = vec4(result, 1);

    // FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
    // FragColor = vec4(1.0f, 1.0f, 1.0f, 1.0f);
}