#version 450

// Ripple Simulation Compute Shader
// Implements shallow water equations for interactive water ripples

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Ping-pong buffers: current and previous wave height
layout(set = 0, binding = 0, r32f) uniform readonly image2D wave_current;
layout(set = 0, binding = 1, r32f) uniform readonly image2D wave_previous;
layout(set = 0, binding = 2, r32f) uniform writeonly image2D wave_next;

// Interaction input from camera viewport
layout(set = 0, binding = 3, rgba8) uniform readonly image2D interaction_mask;

layout(push_constant) uniform Params {
    int resolution;
    float delta_time;
    float wave_speed;
    float damping;
    float interaction_strength;
} params;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    if (uv.x >= params.resolution || uv.y >= params.resolution) return;
    
    // Boundary conditions - edges stay at neutral
    if (uv.x == 0 || uv.y == 0 || 
        uv.x == params.resolution - 1 || uv.y == params.resolution - 1) {
        imageStore(wave_next, uv, vec4(0.5));
        return;
    }
    
    // Load current and neighboring heights
    float c = imageLoad(wave_current, uv).r;
    float l = imageLoad(wave_current, uv + ivec2(-1, 0)).r;
    float r = imageLoad(wave_current, uv + ivec2(1, 0)).r;
    float u = imageLoad(wave_current, uv + ivec2(0, -1)).r;
    float d = imageLoad(wave_current, uv + ivec2(0, 1)).r;
    
    // Previous height for wave equation
    float prev = imageLoad(wave_previous, uv).r;
    
    // Laplacian for wave propagation
    float laplacian = (l + r + u + d) / 4.0 - c;
    
    // Wave equation: h_new = 2*h_current - h_previous + c^2 * dt^2 * laplacian
    float c2_dt2 = params.wave_speed * params.wave_speed * params.delta_time * params.delta_time;
    float new_height = 2.0 * c - prev + c2_dt2 * laplacian;
    
    // Damping
    float neutral = 0.5;
    new_height = neutral + (new_height - neutral) * params.damping;
    
    // Add interaction impulse from objects touching water
    vec4 interaction = imageLoad(interaction_mask, uv);
    float interact_value = interaction.r * params.interaction_strength;
    if (interact_value > 0.1) {
        // Create wave peak at interaction point
        new_height = max(new_height, 0.5 + interact_value * 0.3);
    }
    
    // Clamp and store
    new_height = clamp(new_height, 0.0, 1.0);
    imageStore(wave_next, uv, vec4(new_height));
}
