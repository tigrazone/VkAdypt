#version 450
void main() { gl_Position = vec4(vec2((ivec2(gl_VertexIndex << 1, gl_VertexIndex) & 2) << 1) - 1.0, 0.0, 1.0); }
