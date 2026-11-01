#vertex
#version 330 core

layout (location = 0) in vec3 vPos;


uniform mat4 uTransform;
uniform mat4 uProjection;

void main()
{
	mat4 transform = uTransform;
	vec3 fPos = vec3(transform * vec4(vPos,1));
	
	gl_Position = uProjection * vec4(fPos,1);
};

#fragment
#version 330 core

out vec4 FragColor;

uniform vec3 wireframe_color;

void main() {
	FragColor = vec4(wireframe_color, 1);
}
