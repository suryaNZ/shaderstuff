#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D output_render;

layout(set = 0, binding = 1, std430) restrict buffer CameraInfo {
    mat4 ProjectionMat;
    mat4 CameraToWorld;
    float Fov;
    float Far;
    float Near;
} 
camera_data;

layout(set = 0, binding = 2, std430) restrict buffer Faces {
    vec3 data[];
} 
faces;
layout(set = 0, binding = 3, std430) restrict buffer InputMaterial {
    vec4 colour[];
    // float smoothness[];
} 
materials;

layout(set = 0, binding = 4, std430) restrict buffer Spheres {
    vec4 data[];
}
spheres;

layout(set = 0, binding = 5, std430) restrict buffer SphereInputMaterial {
    vec4 colour[];
    // float smoothness[];
} 
sphereMaterials;

// structs
struct Ray {
    vec3 origin;
    vec3 dir;
};

struct Material {
    vec4 colour;
};

struct Sphere {
    vec3 pos;
    float r; // radius
};

struct HitInfo {
    bool didHit;
    vec3 pos;
    vec3 normal;    
    float dist;
    vec4 colour;
};



// intersection functions
HitInfo RaySphere(Ray ray, vec3 sphereCentre, float radius, vec4 colour) {
    HitInfo hitinfo;
    hitinfo.didHit = false;
    vec3 rayOffset = ray.origin - sphereCentre;
    // matrix stuff that I do not understand 
    // https://en.wikipedia.org/wiki/Line%E2%80%93sphere_intersection#Calculation_using_vectors_in_3D

    float a = dot(ray.dir, ray.dir);
    float b = 2 * dot(rayOffset, ray.dir);
    float c = dot(rayOffset, rayOffset) - radius * radius;

    float discriminant = b*b - 4*a*c;

    if(discriminant >= 0) {
        float dist = (-b - sqrt(discriminant)) / (2*a);
        if(dist >= 0) {
            hitinfo.didHit = true;
            hitinfo.dist = dist;
            hitinfo.pos = ray.origin + ray.dir * dist;
            hitinfo.normal = normalize(hitinfo.pos - sphereCentre);
            hitinfo.colour = colour;
        }
    }
    return hitinfo;
}







int x, y;
vec2 uv;

void main() {
    x = int(gl_GlobalInvocationID.x);
    y = int(gl_GlobalInvocationID.y);
    ivec2 invocID = ivec2(gl_GlobalInvocationID.xy);
    ivec2 image_size = imageSize(output_render);
    uv = vec2(vec2(invocID) / vec2(image_size));
    uv.y = 1.0 - uv.y;
    float aspect_ratio = float(image_size.x) / float(image_size.y);
    // uv.x *= aspect_ratio;
    
    // if(x*20 < faces.data.length() || y*20 < faces.data.length()) {
        // imageStore(output_render, invocID, materials.colour[0]);
    // } else {
        // imageStore(output_render, invocID, vec4(0,0,0,0));
    // }

    float planeHeight = camera_data.Near * tan(camera_data.Fov * 0.5 * 0.0174532925199) * 2; // the funky number is deg2rad, pi/180

    vec3 viewparams = vec3(
        planeHeight * aspect_ratio,
        planeHeight,
        -camera_data.Near
    );

    vec3 viewPointLocal = vec3(uv-0.5, 1.0) * viewparams;
    vec3 viewPoint = (camera_data.CameraToWorld * vec4(viewPointLocal, 1.0)).xyz;


    Ray ray;
    ray.origin = camera_data.CameraToWorld[3].xyz;
    ray.dir = normalize(viewPoint - ray.origin);

    HitInfo closestHit;
    closestHit.didHit = false;

    for(int i = 0; i < spheres.data.length(); i++) {
        vec4 sphere = spheres.data[i];
        HitInfo thehit = RaySphere(ray, sphere.xyz, sphere.w, sphereMaterials.colour[i]);
        if(!closestHit.didHit || (thehit.didHit && thehit.dist < closestHit.dist)) {
            closestHit = thehit;
        }
    }

    if(closestHit.didHit) {
        imageStore(output_render, invocID, closestHit.colour);
    } else {
        imageStore(output_render, invocID, vec4(1.0,1.0,1.0,1.0));
    }
}