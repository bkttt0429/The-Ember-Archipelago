shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords, depth_prepass_alpha;

uniform sampler2D swe_texture; // R=Height
uniform float swe_strength = 2.0;
uniform vec2 sea_size = vec2(40.0, 40.0);

// Wave Parameters
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.5);
uniform float wave_steepness = 0.2;
uniform float wave_length = 10.0;
uniform float wave_chaos = 0.5; // Randomness factor

uniform vec4 color_deep : source_color = vec4(0.05, 0.25, 0.45, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.3, 0.7, 0.9, 1.0);
uniform vec4 color_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float absorption_coeff = 1.2;
uniform float foam_threshold = 0.4;
uniform float foam_thickness = 0.4;
uniform float refraction_strength = 0.03;
uniform bool debug_show_markers = false;

uniform sampler2D foam_noise : repeat_enable; // Pass a noise texture for stylized foam

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_foam;

// Gerstner Wave Function
vec3 gerstner_wave(vec3 pos, float time, vec2 dir, float length, float steepness, float speed, inout vec3 tangent, inout vec3 binormal) {
    float k = 2.0 * PI / length;
    float c = sqrt(9.81 / k) * speed;
    vec2 d = normalize(dir);
    float f = k * (dot(d, pos.xz) - c * time);
    float a = steepness / k;

    tangent += vec3(
        -d.x * d.x * (steepness * sin(f)),
        d.x * (steepness * cos(f)),
        -d.x * d.y * (steepness * sin(f))
    );
    binormal += vec3(
        -d.x * d.y * (steepness * sin(f)),
        d.y * (steepness * cos(f)),
        -d.y * d.y * (steepness * sin(f))
    );

    return vec3(
        d.x * (a * cos(f)),
        a * sin(f),
        d.y * (a * cos(f))
    );
}

// Chaotic Wave Accumulator (8 Layers + Procedural Noise)
vec3 get_waves_disp(vec3 pos, float t, inout vec3 tangent, inout vec3 binormal) {
    vec3 disp = vec3(0.0);
    
    // Wave parameters (Length, Steepness, Speed, Direction Angle)
    float wave_data[32] = float[](
        wave_length,       wave_steepness, 1.0, 0.0,
        wave_length * 1.3, wave_steepness * 0.7, 0.8, 1.1,
        wave_length * 0.6, wave_steepness * 0.9, 1.5, 2.4,
        wave_length * 0.3, wave_steepness * 1.2, 2.1, -0.6,
        wave_length * 2.1, wave_steepness * 0.4, 0.6, 4.3,
        wave_length * 0.8, wave_steepness * 0.8, 1.3, -1.2,
        wave_length * 0.45, wave_steepness * 1.0, 1.9, 5.2,
        wave_length * 1.7, wave_steepness * 0.3, 0.5, 0.7
    );

    float base_angle = atan(wind_dir.y, wind_dir.x);

    for (int i = 0; i < 8; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx];
        float w_steep = wave_data[idx+1] * wind_strength;
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * wave_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        disp += gerstner_wave(pos, t, d, w_len, w_steep, w_speed, tangent, binormal);
    }
    
    // Extra Micro-Chaos Noise
    float noise = sin(pos.x * 2.0 + t) * cos(pos.z * 2.0 - t * 0.5) * 0.2;
    disp.y += noise * wind_strength * wave_chaos;
    
    return disp;
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // 1. SWE Ripple Displacement
    vec2 uv = (world_pos.xz / sea_size) + 0.5;
    vec4 swe_sample = texture(swe_texture, uv);
    float swe_h = swe_sample.r;
    float is_obstacle = swe_sample.b;
    
    // 2. Chaotic Wave Displacement
    float t = TIME;
    vec3 tangent = vec3(1.0, 0.0, 0.0);
    vec3 binormal = vec3(0.0, 0.0, 1.0);
    
    vec3 wave_disp = get_waves_disp(world_pos, t, tangent, binormal);
    
    float wave_weight = 1.0 - is_obstacle;
    VERTEX.xyz += wave_disp * wave_weight;
    VERTEX.y += swe_h * swe_strength * wave_weight;
    
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_height = VERTEX.y;
    
    // Analytical Normal calculation
    v_normal = normalize(cross(binormal, tangent));
    
    // Foam intensity based on total wave vertical push
    v_foam = clamp(wave_disp.y * 2.5 - foam_threshold, 0.0, 1.0);
}

