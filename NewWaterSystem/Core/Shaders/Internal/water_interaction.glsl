#version 450

// NewWaterSystem/shaders/compute/water_interaction.glsl
// Upgraded Complete Shallow Water Equation (SWE) Solver
// Based on Lax-Friedrichs scheme for conservation laws
// R = Height (h perturbation)
// G = Momentum X (hu)
// B = Momentum Y (hv)
// A = Obstacle (1.0 = solid, 0.0 = fluid)

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
    float propagation_speed; // No longer used for physics, but kept for compatibility
    int interact_count;
    float rain_intensity;
    float time;
    float sea_size_x;
    float sea_size_z;
    float gravity;     // New: defaults to 9.81
    float base_depth;  // New: defaults to 1.0
    float padding1;    // Alignment to 48 bytes
    float padding2;
} params;

// Simple hash for pseudo-randomness
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Shared memory for height and momentum components
shared vec3 tile[10][10]; // .r=h, .g=hu, .b=hv

void main() {
    ivec2 local_id = ivec2(gl_LocalInvocationID.xy);
    ivec2 global_id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(tex_in);

    // 1. Cooperative Load to Shared Memory (H, HU, HV)
    ivec2 id_c = global_id;
    ivec2 id_l = ivec2(max(global_id.x - 1, 0), global_id.y);
    ivec2 id_r = ivec2(min(global_id.x + 1, size.x - 1), global_id.y);
    ivec2 id_u = ivec2(global_id.x, max(global_id.y - 1, 0));
    ivec2 id_d = ivec2(global_id.x, min(global_id.y + 1, size.y - 1));

    tile[local_id.x + 1][local_id.y + 1] = imageLoad(tex_in, id_c).rgb;

    // Borders
    if (local_id.x == 0) tile[0][local_id.y + 1] = imageLoad(tex_in, id_l).rgb;
    if (local_id.x == 7) tile[9][local_id.y + 1] = imageLoad(tex_in, id_r).rgb;
    if (local_id.y == 0) tile[local_id.x + 1][0] = imageLoad(tex_in, id_u).rgb;
    if (local_id.y == 7) tile[local_id.x + 1][9] = imageLoad(tex_in, id_d).rgb;

    barrier();

    if (global_id.x >= size.x || global_id.y >= size.y) return;

    // 2. Physical Constants
    float g = (params.gravity > 0.1) ? params.gravity : 9.81;
    float H0 = (params.base_depth > 0.01) ? params.base_depth : 1.0;
    float dx = 1.0; // Grid spacing assumption
    float h_eps = 1e-4;

    // 3. Current State
    vec4 dataC = imageLoad(tex_in, global_id);
    float hC = dataC.r;
    float huC = dataC.g;
    float hvC = dataC.b;
    float is_obstacle = dataC.a; // Obstacle moved to Alpha channel

    // 4. Neighbor Samples (Shared Memory)
    vec3 qL = tile[local_id.x][local_id.y + 1];
    vec3 qR = tile[local_id.x + 2][local_id.y + 1];
    vec3 qU = tile[local_id.x + 1][local_id.y];
    vec3 qD = tile[local_id.x + 1][local_id.y + 2];

    // 5. Compute Fluxes (Lax-Friedrichs)
    // Formula: ∂U/∂t + ∂F/∂x + ∂G/∂y = 0
    // U = [h, hu, hv]
    
    // Total Depth H = H0 + h
    float HC = max(H0 + hC, h_eps);
    float HL = max(H0 + qL.x, h_eps);
    float HR = max(H0 + qR.x, h_eps);
    float HU = max(H0 + qU.x, h_eps);
    float HD = max(H0 + qD.x, h_eps);

    // Velocities
    float uC = huC / HC; float vC = hvC / HC;
    float uL = qL.y / HL; float vL = qL.z / HL;
    float uR = qR.y / HR; float vR = qR.z / HR;
    float uU = qU.y / HU; float vU = qU.z / HU;
    float uD = qD.y / HD; float vD = qD.z / HD;

    // Wave Speed c = sqrt(gH)
    float cC = sqrt(g * HC);
    float alphaX = max(abs(uC) + cC, max(abs(uL) + sqrt(g*HL), abs(uR) + sqrt(g*HR)));
    float alphaY = max(abs(vC) + cC, max(abs(vU) + sqrt(g*HU), abs(vD) + sqrt(g*HD)));

    // X-Direction Flux F = [hu, hu^2/H + 0.5gh^2, huv/H]
    vec3 F_L = vec3(qL.y, qL.y * uL + 0.5 * g * qL.x * qL.x, qL.y * vL);
    vec3 F_R = vec3(qR.y, qR.y * uR + 0.5 * g * qR.x * qR.x, qR.y * vR);
    vec3 dF_dx = (F_R - F_L) / (2.0 * dx) - 0.5 * alphaX * (qR - 2.0 * vec3(hC, huC, hvC) + qL) / dx;

    // Y-Direction Flux G = [hv, huv/H, hv^2/H + 0.5gh^2]
    vec3 G_U = vec3(qU.z, qU.y * vU, qU.z * vU + 0.5 * g * qU.x * qU.x);
    vec3 G_D = vec3(qD.z, qD.y * vD, qD.z * vD + 0.5 * g * qD.x * qD.x);
    vec3 dG_dy = (G_D - G_U) / (2.0 * dx) - 0.5 * alphaY * (qD - 2.0 * vec3(hC, huC, hvC) + qU) / dx;

    // 6. Update Rule
    float next_h = hC - params.dt * (dF_dx.x + dG_dy.x);
    float next_hu = (huC - params.dt * (dF_dx.y + dG_dy.y)) * params.damping;
    float next_hv = (hvC - params.dt * (dF_dx.z + dG_dy.z)) * params.damping;

    // 7. Obstacle Interaction
    if (is_obstacle > 0.5) {
        next_h = 0.0;
        next_hu = 0.0;
        next_hv = 0.0;
    }

    // 8. Rain System
    if (params.rain_intensity > 0.0) {
        float r = hash(vec2(global_id) + floor(params.time * 60.0));
        if (r < params.rain_intensity * 0.05) {
            next_h += 0.5 * params.dt;
        }
    }

    // 9. User Interaction (Multi-Point)
    if (params.interact_count > 0) {
        vec2 my_pos = vec2(global_id) / vec2(size);
        for (int i = 0; i < params.interact_count; i++) {
            vec4 it = interaction_data.interactions[i];
            vec2 pos = it.xy;
            float strength = it.z;
            float radius = it.w;
            
            float dist = distance(my_pos, pos);
            if (dist < radius && radius > 0.001) {
                float gauss = exp(- (dist * dist) / (radius * radius * 0.25));

                if (strength > 1000.0) {
                    // VORTEX MODE (Impact to momentum)
                    float s = strength - 2000.0;
                    next_hu += s * gauss * params.dt * 10.0; 
                } else if (strength < -1000.0) {
                    // SUCTION MODE (Height impact)
                    float s = abs(strength) - 2000.0;
                    next_h += s * gauss * params.dt;
                } else {
                    // IMPACT MODE
                    next_h += strength * gauss * params.dt;
                }
            }
        }
    }
    
    // 10. Boundary Absorption (Aggressive Absorption)
    int margin_pixels = int(float(size.x) * 0.10);
    float dist_x = min(float(global_id.x), float(size.x - 1 - global_id.x));
    float dist_y = min(float(global_id.y), float(size.y - 1 - global_id.y));
    float dist_edge = min(dist_x, dist_y);
    
    if (dist_edge < float(margin_pixels)) {
        float edge_factor = dist_edge / float(margin_pixels);
        float boundary_damping = 1.0 + (1.0 - edge_factor) * 10.0;
        
        next_hu *= (1.0 / boundary_damping);
        next_hv *= (1.0 / boundary_damping);
        next_h *= (0.5 + 0.5 * edge_factor);
        
        if (edge_factor < 0.2) {
            next_hu = 0.0;
            next_hv = 0.0;
        }
    }

    // Final Safety Clamp
    next_h = clamp(next_h, -5.0, 5.0);
    next_hu = clamp(next_hu, -10.0, 10.0);
    next_hv = clamp(next_hv, -10.0, 10.0);

    // Save to OUTPUT texture (R=h, G=hu, B=hv, A=is_obstacle)
    imageStore(tex_out, global_id, vec4(next_h, next_hu, next_hv, is_obstacle));
}

