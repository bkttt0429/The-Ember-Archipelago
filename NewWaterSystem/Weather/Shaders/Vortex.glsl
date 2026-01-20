#version 450

// ============================================================================
// Vortex Effect - Compute Shader
// Simulates large ocean vortices (Maelstrom):
// 1. Center funnel depression
// 2. Spiral inward flow
// 3. Edge wave texture
// ============================================================================

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// ============================================================================
// Bindings
// ============================================================================
// SWE height field (Read/Write)
layout(rgba32f, set = 0, binding = 0) uniform image2D swe_height;

// Weather influence map (RGBA = HeightDelta/ForceX/ForceY/DangerLevel)
layout(rgba16f, set = 0, binding = 1) uniform image2D weather_influence;

// Vortex Parameters
layout(std430, set = 0, binding = 2) buffer VortexParams {
    vec2 position;        // Vortex center world pos
    float radius;         // Radius of influence
    float intensity;      // Intensity 0-1
    float rotation_speed; // Rotation speed
    float depth;          // Funnel depth (meters)
    float time;           // Current time (s)
    float world_size;     // Water area size
} params;

// ============================================================================
// Constants
// ============================================================================
const float PI = 3.14159265359;
const float GRAVITY = 9.81;

// Rankine Vortex Model Parameters
const float CORE_RATIO = 0.2; // Core radius ratio where velocity peaks

// ============================================================================
// Main
// ============================================================================
void main() {
    ivec2 grid_pos = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(swe_height);
    
    if (grid_pos.x >= texture_size.x || grid_pos.y >= texture_size.y) {
        return;
    }
    
    // Map texture coords to world pos
    vec2 world_pos = (vec2(grid_pos) / vec2(texture_size)) * params.world_size - params.world_size * 0.5;
    
    // Dist to center
    vec2 to_center = world_pos - params.position;
    float distance = length(to_center);
    
    // Skip if outside influence
    if (distance > params.radius) {
        return;
    }
    
    // ========================================================================
    // Vortex Physics Calculation
    // ========================================================================
    
    // Normalized distance
    float r_norm = distance / params.radius;
    
    // ====== 1. Funnel Height (Lorentzian profile) ======
    float funnel_shape = 1.0 / (1.0 + pow(r_norm / 0.15, 2.0));
    float funnel_depth = funnel_shape * params.depth * params.intensity;
    
    // ====== 2. Spiral Waves ======
    float angle = atan(to_center.y, to_center.x);
    float spiral_arms = 4.0;
    float spiral_phase = spiral_arms * angle + params.rotation_speed * params.time;
    float spiral_waves = sin(spiral_phase + r_norm * 15.0) * exp(-r_norm * 3.0);
    float spiral_height = spiral_waves * params.intensity * 1.2;
    
    // ====== 3. Edge Turbulence ======
    float edge_factor = exp(-pow((r_norm - CORE_RATIO) / 0.05, 2.0));
    float edge_ripples = sin(params.time * 5.0 + r_norm * 40.0) * edge_factor * 0.5;
    
    // ========================================================================
    // Total Displacement
    // ========================================================================
    float current_height = imageLoad(swe_height, grid_pos).r;
    float total_displacement = -funnel_depth + spiral_height + edge_ripples;
    
    // Smooth transition
    float influence = smoothstep(params.radius * 1.0, params.radius * 0.8, distance);
    float new_height = current_height + total_displacement * influence;
    
    // ========================================================================
    // Force Field (Rankine Vortex Model)
    // ========================================================================
    float v_tangent;
    if (r_norm < CORE_RATIO) {
        v_tangent = (r_norm / CORE_RATIO) * params.rotation_speed * params.radius;
    } else {
        v_tangent = (CORE_RATIO / r_norm) * params.rotation_speed * params.radius;
    }
    
    // Tangent direction
    vec2 tangent_dir = vec2(-to_center.y, to_center.x);
    if (length(tangent_dir) > 0.001) {
        tangent_dir = normalize(tangent_dir);
    }
    vec2 velocity = tangent_dir * v_tangent * params.intensity;
    
    // Inward suction
    vec2 inward_dir = -normalize(to_center);
    float suction = (1.0 - r_norm) * params.intensity * 10.0;
    velocity += inward_dir * suction;
    
    // Danger level
    float danger = (1.0 - r_norm) * params.intensity;
    
    // ========================================================================
    // Write Results
    // ========================================================================
    vec4 current_sim = imageLoad(swe_height, grid_pos);
    float total_h = max(new_height + 1.0, 0.01); // 1.0 is default base depth
    vec2 next_mom = velocity * total_h;
    
    imageStore(swe_height, grid_pos, vec4(new_height, next_mom.x, next_mom.y, current_sim.a));
    
    vec4 weather_data = vec4(
        total_displacement, // R: Height delta
        velocity.x,         // G: Force X
        velocity.y,         // B: Force Z
        danger              // A: Danger Level
    );
    imageStore(weather_influence, grid_pos, weather_data);
}

// ============================================================================
// Math Utils
// ============================================================================

vec2 get_velocity_at(vec2 pos) {
    vec2 to_center = pos - params.position;
    float dist = length(to_center);
    float r_norm = dist / params.radius;
    
    if (r_norm > 1.0) return vec2(0.0);
    
    float tangent_vel = (r_norm < 0.2) ? 
        params.rotation_speed * dist :
        params.rotation_speed * params.radius * 0.2 / dist;
    
    float radial_vel = -params.intensity * 5.0 * r_norm * (1.0 - r_norm * r_norm);
    
    vec2 dir = normalize(to_center);
    vec2 tang = vec2(-dir.y, dir.x);
    
    return dir * radial_vel + tang * tangent_vel;
}