void fragment() {
    // 1. Robust Depth Reconstruction (Using NDC for maximum compatibility)
    float depth_raw = texture(depth_texture, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
    vec4 view_pos_raw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_pos_raw.xyz /= view_pos_raw.w;
    
    // Distance from camera to underwater geometry
    float geom_dist = length(view_pos_raw.xyz);
    // Distance from camera to water surface
    float surface_dist = length(VERTEX);
    
    // Distance mapping
    float water_depth = max(geom_dist - surface_dist, 0.0);
    
    // 2. Beer's Law (Smooth Transition)
    float absorption = exp(-water_depth * absorption_coeff);
    vec3 deep = color_deep.rgb;
    vec3 shallow = color_shallow.rgb;
    vec3 sea_color = mix(deep, shallow, absorption);
    
    // 3. Normal & Fresnel
    vec3 normal = normalize(v_normal);
    float fresnel = pow(1.0 - clamp(dot(normal, VIEW), 0.0, 1.0), 4.0);
    
    // 4. Stylized Foam System
    float shore_mask = clamp(1.0 - water_depth / foam_thickness, 0.0, 1.0);
    
    // Stylized Noise-based Foam (Two layers)
    vec2 foam_uv = v_world_pos.xz * 0.5;
    float n1 = texture(foam_noise, foam_uv + TIME * 0.05).r;
    float n2 = texture(foam_noise, foam_uv * 1.5 - TIME * 0.08).r;
    float combined_noise = (n1 + n2) * 0.5;
    
    // Shoreline "Crust"
    float shore_foam = smoothstep(0.4, 0.6, shore_mask + combined_noise * 0.2) * shore_mask;
    
    // Wave Crest "Spray"
    float crest_foam = smoothstep(0.5, 0.8, v_foam + combined_noise * 0.1) * 0.8;
    
    float final_foam = clamp(shore_foam + crest_foam, 0.0, 1.0);
    
    // 5. Refraction (Distorted Screen Sampling)
    vec2 ref_uv_offset = normal.xz * refraction_strength * clamp(water_depth, 0.0, 0.3);
    vec2 ref_uv = SCREEN_UV + ref_uv_offset;
    vec3 ref_color = texture(screen_texture, ref_uv).rgb;
    
    // 6. FINAL SHADING
    vec3 color = mix(ref_color, sea_color, 1.0 - absorption * 0.4);
    
    // Add Ripple Warning Color (Visual Feedback for interaction)
    vec2 swe_uv = (v_world_pos.xz / sea_size) + 0.5;
    float ripple_h = texture(swe_texture, swe_uv).r;
    if (abs(ripple_h) > 0.1) {
        color = mix(color, vec3(0.6, 1.0, 1.0), abs(ripple_h) * 5.0); // Bright Cyan Highlight
    }
    
    // OPACITY FIX: Fade water out at the very edge to avoid blocky intersections
    float edge_fade = clamp(water_depth * 10.0, 0.0, 1.0);
    
    // Blend foam
    color = mix(color, color_foam.rgb, final_foam);
    
    // 7. Debug Markers (Observe motion)
    if (debug_show_markers) {
        // Red dots at resting grid positions
        vec2 grid = fract(v_world_pos.xz * 1.0); 
        float dist = length(grid - 0.5);
        if (dist < 0.05) {
            color = mix(color, vec3(1.0, 0.0, 0.0), 0.9);
        }
    }

    ALBEDO = color;
    ALPHA = edge_fade; // Smoothly fade at intersection
    
    EMISSION = vec3(0.05, 0.1, 0.2) * fresnel * (1.0 - final_foam); 
    EMISSION += vec3(1.0) * pow(fresnel, 12.0) * 0.6; // Very sharp specular sparkle
    
    ROUGHNESS = 0.1;
    SPECULAR = 0.6;
}
