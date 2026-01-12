#version 450

// WaterSystem/Core/Shaders/WaterSolver.glsl
// Shallow Water Equation (SWE) Solver
// R = Height, G = Velocity, B = Obstacle, A = Alpha (fixed 1.0)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform image2D sim_tex;

// Binding 1: Interaction Buffer (Read-Only)
layout(set = 0, binding = 1) readonly buffer InteractionBuffer {
    vec4 interactions[]; // xy=pos, z=accel, w=radius
} interaction_data;

layout(push_constant) uniform Params {
    float dt;
    float damping;
    float propagation_speed;
    int interact_count;
} params;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(sim_tex);
    if (uv.x >= size.x || uv.y >= size.y) return;

    // Sample Neighbors
    vec4 dataC = imageLoad(sim_tex, uv);
    float hC = dataC.r;
    float vC = dataC.g;
    float is_obstacle = dataC.b;
    
    // Safety check for NaN or Inf
    if (isnan(hC) || isinf(hC)) hC = 0.0;
    if (isnan(vC) || isinf(vC)) vC = 0.0;
    
    float hL = imageLoad(sim_tex, uv + ivec2(-1, 0)).r;
    float hR = imageLoad(sim_tex, uv + ivec2(1, 0)).r;
    float hU = imageLoad(sim_tex, uv + ivec2(0, -1)).r;
    float hD = imageLoad(sim_tex, uv + ivec2(0, 1)).r;

    // Boundary conditions
    if (uv.x == 0) hL = hC;
    if (uv.x == size.x - 1) hR = hC;
    if (uv.y == 0) hU = hC;
    if (uv.y == size.y - 1) hD = hC;

    // 1. Physics Step
    // Clamp acceleration to prevent explosion
    float laplacian = (hL + hR + hU + hD - 4.0 * hC);
    float accel = laplacian * params.propagation_speed;
    
    float next_v = (vC + accel * params.dt) * params.damping;
    float next_h = hC + next_v * params.dt;

    // 2. Obstacle Reflection
    if (is_obstacle > 0.5) {
        next_h = 0.0;
        next_v = 0.0;
    }

    // 3. User Interaction (Multi-Point)
    if (params.interact_count > 0) {
        vec2 my_pos = vec2(uv) / vec2(size);
        for (int i = 0; i < params.interact_count; i++) {
            vec4 it = interaction_data.interactions[i];
            vec2 pos = it.xy;
            float strength = it.z;
            float radius = it.w;
            
            float dist = distance(my_pos, pos);
            if (dist < radius && radius > 0.001) {
                // Gaussian Impulse: exp(-dist^2 / (radius^2))
                // Smoother than linear, no sharp derivative spikes
                float val = dist / radius;
                float force = exp(-val * val * 4.0) * strength;
                next_h += force * params.dt;
            }
        }
    }
    
    // Final Safety Clamp
    next_h = clamp(next_h, -10.0, 10.0);
    next_v = clamp(next_v, -20.0, 20.0);

    imageStore(sim_tex, uv, vec4(next_h, next_v, is_obstacle, 1.0));
}
