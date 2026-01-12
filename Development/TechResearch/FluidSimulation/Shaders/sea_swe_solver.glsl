#version 450

// Shallow Water Equation (SWE) Solver
// R = Height, G = Velocity (Height Change)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform image2D sim_tex;

layout(push_constant) uniform Params {
    float dt;
    float damping;
    float propagation_speed;
    int interact_flag;
    vec2 interact_pos; // 0..1 UV
    float interact_strength;
    float interact_radius;
} params;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(sim_tex);
    if (uv.x >= size.x || uv.y >= size.y) return;

    // Sample Neighbors
    float hC = imageLoad(sim_tex, uv).r;
    float vC = imageLoad(sim_tex, uv).g;
    
    float hL = imageLoad(sim_tex, uv + ivec2(-1, 0)).r;
    float hR = imageLoad(sim_tex, uv + ivec2(1, 0)).r;
    float hU = imageLoad(sim_tex, uv + ivec2(0, -1)).r;
    float hD = imageLoad(sim_tex, uv + ivec2(0, 1)).r;

    // Boundary conditions (simple clamp)
    if (uv.x == 0) hL = hC;
    if (uv.x == size.x - 1) hR = hC;
    if (uv.y == 0) hU = hC;
    if (uv.y == size.y - 1) hD = hC;

    // SWE Physics Step
    // wave acceleration depends on Laplacian of height
    float accel = (hL + hR + hU + hD - 4.0 * hC) * params.propagation_speed;
    
    // Update velocity and height
    float next_v = (vC + accel * params.dt) * params.damping;
    float next_h = hC + next_v * params.dt;

    // Obstacle Logic (B channel stores "Is Obstacle" - 1.0 if land)
    float is_obstacle = imageLoad(sim_tex, uv).b;
    if (is_obstacle > 0.5) {
        next_h = 0.0;
        next_v = 0.0;
    }

    // Mouse Interaction
    if (params.interact_flag > 0) {
        vec2 my_pos = vec2(uv) / vec2(size);
        float dist = distance(my_pos, params.interact_pos);
        if (dist < params.interact_radius) {
            float force = (1.0 - dist / params.interact_radius) * params.interact_strength;
            next_h += force * params.dt;
        }
    }

    imageStore(sim_tex, uv, vec4(next_h, next_v, is_obstacle, 1.0));
}
