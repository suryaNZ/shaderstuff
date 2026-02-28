#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D output_render;

layout(set = 0, binding = 1, std430) restrict buffer CameraInfo {
    mat4 ProjectionMat;
    float Fov;
    float Far;
    float Near;    
} 
camera_data;

layout(set = 0, binding = 2, std430) restrict buffer Faces {vec3 faces[];} faces;
layout(set = 0, binding = 3, std430) restrict buffer Albedos {vec4 albedos[];} albedos;

// structs
struct Ray {
    vec3 origin;
    vec3 dir;
};

struct HitInfo {
    bool didHit;
    vec3 pos;
    vec3 normal;    
    float dist;
    vec4 albedo;
};

int x, y;

void main() {
    x = int(gl_GlobalInvocationID.x);
    y = int(gl_GlobalInvocationID.y);
    ivec2 invocID = ivec2(gl_GlobalInvocationID.xy);
    
    // if(x*20 < faces.faces.length() || y*20 < faces.faces.length()) {
    //     imageStore(output_render, invocID, albedos.albedos[0]);
    // } else {
    //     imageStore(output_render, invocID, vec4(0,0,0,0));
    // }
}