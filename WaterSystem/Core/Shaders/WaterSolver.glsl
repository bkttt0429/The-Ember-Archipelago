#version 450

// WaterSystem/Core/Shaders/WaterSolver.glsl
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

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(tex_in);
    if (uv.x >= size.x || uv.y >= size.y) return;

    // Sample Neighbors from INPUT texture
    vec4 dataC = imageLoad(tex_in, uv);
    float hC = dataC.r;
    float vC = dataC.g;
    float is_obstacle = dataC.b;
    
    // Safety check for NaN or Inf
    if (isnan(hC) || isinf(hC)) hC = 0.0;
    if (isnan(vC) || isinf(vC)) vC = 0.0;
    
    float hL = imageLoad(tex_in, uv + ivec2(-1, 0)).r;
    float hR = imageLoad(tex_in, uv + ivec2(1, 0)).r;
    float hU = imageLoad(tex_in, uv + ivec2(0, -1)).r;
    float hD = imageLoad(tex_in, uv + ivec2(0, 1)).r;

    // Boundary conditions
    if (uv.x == 0) hL = hC;
    if (uv.x == size.x - 1) hR = hC;
    if (uv.y == 0) hU = hC;
    if (uv.y == size.y - 1) hD = hC;

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

    // 3. Rain System (Pseudo-Random points)
    if (params.rain_intensity > 0.0) {
        // High frequency check
        float r = hash(vec2(uv) + floor(params.time * 60.0));
        if (r < params.rain_intensity * 0.05) {
            next_h += 0.5 * params.dt;
        }
    }


    // 3. User Interaction (Multi-Point)
    if (params.interact_count > 0) {
        vec2 my_pos = vec2(uv) / vec2(size);
        for (int i = 0; i < params.interact_count; i++) {
            vec4 it = interaction_data.interactions[i];
            vec2 pos = it.xy;
            float strength = it.z;
            float radius = it.w;
            
            // it.w usually stores radius, but we can encode type in strength or a separate buffer.
            // For now, let's use a simple convention:
            // strength > 0 and < 1000: IMPACT
            // strength > 1000: VORTEX (strength - 2000)
            // strength < -1000: SUCTION (abs(strength) - 2000)
            
            float dist = distance(my_pos, pos);
            if (dist < radius && radius > 0.001) {
                float falloff = 1.0 - smoothstep(0.0, radius, dist);
                float gauss = exp(- (dist * dist) / (radius * radius * 0.25));

                if (strength > 1000.0) {
                    // VORTEX MODE
                    float s = strength - 2000.0;
                    vec2 dir = my_pos - pos;
                    vec2 tangent = vec2(-dir.y, dir.x); // Rotation
                    // Apply velocity directly to G channel
                    next_v += s * gauss * params.dt * 10.0; 
                } else if (strength < -1000.0) {
                    // SUCTION MODE
                    float s = abs(strength) - 2000.0;
                    next_h += s * gauss * params.dt;
                } else {
                    // IMPACT MODE (Standard Ripple)
                    next_h += strength * gauss * params.dt;
                }
            }
        }
    }
    
    // Final Safety Clamp
    next_h = clamp(next_h, -10.0, 10.0);
    next_v = clamp(next_v, -20.0, 20.0);

    // Save to OUTPUT texture
    imageStore(tex_out, uv, vec4(next_h, next_v, is_obstacle, 1.0));
}
