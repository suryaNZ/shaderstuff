#[compute]
#version 450

const int MAX_BOUNCES = 4;
const vec4 ENVIRONMENT_COLOUR = vec4(0.3,0.3,0.3,0.3);

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
    vec4 emission_colour[];
    float emission_strength[];
    // float smoothness[];
} 
materials;

layout(set = 0, binding = 4, std430) restrict buffer Spheres {
    vec4 data[];
}
spheres;

// layout(set = 0, binding = 5, std430) restrict buffer SphereInputMaterial {
//     vec4 colour[];
//     vec4 emission_colour[];
//     float emission_strength[];
//     // float smoothness[];
// } 
// sphere_materials;

struct Material {
vec4 colour;
vec4 emission_colour;
float emission_strength;
};

layout(set = 0, binding = 5, std430) restrict buffer SphereInputMaterial {
    Material materials[];
} 
sphere_materials;



// structs
struct Ray {
    vec3 origin;
    vec3 dir;
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
    Material material;
};


Material gen_material(vec4 colour, vec4 emission_colour, float emission_strength) {
    Material m;
    m.colour = colour;
    m.emission_colour = emission_colour;
    m.emission_strength = emission_strength;
    return m;
}

// Material gen_material_from_sphereno(int sphereno) {
//     Material m;
//     m.colour = sphere_materials.colour[sphereno];
//     m.emission_colour = sphere_materials.emission_colour[sphereno];
//     m.emission_strength = sphere_materials.emission_strength[sphereno];
//     return m;
// }



// helper functions
// float rand(vec2 co){
//     // taken from https://stackoverflow.com/a/4275343
//     return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
// }

// Used as initial seed to the PRNG.
uint pcg_hash(uint seed) {
uint state = seed * 747796405u + 2891336453u;
uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
return (word >> 22u) ^ word;
}

// Used to advance the PCG state.
uint rand_pcg(inout uint rng_state) {
uint state = rng_state;
rng_state = rng_state * 747796405u + 2891336453u;
uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
return (word >> 22u) ^ word;
}

// Advances the prng state and returns the corresponding random float.
float rand(inout uint state) {
uint x = rand_pcg(state);
state = x;
return float(x) * uintBitsToFloat(0x2f800000u);
}

// float rand(inout uint SEED) {
//     SEED = SEED * 747796405 + 2891336453;
//     uint result = ((SEED >> ((SEED >> 28) + 4)) ^ SEED) * 277803737;
//     result = (result >> 22) ^ result;
//     return result / 4294967295.0;
// }

// intersection functions
HitInfo RaySphere(Ray ray, vec3 sphereCentre, float radius, Material material) {
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
            hitinfo.normal = normalize(sphereCentre - hitinfo.pos);
            hitinfo.material = material;
        }
    }
    return hitinfo;
}


// vec3 randDir(vec2 c1, vec2 c2, vec2 c3) {
//     return vec3(rand(c1), rand(c2), rand(c3));
// }

vec3 randomHemisphereDir(vec3 normal, inout uint SEED) {
    vec3 res = vec3(rand(SEED), rand(SEED), rand(SEED));
    if(dot(res, normal) < 0) res = vec3(0,0,0) - res;
    return normalize(res);
}


vec4 Trace(Ray ray, inout uint SEED) {
    HitInfo hitinfo;
    HitInfo newhitinfo;
    vec4 color = vec4(1,1,1,1);
    vec4 incomingLight = vec4(0,0,0,1); 
    hitinfo.didHit = false;
    for(int i = 0; i < MAX_BOUNCES; i++) {
        for(int sphereno = 0; sphereno < spheres.data.length(); sphereno++) {
            newhitinfo = RaySphere(
                ray, 
                spheres.data[sphereno].xyz, 
                spheres.data[sphereno].w, 
                sphere_materials.materials[sphereno]
                );
            if(!hitinfo.didHit) hitinfo = newhitinfo;
            else if(newhitinfo.dist < hitinfo.dist) hitinfo = newhitinfo;
        }
        if(!hitinfo.didHit) continue;
        ray.origin = hitinfo.pos;
        ray.dir = randomHemisphereDir(hitinfo.normal, SEED);
        vec4 emittedLight = hitinfo.material.emission_colour * hitinfo.material.emission_strength;
        incomingLight += emittedLight * color;
        color *= hitinfo.material.colour;
    }
    // if(!hitinfo.didHit) return ENVIRONMENT_COLOUR;
    incomingLight.w = 1;
    return incomingLight;
    // return normalize(incomingLight);
}


int x, y;
vec2 uv;

int num_rays = 100;

void main() {
    x = int(gl_GlobalInvocationID.x);
    y = int(gl_GlobalInvocationID.y);
    ivec2 invocID = ivec2(gl_GlobalInvocationID.xy);
    ivec2 image_size = imageSize(output_render);
    uv = vec2(vec2(invocID) / vec2(image_size));
    uv.y = 1.0 - uv.y;
    float aspect_ratio = float(image_size.x) / float(image_size.y);

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

    uint SEED = pcg_hash(invocID.x * invocID.x * invocID.y);

    vec4 total_colour = vec4(0,0,0,0);
    for(int i = 0; i < num_rays; i++) {
        total_colour += Trace(ray, SEED);
    }

    imageStore(output_render, invocID, total_colour / num_rays);

    // float a;
    // a = rand(SEED);
    // a = rand(SEED);
    // a = rand(SEED);
    // a = rand(SEED);
    // a = rand(SEED);
    // a = rand(SEED);
    // vec3 b = randomHemisphereDir(vec3(0,0,0), SEED);
    // imageStore(output_render, invocID, vec4(b,1));


    // HitInfo closestHit;
    // closestHit.didHit = false;

    // for(int i = 0; i < spheres.data.length(); i++) {
    //     vec4 sphere = spheres.data[i];
    //     HitInfo thehit = RaySphere(ray, sphere.xyz, sphere.w, sphere_materials.materials[i]);
    //     if(!closestHit.didHit || (thehit.didHit && thehit.dist < closestHit.dist)) {
    //         closestHit = thehit;
    //     }
    // }

    // if(closestHit.didHit) {
    //     imageStore(output_render, invocID, closestHit.material.colour);
    // } else {
    //     imageStore(output_render, invocID, vec4(0.3,0.3,0.3,0.3));
    // }
}