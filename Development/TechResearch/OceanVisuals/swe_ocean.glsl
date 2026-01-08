#[compute]
#version 450

// Local Shallow Water Equations Solver
// Implements Advection and Height-Velocity Integration

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Formats:
// We use RGBA32F for state textures.
// R: Height (h) -> Displacement from water level
// G: Velocity X (u)
// B: Velocity Z (v)
// A: Foam / Turbulence (passive tracer)

// Bindings
layout(set = 0, binding = 0) uniform SimParams {
    float delta_time;
    float grid_size;  // Physical size of the grid (meters)
    float drag;       // Damping factor (e.g., 0.99)
    float gravity;    // e.g., 9.8
    ivec2 texture_size; 
    vec2 offset;      // Smooth scrolling offset (Pixel Snapping)
} params;

// Input: Previous State (Read-only)
layout(set = 0, binding = 1) uniform sampler2D prev_state;

// Output: Current State (Write/Read via ImageLoad/Store)
layout(set = 0, binding = 2, rgba32f) uniform image2D current_state;

// Interactions
struct Interaction {
    vec2 position; // Local position (meters) relative to grid center
    float radius;
    float strength;
};

// Max 16 interactions per frame
layout(set = 0, binding = 3) uniform InteractionParams {
    int count;
    // pad to 16 bytes alignment for std140 if mostly vec4s
    int _pad1; 
    int _pad2;
    int _pad3;
    vec4 items[16]; // x, y (Pos), z (Radius), w (Strength)
} interactions;

// Pass Constants
layout(push_constant) uniform Constants {
    int pass_mode; // 0 = Advection, 1 = Update (Integration)
};

// --- Helper Functions ---

// Bilinear sample from texture (GLSL does this automatically with sampler2D)
vec4 sample_state(vec2 uv) {
    // Boundary check for UV to avoid wrapping artifacts if expected behavior is "open sea"
    // However, clamp_to_edge is usually set in the sampler.
    return texture(prev_state, uv);
}

// --- Pass 0: Advection (Semi-Lagrangian) ---
void pass_advection(ivec2 id) {
    vec2 uv = (vec2(id) + 0.5) / vec2(params.texture_size);
    vec2 texel_size = 1.0 / vec2(params.texture_size);
    
    // 1. Calculate Sampling Position (Back-Trace)
    // We want the value at 'current_pos' which came from 'old_pos'.
    // Because the grid itself Moved (Snapping), 'current_pos' relative to 'old_grid' is 'uv + offset'.
    vec2 world_uv = uv + params.offset;
    
    // To do semi-lagrangian advection, we need velocity at the source.
    // Start with velocity at current guessed position.
    vec4 val_at_pos = texture(prev_state, world_uv);
    vec2 velocity = val_at_pos.gb; // u, v
    
    // Backtrace: pos_old = pos_new - velocity * dt
    // Convert velocity (meters/sec) to UV space per second.
    // grid_size is width in meters. texture_size is width in pixels.
    // uv_vel = vel / grid_size
    vec2 uv_velocity = velocity / params.grid_size;
    
    // Advect Backwards
    vec2 advected_uv = world_uv - uv_velocity * params.delta_time;
    
    // 2. Sample from previous state at advected position
    vec4 advected_val = texture(prev_state, advected_uv);
    
    // Decay/Damping happens here or in update pass. 
    // Let's keep advection pure transport.
    
    // Handle "Fresh" Water (simulating infinite ocean)
    // If we trace back outside the texture, we assume rest state (h=0, vel=0)
    // Actually, sampler with CLAMP_TO_EDGE might stretch edge values.
    // Simple check:
    if (advected_uv.x < 0.0 || advected_uv.x > 1.0 || advected_uv.y < 0.0 || advected_uv.y > 1.0) {
       advected_val = vec4(0.0);
    }
    
    imageStore(current_state, id, advected_val);
}

