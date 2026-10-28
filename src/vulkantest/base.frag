
#version 450 core

layout(location = 0) out vec4 outFragColor;

layout(location = 0) in vec3 fColor;

void main() {
    outFragColor = vec4(fColor, 1.0);
} 

// layout(location = 0) out vec4 outFragColor;

// void main() {
//     outFragColor = vec4(1.0, 0.0, 0.0, 1.0);
// } 