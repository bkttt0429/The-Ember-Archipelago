#version 450

// NewWaterSystem/Core/Shaders/Internal/water_solver_maccormack.glsl
// Semi-Lagrangian MacCormack Advection Solver
// High-fidelity advection aiming for low dissipation (vorticity preservation)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Double Buffer: In (Previous State) -> Out (New State)
layout(set = 0, binding = 0, rgba32f) uniform readonly image2D tex_in;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D tex_out;

// Interaction Buffer (Read-Only)
layout(set = 0, binding = 2) readonly buffer InteractionBuffer {
    vec4 interactions[]; // xy=pos, z=strength, w=radius
} interaction_data;

layout(push_constant) uniform Params {
    float dt;
    float damping;
    float propagation_speed; // unused
    int interact_count;
    float rain_intensity;
    float time;
    float sea_size_x;
    float sea_size_z;
    float gravity;     // 9.81
    float base_depth;  // 1.0
    float padding1;
    float padding2;
} params;

// Helpers
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Bilinear Sampling from Image
vec4 sample_bilinear(vec2 uv, vec2 size) {
    vec2 pos = uv * size - 0.5;
    ivec2 base = ivec2(floor(pos));
    vec2 f = fract(pos);
    
    // Clamp coordinates
    ivec2 s = ivec2(size);
    ivec2 p00 = clamp(base, ivec2(0), s - 1);
    ivec2 p10 = clamp(base + ivec2(1, 0), ivec2(0), s - 1);
    ivec2 p01 = clamp(base + ivec2(0, 1), ivec2(0), s - 1);
    ivec2 p11 = clamp(base + ivec2(1, 1), ivec2(0), s - 1);

    vec4 v00 = imageLoad(tex_in, p00);
    vec4 v10 = imageLoad(tex_in, p10);
    vec4 v01 = imageLoad(tex_in, p01);
    vec4 v11 = imageLoad(tex_in, p11);

    return mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
}

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(tex_in);
    if (id.x >= size.x || id.y >= size.y) return;

    // Physical Constants
    float g = (params.gravity > 0.1) ? params.gravity : 9.81;
    float dx = 1.0; // Grid spacing

    // 1. Current State
    vec4 dataC = imageLoad(tex_in, id);
    float hC = dataC.r;
    float huC = dataC.g;
    float hvC = dataC.b;
    float is_obstacle = dataC.a;

    // Obstacle Check
    if (is_obstacle > 0.5) {
        imageStore(tex_out, id, vec4(0, 0, 0, 1));
        return;
    }

    // Velocity Field (u, v)
    float H_total = max(params.base_depth + hC, 0.0001);
    vec2 vel = vec2(huC, hvC) / H_total;

    // 2. MacCormack Advection
    // U_adv = U_n - (U_fwd - U_bwd) / 2 ... roughly speaking
    // Semi-Lagrangian MacCormack:
    // phi_n+1 = phi_n + (phi_star - phi_rev) / 2
    // where phi_star is forward advected, phi_rev is backward from phi_star
    
    vec2 uv = (vec2(id) + 0.5) / vec2(size);
    vec2 dt_vel = vel * params.dt; // Normalized velocity displacement? No, dx=1
    // Pixels displacement:
    vec2 displacement = dt_vel; // Since dx=1, velocity 1.0 means 1 pixel per second? 
    // Wait, grid_res is mapped to sea_size. 
    // cell_size = sea_size / grid_res. 
    // Let's assume dx=1 in simulation space to keep it independent of scale.
    
    // Forward sample (Backtrace in time)
    // Lagrangian: What value lands here? We look BACKWARDS along velocity.
    vec2 coord_back = uv - displacement / vec2(size);
    vec4 phi_n1_hat = sample_bilinear(coord_back, vec2(size));

    // Backward sample (Forward trace from the estimate)
    // Where clearly this value goes?
    vec2 coord_fwd = coord_back + displacement / vec2(size);
    vec4 phi_n_hat = sample_bilinear(coord_fwd, vec2(size));

    // MacCormack Correction
    vec4 phi_final = phi_n1_hat + (dataC - phi_n_hat) * 0.5;

    // Limiter (prevents oscillations extrema)
    // Min/Max of 4-neighborhood + center
    vec4 v_min = dataC;
    vec4 v_max = dataC;
    
    ivec2 offsets[4] = {ivec2(1,0), ivec2(-1,0), ivec2(0,1), ivec2(0,-1)};
    for(int i=0; i<4; i++) {
        vec4 neighbor = imageLoad(tex_in, clamp(id + offsets[i], ivec2(0), size-1));
        v_min = min(v_min, neighbor);
        v_max = max(v_max, neighbor);
    }
    
    phi_final = clamp(phi_final, v_min, v_max);
    
    // Advected quantities
    float h_adv = phi_final.r;
    float hu_adv = phi_final.g;
    float hv_adv = phi_final.b;

    // 3. Pressure / Gravity Step (SWE Source Terms)
    // ∂U/∂t = ... - [0, g∂h/∂x, g∂h/∂y]
    // Use Central Difference for Gradients
    
    float hL = imageLoad(tex_in, clamp(id + ivec2(-1, 0), ivec2(0), size-1)).r;
    float hR = imageLoad(tex_in, clamp(id + ivec2(1, 0), ivec2(0), size-1)).r;
    float hU = imageLoad(tex_in, clamp(id + ivec2(0, -1), ivec2(0), size-1)).r;
    float hD = imageLoad(tex_in, clamp(id + ivec2(0, 1), ivec2(0), size-1)).r;
    
    vec2 grad_h = vec2(hR - hL, hD - hU) / (2.0 * dx);
    
    // Acceleration due to gravity
    vec2 accel = -g * grad_h;
    
    // Momentum Update
    float next_hu = (hu_adv + accel.x * H_total * params.dt) * params.damping;
    float next_hv = (hv_adv + accel.y * H_total * params.dt) * params.damping;
    
    // Height Update (Divergence of Flux)
    // ∂h/∂t + ∂(hu)/∂x + ∂(hv)/∂y = 0
    // We already advected h, now add divergence term? 
    // Or did advection cover it? 
    // In operator splitting: 
    // 1. Advect h, hu, hv.
    // 2. Update velocities with pressure/gravity.
    // 3. Update height with divergence of NEW velocities (or old? usually new for stability).
    
    // Let's use the divergence of the advected velocities
    // Need neighbor velocities. For simplicity, re-sample or just use current cell logic with gathered divergence?
    // Using simple divergence from advected momenta is tricky without a second pass or shared memory.
    // For single-pass shader, we can approximate divergence using current neighbors.
    
    vec4 qL = imageLoad(tex_in, clamp(id + ivec2(-1, 0), ivec2(0), size-1));
    vec4 qR = imageLoad(tex_in, clamp(id + ivec2(1, 0), ivec2(0), size-1));
    vec4 qU = imageLoad(tex_in, clamp(id + ivec2(0, -1), ivec2(0), size-1));
    vec4 qD = imageLoad(tex_in, clamp(id + ivec2(0, 1), ivec2(0), size-1));
    
    // Divergence of Momentum (Mass Conservation)
    // div(hv) approx
    float div_hv = (qR.g - qL.g + qD.b - qU.b) / (2.0 * dx); // Center differencing
    
    float next_h = h_adv - div_hv * params.dt;

    // 4. Interactions (Same as original)
    if (params.interact_count > 0) {
        vec2 my_pos = vec2(id) / vec2(size);
        for (int i = 0; i < params.interact_count; i++) {
            vec4 it = interaction_data.interactions[i];
            float dist = distance(my_pos, it.xy);
            if (dist < it.w && it.w > 0.001) {
                float gauss = exp(-(dist * dist) / (it.w * it.w * 0.25));
                if (it.z > 1000.0) { // Vortex
                    float s = it.z - 2000.0;
                    next_hu += s * gauss * params.dt * 10.0; // Twist? This is linear force. 
                    // To do real twist we need perp vector. 
                    // But keep compatibility for now.
                } else if (it.z < -1000.0) { // Suction
                    next_h += (abs(it.z) - 2000.0) * gauss * params.dt;
                } else { // Impact
                    next_h += it.z * gauss * params.dt;
                }
            }
        }
    }
    
    // 5. Rain
    if (params.rain_intensity > 0.0) {
        float r = hash(vec2(id) + floor(params.time * 60.0));
        if (r < params.rain_intensity * 0.05) {
            next_h += 0.5 * params.dt;
        }
    }

    // 6. Boundary
    int margin = int(float(size.x) * 0.10);
    int dist = min(min(id.x, size.x - 1 - id.x), min(id.y, size.y - 1 - id.y));
    if (dist < margin) {
        float factor = float(dist) / float(margin);
        next_hu *= factor;
        next_hv *= factor;
        next_h *= (0.8 + 0.2 * factor);
    }

    // Output
    imageStore(tex_out, id, vec4(next_h, next_hu, next_hv, is_obstacle));
}
