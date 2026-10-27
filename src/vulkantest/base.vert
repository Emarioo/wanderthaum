#version 450

layout (location = 0) in vec2 vPos;
layout (location = 1) in vec3 vColor;

layout (location = 0) out vec3 fColor;


void main() {
    fColor = vColor;
    gl_Position = vec4(vPos, 0, 1.0);
}
