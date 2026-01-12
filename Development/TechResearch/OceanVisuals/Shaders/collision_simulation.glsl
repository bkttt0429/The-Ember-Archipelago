#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Binding 0: Sim Data (R=Height, G=VelX, B=VelY, A=Unused)
layout(rgba32f, binding = 0) uniform readonly image2D sim_tex_in;
// Binding 1: Concentration Data (R=ConcA, G=ConcB, B=Unused, A=Unused)
layout(rgba32f, binding = 1) uniform readonly image2D conc_tex_in;

layout(rgba32f, binding = 2) uniform writeonly image2D sim_tex_out;
layout(rgba32f, binding = 3) uniform writeonly image2D conc_tex_out;

layout(push_constant) uniform PushConstants {
    int mode; // 0: Velocity, 1: Height + Advection
    float dt;
    vec2 padding;
} pc;

layout(std430, binding = 4) buffer Params {
    float grid_size;
    float drag;
    float gravity;
    float pad1;
    vec2 texture_size;
    vec2 uv_offset;
} params;

struct Interaction {
    vec2 pos;
    float radius;
    float strength;
    float color_a;
    float color_b;
    float pad1;
    float pad2;
};

layout(std430, binding = 5) buffer Interactions {
    int count;
    int pad1;
    int pad2;
    int pad3;
    Interaction items[];
} interactions;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    if (float(uv.x) >= params.texture_size.x || float(uv.y) >= params.texture_size.y) return;

    // --- Safety Margin ---
    // Zero out edges to prevent advection leaking garbage
    if (uv.x <= 1 || uv.x >= int(params.texture_size.x)-2 || uv.y <= 1 || uv.y >= int(params.texture_size.y)-2) {
        imageStore(sim_tex_out, uv, vec4(0.0));
        imageStore(conc_tex_out, uv, vec4(0.0));
        return;
    }

    // Load Data
    vec4 sim_data = imageLoad(sim_tex_in, uv);
    vec4 conc_data = imageLoad(conc_tex_in, uv);
    
    // Clamp to avoid NaNs
    float h = clamp(sim_data.r, -20.0, 20.0);
    vec2 v = clamp(sim_data.gb, vec2(-50.0), vec2(50.0));
    
    // Read Concentrations from R/G of conc_texture
    float concA = conc_data.r;
    float concB = conc_data.g;

    float dx = params.grid_size / params.texture_size.x;

    if (pc.mode == 0) {
        // --- Pass 1: Velocity Update (SWE) ---
        // dh/dx, dh/dy
        float h_r = imageLoad(sim_tex_in, uv + ivec2(1, 0)).r;
        float h_l = imageLoad(sim_tex_in, uv - ivec2(1, 0)).r;
        float h_t = imageLoad(sim_tex_in, uv + ivec2(0, 1)).r;
        float h_b = imageLoad(sim_tex_in, uv - ivec2(0, 1)).r;

        vec2 grad_h;
        grad_h.x = (h_r - h_l) / (2.0 * dx);
        grad_h.y = (h_t - h_b) / (2.0 * dx);
        
        // v_new = v_old - dt * g * grad_h
        v -= pc.dt * params.gravity * grad_h;
        v *= (1.0 - params.drag * pc.dt);

        // Calculate Interaction Forces (affecting Velocity)
        vec2 world_pos = (vec2(uv) / params.texture_size - 0.5) * params.grid_size + params.uv_offset;
        for (int i = 0; i < interactions.count; i++) {
            float dist = distance(world_pos, interactions.items[i].pos);
            if (dist < interactions.items[i].radius) {
                float force = (1.0 - dist / interactions.items[i].radius) * interactions.items[i].strength;
                // Add Push force away from center
                vec2 dir = normalize(world_pos - interactions.items[i].pos + vec2(0.001));
                v += dir * force * pc.dt; 
            }
        }

        // Store Updated Velocity, Keep Height, Keep Conc
        imageStore(sim_tex_out, uv, vec4(h, v.x, v.y, 1.0));
        imageStore(conc_tex_out, uv, vec4(concA, concB, 0.0, 1.0));
    } 
    else {
        // --- Pass 2: Height Update & Advection ---
        
        // 1. Height Update (Divergence)
        float v_r = imageLoad(sim_tex_in, uv + ivec2(1, 0)).g;
        float v_l = imageLoad(sim_tex_in, uv - ivec2(1, 0)).g;
        float v_t = imageLoad(sim_tex_in, uv + ivec2(0, 1)).b;
        float v_b = imageLoad(sim_tex_in, uv - ivec2(0, 1)).b;

        float div_v = (v_r - v_l) / (2.0 * dx) + (v_t - v_b) / (2.0 * dx);
        float depth = 10.0; // Mean depth
        h -= pc.dt * depth * div_v;
        
        // 2. Advection (Semi-Lagrangian) of Concentration
        // Backtrace
        vec2 back_uv_coord = vec2(uv) - v * pc.dt * (params.texture_size.x / params.grid_size);
        
        // Bilinear Sample of Concentration Texture
        ivec2 i_uv = ivec2(floor(back_uv_coord));
        vec2 f = fract(back_uv_coord);
        
        // We need to sample conc_tex_in at the backtraced location
        // We use texture size clamping to be safe (though loops handle it?) GLSL imageLoad handles OOB? 
        // Safer to clamp manually or rely on boundary logic.
        
        vec4 c00 = imageLoad(conc_tex_in, i_uv);
        vec4 c10 = imageLoad(conc_tex_in, i_uv + ivec2(1, 0));
        vec4 c01 = imageLoad(conc_tex_in, i_uv + ivec2(0, 1));
        vec4 c11 = imageLoad(conc_tex_in, i_uv + ivec2(1, 1));

        vec4 mixed_c = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
        concA = mixed_c.r;
        concB = mixed_c.g;

        // 3. Apply Interactions (Source Terms for Height & Conc)
        vec2 world_pos = (vec2(uv) / params.texture_size - 0.5) * params.grid_size + params.uv_offset;
        for (int i = 0; i < interactions.count; i++) {
            float dist = distance(world_pos, interactions.items[i].pos);
            if (dist < interactions.items[i].radius) {
                float weight = (1.0 - dist / interactions.items[i].radius);
                
                // Add dyes
                concA += interactions.items[i].color_a * weight * 0.1;
                concB += interactions.items[i].color_b * weight * 0.1;
                
                // Add height displacement directly
                h += weight * interactions.items[i].strength * pc.dt * 0.5;
            }
        }
        
        // Decay / Dissipation
        concA = clamp(concA * 0.995, 0.0, 10.0);
        concB = clamp(concB * 0.995, 0.0, 10.0);
        h = clamp(h * 0.999, -20.0, 20.0); // Damping

        imageStore(sim_tex_out, uv, vec4(h, v.x, v.y, 1.0));
        imageStore(conc_tex_out, uv, vec4(concA, concB, 0.0, 1.0));
    }
}
