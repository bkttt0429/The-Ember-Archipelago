#version 450

// ============================================================================
// Waterspout Effect - Compute Shader
// Simulates a tornado-like column over water:
// 1. Central uplift (water column)
// 2. Spiral wave patterns
// 3. Edge ripple propagation
// ============================================================================

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// ============================================================================
// Bindings
// ============================================================================
// SWE height field (Read/Write)
layout(rgba32f, set = 0, binding = 0) uniform image2D swe_height;

// Weather influence map (RGBA = HeightDelta/ForceX/ForceY/Intensity)
layout(rgba16f, set = 0, binding = 1) uniform image2D weather_influence;

// Waterspout Parameters
layout(std430, set = 0, binding = 2) buffer WaterspoutParams {
    vec2 position;        // World pos (x, z)
    float radius;         // Influence radius (meters)
    float intensity;      // Intensity 0-1
    float rotation_speed; // Rotation speed (rad/s)
    float time;           // Current time (s)
    float world_size;     // Water area size
    float _padding;
} params;

// ============================================================================
// Constants
// ============================================================================
const float PI = 3.14159265359;
const float GRAVITY = 9.81;

// Structure Parameters
const float CORE_RATIO = 0.15;        // Core radius ratio
const float SPIRAL_ARMS = 3.0;        // Number of spiral arms
const float VERTICAL_VELOCITY = 25.0; // Vertical suction (m/s)

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
    
    if (distance > params.radius) {
        return;
    }
    
    // ========================================================================
    // Force Field Calculation
    // ========================================================================
    
    // Normalized distance
    float r_norm = distance / params.radius;
    
    // ====== 1. Vertical Displacement (Central Lift) ======
    float core_factor = exp(-pow(r_norm / CORE_RATIO, 2.0));
    float vertical_displacement = core_factor * params.intensity * 8.0; // Up to 8m
    
    // ====== 2. Spiral Waves (Rankine Vortex Model) ======
    float angle = atan(to_center.y, to_center.x);
    float spiral_phase = SPIRAL_ARMS * angle + params.rotation_speed * params.time;
    
    // Tangent velocity
    float tangent_velocity;
    if (r_norm < CORE_RATIO) {
        tangent_velocity = (r_norm / CORE_RATIO) * params.rotation_speed * params.radius;
    }
    else {
        tangent_velocity = (CORE_RATIO / r_norm) * params.rotation_speed * params.radius;
    }
    
    // Spiral height modulation
    float spiral_wave = sin(spiral_phase + r_norm * 10.0) * exp(-r_norm * 2.0);
    float spiral_height = spiral_wave * params.intensity * 2.0;
    
    // ====== 3. Edge Ripple (Pressure Wave) ======
    float edge_factor = exp(-pow((r_norm - 0.9) / 0.1, 2.0));
    float edge_wave = sin(params.time * 3.0 + r_norm * 20.0) * edge_factor;
    float edge_height = edge_wave * params.intensity * 1.5;
    
    // ====== 4. Random Turbulence ======
    float noise_phase = fract(sin(dot(world_pos, vec2(12.9898, 78.233))) * 43758.5453);
    float turbulence = (noise_phase - 0.5) * params.intensity * 0.5;
    
    // ========================================================================
    // Total Displacement
    // ========================================================================
    float current_height = imageLoad(swe_height, grid_pos).r;
    float total_displacement = vertical_displacement + spiral_height + edge_height + turbulence;
    
    // Smooth influence
    float influence = smoothstep(params.radius * 1.1, params.radius * 0.9, distance);
    float new_height = current_height + total_displacement * influence;
    
    // ========================================================================
    // Force Field (for ship physics)
    // ========================================================================
    vec2 tangent_dir = vec2(-to_center.y, to_center.x);
    if (length(tangent_dir) > 0.001) {
        tangent_dir = normalize(tangent_dir);
    }
    vec2 tangent_force = tangent_dir * tangent_velocity * params.intensity;
    
    vec2 radial_dir = -normalize(to_center);
    float radial_strength = (1.0 - r_norm) * params.intensity * 15.0; 
    vec2 radial_force = radial_dir * radial_strength;
    
    vec2 total_force = tangent_force + radial_force;
    
    // ========================================================================
    // Write Results
    // ========================================================================
    vec4 current_sim = imageLoad(swe_height, grid_pos);
    float total_h = max(new_height + 1.0, 0.01);
    vec2 next_mom = total_force * total_h;
    
    imageStore(swe_height, grid_pos, vec4(new_height, next_mom.x, next_mom.y, current_sim.a));
    
    vec4 weather_data = vec4(
        total_displacement,    // R: Height delta
        total_force.x,         // G: Force X
        total_force.y,         // B: Force Z
        params.intensity       // A: Intensity tag
    );
    imageStore(weather_influence, grid_pos, weather_data);
    
    // ====== Core Eyewall Effect ======
    if (r_norm > CORE_RATIO * 0.8 && r_norm < CORE_RATIO * 1.2) {
        float eyewall = sin(params.time * 10.0 + angle * 8.0);
        new_height += eyewall * params.intensity * 0.8;
        
        // Re-read current state to be safe (or just use current_sim.a)
        float total_h_eye = max(new_height + 1.0, 0.01);
        vec2 next_mom_eye = total_force * total_h_eye;
        imageStore(swe_height, grid_pos, vec4(new_height, next_mom_eye.x, next_mom_eye.y, current_sim.a));
    }
}

// ============================================================================
// Utilities
// ============================================================================

float perlin_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
    float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
    float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
    float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Vorticity for danger detection
float calculate_vorticity(vec2 pos, vec2 center, float radius) {
    vec2 r = pos - center;
    float dist = length(r);
    if (dist < 0.001) return 0.0;
    
    float r_norm = dist / radius;
    if (r_norm < CORE_RATIO) {
        return params.rotation_speed / CORE_RATIO;
    } else {
        return params.rotation_speed * CORE_RATIO / r_norm;
    }
}
