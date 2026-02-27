#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D output_render;

void main() {
    ivec2 invocID = ivec2(gl_GlobalInvocationID.xy);
    imageStore(output_render, invocID, vec4(invocID.x/1080.0, invocID.y/1080.0, 0.0, 1.0));
}