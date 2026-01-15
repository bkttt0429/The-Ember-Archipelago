#version 450

// NewWaterSystem/shaders/compute/water_interaction.glsl
// Shallow Water Equation (SWE) Solver
// R = Height, G = Velocity, B = Obstacle, A = Alpha (fixed 1.0)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D tex_in;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D tex_out;

// Binding 2: Interaction Buffer (Read-Only)
layout(set = 0, binding = 2) readonly buffer InteractionBuffer {
    vec4 interactions[]; // xy=pos, z=accel, w=radius
} interaction_data;

layout(push_constant) uniform Params {
    float dt;
    float damping;
    float propagation_speed;
    int interact_count;
    float rain_intensity;
    float time;
    float sea_size_x;
    float sea_size_z;
} params;

// Simple hash for pseudo-randomness
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

shared float tile[10][10];

void main() {
    ivec2 local_id = ivec2(gl_LocalInvocationID.xy);
    ivec2 global_id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(tex_in);

    // 1. Cooperative Load to Shared Memory
    // Each thread in 8x8 block is responsible for its center cell
    // Some threads load neighbors/corners to fill 10x10 tile
    
    // Center
    tile[local_id.x + 1][local_id.y + 1] = imageLoad(tex_in, global_id).r;

    // Borders
    if (local_id.x == 0) tile[0][local_id.y + 1] = imageLoad(tex_in, ivec2(max(global_id.x - 1, 0), global_id.y)).r;
    if (local_id.x == 7) tile[9][local_id.y + 1] = imageLoad(tex_in, ivec2(min(global_id.x + 1, size.x - 1), global_id.y)).r;
    if (local_id.y == 0) tile[local_id.x + 1][0] = imageLoad(tex_in, ivec2(global_id.x, max(global_id.y - 1, 0))).r;
    if (local_id.y == 7) tile[local_id.x + 1][9] = imageLoad(tex_in, ivec2(global_id.x, min(global_id.y + 1, size.y - 1))).r;

    // Corners
    if (local_id.x == 0 && local_id.y == 0) tile[0][0] = imageLoad(tex_in, ivec2(max(global_id.x - 1, 0), max(global_id.y - 1, 0))).r;
    if (local_id.x == 7 && local_id.y == 0) tile[9][0] = imageLoad(tex_in, ivec2(min(global_id.x + 1, size.x - 1), max(global_id.y - 1, 0))).r;
    if (local_id.x == 0 && local_id.y == 7) tile[0][9] = imageLoad(tex_in, ivec2(max(global_id.x - 1, 0), min(global_id.y + 1, size.y - 1))).r;
    if (local_id.x == 7 && local_id.y == 7) tile[9][9] = imageLoad(tex_in, ivec2(min(global_id.x + 1, size.x - 1), min(global_id.y + 1, size.y - 1))).r;

    barrier();

    if (global_id.x >= size.x || global_id.y >= size.y) return;

    // Sample Center Data (for Velocity/Obstacle)
    vec4 dataC = imageLoad(tex_in, global_id);
    float hC = dataC.r;
    float vC = dataC.g;
    float is_obstacle = dataC.b;
    
    // Safety check for NaN or Inf
    if (isnan(hC) || isinf(hC)) hC = 0.0;
    if (isnan(vC) || isinf(vC)) vC = 0.0;
    
    // Use Shared Memory for Laplacian Neighbors
    float hL = tile[local_id.x][local_id.y + 1];
    float hR = tile[local_id.x + 2][local_id.y + 1];
    float hU = tile[local_id.x + 1][local_id.y];
    float hD = tile[local_id.x + 1][local_id.y + 2];

    // 1. Physics Step
    float laplacian = (hL + hR + hU + hD - 4.0 * hC);
    float accel = laplacian * params.propagation_speed;
    
    float next_v = (vC + accel * params.dt) * params.damping;
    float next_h = hC + next_v * params.dt;

    // 2. Obstacle Reflection
    if (is_obstacle > 0.5) {
        next_h = 0.0;
        next_v = 0.0;
    }

    // 3. Rain System
    if (params.rain_intensity > 0.0) {
        float r = hash(vec2(global_id) + floor(params.time * 60.0));
        if (r < params.rain_intensity * 0.05) {
            next_h += 0.5 * params.dt;
        }
    }

    // 4. User Interaction (Multi-Point)
    if (params.interact_count > 0) {
        vec2 my_pos = vec2(global_id) / vec2(size);
        for (int i = 0; i < params.interact_count; i++) {
            vec4 it = interaction_data.interactions[i];
            vec2 pos = it.xy;
            float strength = it.z;
            float radius = it.w;
            
            float dist = distance(my_pos, pos);
            if (dist < radius && radius > 0.001) {
                float falloff = 1.0 - smoothstep(0.0, radius, dist);
                float gauss = exp(- (dist * dist) / (radius * radius * 0.25));

                if (strength > 1000.0) {
                    // VORTEX MODE
                    float s = strength - 2000.0;
                    next_v += s * gauss * params.dt * 10.0; 
                } else if (strength < -1000.0) {
                    // SUCTION MODE
                    float s = abs(strength) - 2000.0;
                    next_h += s * gauss * params.dt;
                } else {
                    // IMPACT MODE
                    next_h += strength * gauss * params.dt;
                }
            }
        }
    }
    
    // 5. Boundary Absorption (Non-Reflecting Boundary) - REFINED
    int margin_pixels = int(float(size.x) * 0.10); // 10% border (Aggressive)
    
    // Calculate distance to nearest edge in pixels
    float dist_x = min(float(global_id.x), float(size.x - 1 - global_id.x));
    float dist_y = min(float(global_id.y), float(size.y - 1 - global_id.y));
    float dist_edge = min(dist_x, dist_y);
    
    if (dist_edge < float(margin_pixels)) {
        // Normalized distance factor (0.0 at edge, 1.0 at margin start)
        float edge_factor = dist_edge / float(margin_pixels);
        
        // Damping ramp: 1.0 (normal) -> 10.0 (edge)
        float boundary_damping = 1.0 + (1.0 - edge_factor) * 10.0;
        
        next_v *= (1.0 / boundary_damping);
        next_h *= (0.5 + 0.5 * edge_factor); // Reduce height but smoother
        
        // Absolute kill at very edge (2%)
        if (edge_factor < 0.2) {
            next_v *= 0.0;
        }
    }

    // Final Safety Clamp
    next_h = clamp(next_h, -10.0, 10.0);
    next_v = clamp(next_v, -20.0, 20.0);

    // Save to OUTPUT texture
    imageStore(tex_out, global_id, vec4(next_h, next_v, is_obstacle, 1.0));
}