// --- Pass 1: Integration (SWE Update) ---
void pass_update(ivec2 id) {
    // Current state here actually contains the RESULT of Pass 0 (Advected State).
    // Because we ping-ponged or we are reading from the output of the previous dispatch?
    // NOTE: In the GDScript logic:
    // Pass 1: Advection (Read T0 -> Write T1)
    // Pass 2: Update (Read T1 -> Write T0)
    // So 'prev_state' binding here points to 'Advected State' (T1) when we are in Update Pass (Writing T0).
    
    vec2 uv = (vec2(id) + 0.5) / vec2(params.texture_size);
    vec2 texel = 1.0 / vec2(params.texture_size);
    
    vec4 state = texture(prev_state, uv);
    float h = state.r;
    float u = state.g;
    float v = state.b;
    float foam = state.a;
    
    // Spatial Gradients (Central Difference)
    float h_right = texture(prev_state, uv + vec2(texel.x, 0)).r;
    float h_left  = texture(prev_state, uv - vec2(texel.x, 0)).r;
    float h_up    = texture(prev_state, uv + vec2(0, texel.y)).r;
    float h_down  = texture(prev_state, uv - vec2(0, texel.y)).r;
    
    float u_right = texture(prev_state, uv + vec2(texel.x, 0)).g;
    float u_left  = texture(prev_state, uv - vec2(texel.x, 0)).g;
    float v_up    = texture(prev_state, uv + vec2(0, texel.y)).b;
    float v_down  = texture(prev_state, uv - vec2(0, texel.y)).b;
    
    float dx = params.grid_size / float(params.texture_size.x);
    float dt = min(params.delta_time, 0.05); // Safety Clamp
    
    // --- Apply Interactions ---
    // Calculate local position of current pixel (meters, relative to center)
    // uv (0..1) -> (-0.5 .. 0.5) * grid_size
    vec2 local_pos = (uv - 0.5) * params.grid_size;
    
    for (int i = 0; i < interactions.count; i++) {
        if (i >= 16) break;
        vec4 item = interactions.items[i];
        vec2 pos = item.xy;
        float radius = item.z;
        float strength = item.w;
        
        float dist = distance(local_pos, pos);
        if (dist < radius) {
            // Smooth falloff
            float factor = 1.0 - smoothstep(0.0, radius, dist);
            // Add to height or velocity?
            // "Splash" usually adds height. "Wake" might add velocity.
            // Add to Height for simple splash.
            h += strength * factor * dt * 5.0; 
            
            // Add to Foam (Splash effect)
            foam += abs(strength) * factor * dt * 1.0;
            
            // Optional: Add outward velocity?
            // vec2 dir = normalize(local_pos - pos);
            // u += dir.x * strength * factor * dt;
            // v += dir.y * strength * factor * dt;
        }
    }
    
    // --- Shallow Water Equations ---
    
    // 1. Update Velocity (Momentum Equation)
    // du/dt = -g * dh/dx
    // dv/dt = -g * dh/dy
    
    float dh_dx = (h_right - h_left) / (2.0 * dx);
    float dh_dy = (h_up - h_down) / (2.0 * dx);
    
    u -= params.gravity * dh_dx * dt;
    v -= params.gravity * dh_dy * dt;
    
    // Apply Damping to Velocity
    u *= params.drag;
    v *= params.drag;
    
    // 2. Update Height (Continuity Equation)
    // dh/dt = - h * (du/dx + dv/dy) - (u * dh/dx + v * dh/dy)
    // Linearized term: -H_avg * Divergence
    // We assume dominant H_avg (average water depth) for wave speed.
    // Let's assume average depth D = 10.0m for wave speed c = sqrt(g*D) ~ 10m/s.
    // But for "ripples" on surface, we might want purely divergence based.
    
    // Divergence: du/dx + dv/dy
    float du_dx = (u_right - u_left) / (2.0 * dx);
    float dv_dy = (v_up - v_down) / (2.0 * dx);
    float divergence = du_dx + dv_dy;
    
    // Conservation of Mass term
    // h_new = h_old - D * divergence * dt
    float avg_depth = 2.0; // Tuning parameter for wave speed c^2 = g*D
    // If D is too large, waves move too fast and might explode if CFL condition violated.
    // CFL: dt * c < dx  => dt * sqrt(g*D) < dx
    // dx = 64m / 256 = 0.25m. 
    // If dt=0.016, then sqrt(9.8*D) < 0.25/0.016 = 15.6 => 9.8*D < 244 => D < 24m. 
    // So D=2.0 is safe.
    
    h -= avg_depth * divergence * dt;
    
    // Damping Height (to prevent accumulation of noise)
    h *= 0.999;
    
    // Hard Clamps
    h = clamp(h, -10.0, 10.0);
    u = clamp(u, -20.0, 20.0);
    v = clamp(v, -20.0, 20.0);
    
    // Foam Generation from Compression (Negative Divergence)
    float compression = max(0.0, -divergence - 2.0); // Threshold can be tuned
    foam += compression * dt * 5.0;

    // Foam decay
    foam *= 0.99;
    foam = clamp(foam, 0.0, 1.0);
    
    imageStore(current_state, id, vec4(h, u, v, foam));
}

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= params.texture_size.x || id.y >= params.texture_size.y) return;
    
    if (pass_mode == 0) {
        pass_advection(id);
    } else {
        pass_update(id);
    }
}
