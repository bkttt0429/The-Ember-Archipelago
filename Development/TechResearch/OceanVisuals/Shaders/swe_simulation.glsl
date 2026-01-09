#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform Params {
    float dt;
    float grid_size;
    float drag;
    float gravity;
    int texture_size_x;
    int texture_size_y;
    vec2 uv_offset;
} params;

// Input Texture (Prev State)
layout(set = 0, binding = 1) uniform sampler2D tex_in;

// Output Image (Current State)
layout(rgba32f, set = 0, binding = 2) uniform image2D img_out;

// Interactions
struct Interaction {
    vec2 pos;
    float radius;
    float strength;
};

layout(set = 0, binding = 3) uniform Interactions {
    int count;
    int pad1;
    int pad2;
    int pad3;
    Interaction items[16];
} interactions;

layout(push_constant) uniform PushConsts {
    int mode; // 0 = Update Velocity, 1 = Update Height
    int apply_shift; // 1 = Apply params.uv_offset
} pc;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(img_out);
    
    if (id.x >= size.x || id.y >= size.y) return;
    
    vec2 uv = (vec2(id) + 0.5) / vec2(size);
    vec2 sample_uv = uv;
    if (pc.apply_shift == 1) {
        sample_uv += params.uv_offset;
    }
    
    if (pc.mode == 0) {
        // --- PASS 1: UPDATE VELOCITY ---
        vec2 texel = 1.0 / vec2(size);
        vec4 c = texture(tex_in, sample_uv);
        vec4 l = texture(tex_in, sample_uv - vec2(texel.x, 0.0));
        vec4 r = texture(tex_in, sample_uv + vec2(texel.x, 0.0));
        vec4 t = texture(tex_in, sample_uv - vec2(0.0, texel.y));
        vec4 b = texture(tex_in, sample_uv + vec2(0.0, texel.y));
        
        // Force from interactions
        float force = 0.0;
        // Interaction pos is local to the grid center. 
        // We need to account for the current uv_offset if we want interactions to stick to world.
        // But interactions are usually instant. Let's just use current pos.
        vec2 world_pos_local = (uv - 0.5) * params.grid_size; 
        
        for (int i=0; i<interactions.count; i++) {
            float dist = distance(world_pos_local, interactions.items[i].pos);
            if (dist < interactions.items[i].radius) {
                force += interactions.items[i].strength * (1.0 - dist/interactions.items[i].radius);
            }
        }

        float dh_dx = (r.r - l.r) * 0.5;
        float dh_dz = (b.r - t.r) * 0.5;
        
        float vx = c.g - dh_dx * params.gravity * params.dt;
        float vz = c.b - dh_dz * params.gravity * params.dt;
        
        // Damping
        vx *= params.drag;
        vz *= params.drag;
        
        // Height stays same in this pass, but we add force here
        float h = c.r + force * params.dt;
        
        imageStore(img_out, id, vec4(h, vx, vz, c.a));
        
    } else {
        // --- PASS 2: UPDATE HEIGHT ---
        vec2 texel = 1.0 / vec2(size);
        // Note: NO SHIFT in Pass 2 because Pass 1 already shifted it into T1
        vec4 c = texture(tex_in, uv);
        vec4 l = texture(tex_in, uv - vec2(texel.x, 0.0));
        vec4 r = texture(tex_in, uv + vec2(texel.x, 0.0));
        vec4 t = texture(tex_in, uv - vec2(0.0, texel.y));
        vec4 b = texture(tex_in, uv + vec2(0.0, texel.y));
        
        // Use updated divergence from tex_in
        float div_v = (r.g - l.g + b.b - t.b) * 0.5;
        float h = c.r - div_v * 10.0 * params.dt; // depth=10
        
        // Damping and clamp
        h *= (1.0 - 0.02 * params.dt); // Lower decay
        h = clamp(h, -10.0, 10.0);
        
        imageStore(img_out, id, vec4(h, c.g, c.b, c.a));
    }
}
