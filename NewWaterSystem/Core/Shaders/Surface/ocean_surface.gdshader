shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, alpha_to_coverage, depth_draw_always;

// Varying for Jacobian (Foam)
varying float v_jacobian;

uniform float peak_sharpness : hint_range(0.1, 4.0) = 1.0;
uniform float sss_strength : hint_range(0.0, 5.0) = 0.5;
uniform vec4 sss_color : source_color = vec4(0.0, 0.6, 0.5, 1.0);

// Inline WaterWaves.gdshaderinc logic for self-containment
// Redundant PI removed

uniform float horizontal_displacement_scale : hint_range(0.0, 1.0) = 0.8;

vec3 gerstner_wave(vec3 pos, float time, vec2 dir, float length, float steepness, float speed, inout vec3 tangent, inout vec3 binormal, inout float jacobian_det) {
    float k = 2.0 * PI / length;
    float c = sqrt(9.81 / k) * speed;
    vec2 d = normalize(dir);
    float f = k * (dot(d, pos.xz) - c * time);
    float a = steepness / k;

    // Nonlinear peak contraction (Trochoidal approximation)
    float h = sin(f);
    float dh_df = cos(f);
    if (peak_sharpness != 1.0) {
        float s = h * 0.5 + 0.5;
        // ✅ Decoupled: Visual height uses pow() for sharpness
        h = pow(max(s, 0.001), peak_sharpness) * 2.0 - 1.0;
        
        // ✅ Tangent: Always use smooth derivative (ignore peak_sharpness pow)
        // This prevents "explosions" where the normal flips instantly between vertices
        dh_df = cos(f); 
    }

    tangent += vec3(
        -d.x * d.x * (steepness * sin(f)),
        d.x * (steepness * dh_df),
        -d.x * d.y * (steepness * sin(f))
    );
    binormal += vec3(
        -d.x * d.y * (steepness * sin(f)),
        d.y * (steepness * dh_df),
        -d.y * d.y * (steepness * sin(f))
    );
    
    // Jacobian Determinant contribution: J *= (1 - k * A * cos(f))
    // k * A = steepness (approximately)
    // This value represents the determinant of the transformation. < 0 means folding.
    jacobian_det *= (1.0 - steepness * cos(f));

    return vec3(
        d.x * (a * cos(f)) * horizontal_displacement_scale,
        a * h,
        d.y * (a * cos(f)) * horizontal_displacement_scale
    );
}

vec3 get_waves_displacement(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, inout vec3 tangent, inout vec3 binormal, int iterations, inout float jacobian_det) {
    vec3 disp = vec3(0.0);
    
    // 8-Layer Wave Data (Multipliers)
    float wave_data[32] = float[](
        1.0, 1.0, 1.0, 0.0,
        1.3, 0.7, 0.8, 1.1,
        0.6, 0.9, 1.5, 2.4,
        0.3, 1.2, 2.1, -0.6,
        2.1, 0.4, 0.6, 4.3,
        0.8, 0.8, 1.3, -1.2,
        0.45, 1.0, 1.9, 5.2,
        1.7, 0.3, 0.5, 0.7
    );

    // ✅ 修正：先計算總能量，再套用能量守恆縮放
    float total_relative_steepness = 0.0;
    for (int i = 0; i < 8; i++) total_relative_steepness += wave_data[i * 4 + 1];
    
    // ✅ 能量守恆：用 sqrt 而非直接乘法
    float global_energy_scale = sqrt(wave_steepness);
    
    float steepness_norm = 1.0;
    // ✅ 修正：使用 global_energy_scale 而非 wave_steepness
    if (global_energy_scale * total_relative_steepness * wind_strength > 0.75) {
        steepness_norm = 0.75 / (global_energy_scale * total_relative_steepness * wind_strength);
    }

    float base_angle = atan(wind_dir.y, wind_dir.x);
    
    // ✅ Safety Clamp for Chaos (Prevent Moiré patterns)
    float safe_chaos = min(wave_chaos, 0.3);

    for (int i = 0; i < iterations; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx] * wave_length;
        
        // wave_data[idx+1] contains relative steepness
        float w_steep = wave_data[idx+1] * global_energy_scale * steepness_norm;
        
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * safe_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        disp += gerstner_wave(pos, t, d, w_len, w_steep, w_speed, tangent, binormal, jacobian_det);
    }
    
    // Fix: Ensure noise is also suppressed when wind is 0
    if (wind_strength > 0.001) {
        float noise = sin(pos.x * 2.0 + t) * cos(pos.z * 2.0 - t * 0.5) * 0.2;
        disp.y += noise * wind_strength * safe_chaos;
    }
    
    return disp;
}
vec3 get_gerstner_normal_analytical(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos) {
    vec3 normal = vec3(0.0, 1.0, 0.0);
    
    float wave_data[32] = float[](
        1.0, 1.0, 1.0, 0.0,
        1.3, 0.7, 0.8, 1.1,
        0.6, 0.9, 1.5, 2.4,
        0.3, 1.2, 2.1, -0.6,
        2.1, 0.4, 0.6, 4.3,
        0.8, 0.8, 1.3, -1.2,
        0.45, 1.0, 1.9, 5.2,
        1.7, 0.3, 0.5, 0.7
    );

    float total_relative_steepness = 0.0;
    for (int i = 0; i < 4; i++) total_relative_steepness += wave_data[i * 4 + 1];
    
    // ✅ 能量守恆縮放
    float global_energy_scale = sqrt(wave_steepness);
    
    float steepness_norm = 1.0;
    if (global_energy_scale * total_relative_steepness * wind_strength > 0.75) {
        steepness_norm = 0.75 / (global_energy_scale * total_relative_steepness * wind_strength);
    }

    float base_angle = atan(wind_dir.y, wind_dir.x);
    
    // ✅ Safety Clamp for Chaos (Analytical)
    float safe_chaos = min(wave_chaos, 0.3);

    for (int i = 0; i < 8; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx] * wave_length;
        
        // Match vertex logic
        float w_steep = wave_data[idx+1] * global_energy_scale * steepness_norm;
        
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * safe_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        float k = 2.0 * PI / w_len;
        float c = sqrt(9.81 / k) * w_speed;
        float f = k * (dot(d, pos.xz) - c * t);
        
        float h_raw = sin(f);
        float dh_df = cos(f);
        if (peak_sharpness != 1.0) {
            float s = h_raw * 0.5 + 0.5;
            // ✅ Decoupled Visuals vs Physics
            // Visual Height: Sharpened
            // Normal/Derivative: Smooth
            // float h_visual = pow(max(s, 0.001), peak_sharpness) * 2.0 - 1.0; 
            
            // We only need the derivative for the normal here. 
            // Previous code calculated h_visual but didn't use it for normal.y (it used h_raw).
            // Let's stick to the decoupled derivative:
            dh_df = cos(f); 
        }
        
        // ✅ Standard Gerstner Normal Accumulation (Robust)
        normal.x -= d.x * (w_steep * dh_df);
        normal.y -= w_steep * h_raw; 
        normal.z -= d.y * (w_steep * dh_df);
    }
    
    // ✅ Simple normalization without complex clamping hacks
    return normalize(vec3(normal.x, 1.0 - normal.y * 0.5, normal.z));
}
// End of inlined logic

uniform sampler2D swe_texture : hint_default_black, filter_linear, repeat_disable; 
uniform sampler2D fft_texture : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D weather_influence : hint_default_black, filter_linear, repeat_disable;
uniform float swe_strength = 2.0;
uniform vec2 sea_size = vec2(40.0, 40.0);
uniform vec3 manager_world_pos = vec3(0.0);

uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.5);
uniform float wave_steepness = 0.2;
uniform float wave_length = 10.0;
uniform float wave_chaos = 0.5; 
uniform vec4 color_deep : source_color = vec4(0.004, 0.016, 0.047, 1.0); 
uniform vec4 color_shallow : source_color = vec4(0.0, 0.73, 0.99, 1.0);  
uniform vec4 color_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float absorption_coeff = 0.5;
uniform float refraction_strength = 0.05;

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.25;
uniform float specular : hint_range(0.0, 1.0) = 0.6;
uniform bool storm_mode = false;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.5;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.4;
uniform float foam_shore_spread = 0.5;
uniform float foam_shore_strength = 1.0;
uniform float foam_crest_spread = 0.2;
uniform float foam_crest_strength = 1.5;
uniform float foam_wake_strength = 1.5;
uniform float foam_jacobian_bias : hint_range(0.0, 1.0) = 0.3;

// Caustics
uniform sampler2D caustics_texture : hint_default_black, repeat_enable;
uniform float caustics_strength : hint_range(0.0, 5.0) = 1.0;
uniform float caustics_scale = 0.5;
uniform float caustics_speed = 0.1;

uniform bool debug_show_markers = false;
uniform bool show_wireframe = false;

uniform sampler2D foam_noise : repeat_enable, hint_default_white; 
uniform sampler2D foam_detail : repeat_enable, hint_default_white;
uniform sampler2D foam_sparkle : repeat_enable, hint_default_white;
uniform sampler2D foam_normal : hint_normal, repeat_enable;
uniform sampler2D normal_map1 : hint_normal, repeat_enable;
uniform sampler2D normal_map2 : hint_normal, repeat_enable;
uniform sampler2D envelope_tex : hint_default_white, filter_linear, repeat_disable;

uniform float normal_scale : hint_range(0.0, 2.0) = 0.7;
uniform float normal_speed : hint_range(0.0, 0.5) = 0.1;
uniform vec4 rogue_wave_data = vec4(0.0, 0.0, 0.0, 1.0); // x,y: pos, z: height, w: width

// === Breaking Wave Uniforms ===
uniform int breaking_wave_count = 0;
uniform vec4 breaking_wave_data[3];  // xyz=pos+height, w=width
uniform vec4 breaking_wave_params[3];  // x=curl, y=break_point, z=state, w=unused

// === Volumetric & Particle Foam ===
uniform sampler2D foam_particle_texture : hint_default_black;
uniform float water_transparency : hint_range(0.0, 1.0) = 0.4;
uniform vec3 water_scatter_color : source_color = vec3(0.1, 0.6, 0.8);
uniform float lod_scale = 1.0;
uniform float physics_time = 0.0;
uniform float render_alpha = 0.0;

uniform float fft_scale = 1.0;
uniform float normal_tile = 10.0;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D flow_map : hint_default_black, filter_linear, repeat_enable;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.5;

uniform float edge_scale : hint_range(0.0, 5.0) = 0.5;
uniform float far_fade_start : hint_range(0.0, 500.0) = 150.0;
uniform float far_fade_max : hint_range(0.0, 1000.0) = 300.0;
uniform bool debug_view = false;
uniform bool debug_mesh_only = false;



// ... (Existing uniforms)
varying vec2 v_swe_uv;
varying vec3 v_wave_normal;
varying vec3 v_world_pos;
varying float v_edge_damp;

// 1D Envelope Sampling for Rogue Wave
float sample_envelope(float dist, float width) {
    float u = clamp((dist / width) * 0.5 + 0.5, 0.0, 1.0);
    return texture(envelope_tex, vec2(u, 0.0)).r;
}

vec3 get_rogue_wave_displacement(vec3 pos, float t, vec3 tangent_in, vec3 binormal_in, inout vec3 tangent, inout vec3 binormal) {
    if (rogue_wave_data.z <= 0.01) return vec3(0.0);
    
    vec2 center = rogue_wave_data.xy;
    float height = rogue_wave_data.z;
    float width = rogue_wave_data.w;
    
    // Project position onto wave direction (assumed simplistic directional for now, or radial?)
    // Making it directional based on wind to match "rogue wave" usually following sea state
    vec2 wave_dir = normalize(wind_dir); 
    
    // Calculate distance along the wave direction relative to the center
    // This makes it a "wall of water" or "long crest"
    float dist_long = dot(pos.xz - center, wave_dir);
    
    // Check lateral distance to limit width? Or infinite wall? Let's limit it.
    float dist_lat = dot(pos.xz - center, vec2(-wave_dir.y, wave_dir.x));
    
    // Combine for a local shape
    if (abs(dist_long) > width || abs(dist_lat) > width * 2.0) return vec3(0.0);
    
    float envelope = sample_envelope(dist_long, width);
    // Lateral falloff
    envelope *= smoothstep(width * 2.0, width, abs(dist_lat));
    
    float disp_y = envelope * height;
    
    // Analytical Normal modification (Corrected gradient calculation)
    // d(Height)/d(Long) for tangent
    
    // ========== 修正：使用更小的 delta 和安全限制 ==========
    float delta = width * 0.01; // ✅ 改為寬度的 1%
    float env_d = sample_envelope(dist_long + delta, width);
    float slope = (env_d - envelope) / delta * height;
    
    // ✅ 限制斜率，防止垂直或倒置
    slope = clamp(slope, -2.0, 2.0); // 限制在 ±2 的安全範圍
    
    // ✅ 平滑的法線，而非突變
    vec3 wave_n = normalize(vec3(-slope * wave_dir.x, 1.0, -slope * wave_dir.y));
    
    // ✅ 只在波峰附近修改切線（避免波谷產生扭曲）
    if (envelope > 0.3) {
        tangent += wave_n * envelope * 0.3;
    }
    // ======================================================
    
    return vec3(0.0, disp_y, 0.0);
}

void vertex() {
	v_swe_uv = (VERTEX.xz / sea_size) + 0.5;
	v_swe_uv = clamp(v_swe_uv, 0.0, 1.0);
	
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float cam_dist = length(world_pos - manager_world_pos); // Or CAMERA_POSITION_WORLD if available
    
	// Sample SWE for displacement
	vec4 swe_sample = texture(swe_texture, v_swe_uv);
	float swe_h = swe_sample.r;
	float is_obstacle = swe_sample.b;
	float wave_weight = 1.0 - is_obstacle;
	
	// Time Interpolation for smooth vertex movement
	float interpolated_time = physics_time + render_alpha * (1.0 / 60.0);
	
    // LOD Strategy
    int iterations = 8;
    if (cam_dist > 150.0 * lod_scale) iterations = 2;
    else if (cam_dist > 50.0 * lod_scale) iterations = 4;

	// Gerstner Waves
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 wave_disp = vec3(0.0);

	// Jacobian accumulator (Determinant initialized to 1.0)
	float j_det = 1.0;

    // Calcluate world position early for damping
    // Note: VERTEX is local. MODEL_MATRIX * VERTEX is world.
    // We already have calculation: vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // Calculate Distance Damping for smooth horizon
    float dist = length(world_pos - CAMERA_POSITION_WORLD);
    float wave_damp = 1.0 - smoothstep(far_fade_start, far_fade_max, dist);
    
    // World Space Edge Damping (Box Projection)
    // Calculate dist from center (manager_world_pos) in XZ plane
    vec2 dist_from_center = abs(world_pos.xz - manager_world_pos.xz);
    vec2 half_size = sea_size * 0.5;
    
    // REFINED:
    // 1. General Fade (Vertical Height + Alpha): 40% margin
    vec2 margin_general = half_size * 0.4;
    vec2 edge_t_gen = smoothstep(half_size - margin_general, half_size, dist_from_center);
    // Cubic smoothing (SmootherStep)
    edge_t_gen = smoothstep(0.0, 1.0, edge_t_gen);
    
    // 2. Horizontal Suppression (Prevent Tearing): 20% margin
    vec2 margin_horizontal = half_size * 0.2;
    vec2 edge_t_hor = smoothstep(half_size - margin_horizontal, half_size, dist_from_center);
    // Cubic smoothing
    edge_t_hor = smoothstep(0.0, 1.0, edge_t_hor);
    
    // Invert signal (1.0 = Center, 0.0 = Edge)
    float edge_damp_gen = (1.0 - edge_t_gen.x) * (1.0 - edge_t_gen.y);
    float edge_damp_hor = (1.0 - edge_t_hor.x) * (1.0 - edge_t_hor.y);
    
    float final_damp = wave_damp * edge_damp_gen;
    float h_damp = edge_damp_hor;
    v_edge_damp = edge_damp_gen; // Pass to fragment for Alpha fade
    
	if (wind_strength > 0.001) {
		// INLINED get_waves_displacement to support LOD variable iterations
        // Using `iterations` variable from LOD logic
		wave_disp = get_waves_displacement(world_pos, interpolated_time, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, tangent, binormal, iterations, j_det);
        
		v_wave_normal = normalize(cross(binormal, tangent));
	} else {
		v_wave_normal = vec3(0.0, 1.0, 0.0);
	}

    // Convert Jacobian Determinant to "Compression Signal" (1.0 - Det)
    // Det < 1.0 -> Compressing
    // Det < 0.0 -> Folding
    // v_jacobian > 1.0 implies folding
    v_jacobian = 1.0 - j_det;
    
    // Add Rogue Wave (Raw)
    vec3 rogue_disp = get_rogue_wave_displacement(world_pos, interpolated_time, tangent, binormal, tangent, binormal);
    wave_disp += rogue_disp;
    
    // FINAL DAMPING APPLICATION (Separated)
    // 1. Horizontal: Aggressive suppression to prevent tearing
    wave_disp.xz *= h_damp;
    // 2. Vertical: Gentle fade for visual smoothnees
    wave_disp.y *= final_damp;
	
	VERTEX.xyz += wave_disp; 
	
	// === Breaking Wave Curl Logic ===
	for (int i = 0; i < breaking_wave_count; i++) {
		vec3 wave_center = breaking_wave_data[i].xyz; // x, height, z
		float b_width = max(breaking_wave_data[i].w, 0.01); // ✅ Safety Force Min Width
		float curl_strength = breaking_wave_params[i].x;
		float break_point = breaking_wave_params[i].y;
		
		// 修正：世界坐標計算
		// Vertex 已經偏移了，這裡使用原始 world_pos (尚未應用 displacement?)
		// 實際上應該基於當前 Vertex 位置？
		// 我們需要相對於波浪中心的偏移。
		// world_pos 是基於初始 VERTEX 的。
		
		vec2 to_wave = world_pos.xz - vec2(wave_center.x, wave_center.z);
		
		vec2 dir_norm = normalize(breaking_wave_params[i].zw);
		// Fallback to wind if zero (shouldn't happen with new logic, but safe)
		if (length(dir_norm) < 0.1) dir_norm = normalize(wind_dir);
		float dist_along = dot(to_wave, dir_norm);
		float dist_across = length(to_wave - dist_along * dir_norm);
		
		if (abs(dist_across) > b_width) continue;
		
		float lateral_fade = smoothstep(b_width, b_width * 0.5, abs(dist_across));
		
		// Envelope (Sech approx)
		float u = clamp(dist_along / b_width * 0.5 + 0.5, 0.0, 1.0);
		float envelope = texture(envelope_tex, vec2(u, 0.0)).r;
		
		// Curl Zone
		// u > break_point triggers forward curl
		float curl_zone = smoothstep(break_point - 0.2, break_point + 0.1, u);
		
		// 1. Base Vertical Rise (The body of the wave)
		float base_rise = envelope * lateral_fade * wave_center.y;
		VERTEX.y += base_rise;
		
		// 2. Curl Displacement (Forward and Down)
		vec3 curl_offset = vec3(
			dir_norm.x * curl_zone * curl_strength * 3.0,
			-curl_zone * curl_strength * 1.5, // Downward curl
			dir_norm.y * curl_zone * curl_strength * 3.0
		);
		
		// Apply curl scaling by height
		VERTEX.xyz += curl_offset * envelope * lateral_fade * wave_center.y * 0.5; 
	}

	VERTEX.y += swe_h * swe_strength * wave_weight * final_damp;
	
	// FFT Displacement (High Frequency) - Tiled
	vec2 fft_uv = (world_pos.xz / sea_size) + 0.5;
	float fft_h = texture(fft_texture, fft_uv).b;
	VERTEX.y += fft_h * wind_strength * wave_weight * fft_scale * final_damp;
	
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 blend_normals(vec3 n1, vec3 n2) {
    return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
}

void fragment() {
	// 1. Depth & Water Color - Using Linear Z Difference for robust Depth Fade
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_raw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_raw.xyz /= view_pos_raw.w;
	
	// Use View-Space Z for depth comparison (Standard Graph method)
	float geometry_z = -view_pos_raw.z;
	float surface_z = -VERTEX.z;
	float water_depth = max(geometry_z - surface_z, 0.0);
	
	// (Debug code moved to end of function to avoid 'return' error)
	
	// Debug override for raw depth check if needed
	// if (debug_view) { water_depth = geometry_z; } 
	
	float absorption = exp(-water_depth * absorption_coeff);
	// Only use color_shallow via mixing in shallow water; deep water is always color_deep
	// Always allow color transition based on absorption
	
	// === Volumetric Transparency ===
	// Make shallow water more transparent
	float transparency = mix(water_transparency, 0.1, smoothstep(0.0, 5.0, water_depth));
	
	// Volumetric Scatter (Fake SSS inside wave volume)
	float wave_thickness = max(0.0, v_world_pos.y - manager_world_pos.y);
	vec3 scattered_light = water_scatter_color * exp(-wave_thickness * 0.3);
	
	vec3 sea_color = mix(color_deep.rgb, color_shallow.rgb, absorption);
	
	// Apply scatter to base color (simulate light inside wave)
	sea_color += scattered_light * 0.2;
	
	// 2. Sample Weather Influence
	vec4 weather_data = texture(weather_influence, v_swe_uv);
	float weather_danger = weather_data.a;
	sea_color = mix(sea_color, sea_color * 0.3, clamp(weather_danger * 2.0, 0.0, 1.0));
	
	// 3. Per-Pixel Normal Reconstruction (Ripples)
    vec2 ts = 1.0 / vec2(textureSize(swe_texture, 0));
    float h_r = texture(swe_texture, v_swe_uv + vec2(ts.x, 0.0)).r;
    float h_l = texture(swe_texture, v_swe_uv - vec2(ts.x, 0.0)).r;
    float h_d = texture(swe_texture, v_swe_uv + vec2(0.0, ts.y)).r;
    float h_u = texture(swe_texture, v_swe_uv - vec2(0.0, ts.y)).r;
    
    vec3 ripple_n_offset = vec3(h_l - h_r, 0.0, h_u - h_d) * swe_strength * 2.0;
	
	// Weather Normal Reconstruction
	float w_r = texture(weather_influence, v_swe_uv + vec2(ts.x, 0.0)).r;
	float w_l = texture(weather_influence, v_swe_uv - vec2(ts.x, 0.0)).r;
	float w_d = texture(weather_influence, v_swe_uv + vec2(0.0, ts.y)).r;
	float w_u = texture(weather_influence, v_swe_uv - vec2(0.0, ts.y)).r;
	vec3 weather_n_offset = vec3(w_l - w_r, 0.0, w_u - w_d) * 2.0;

	// Normal System - Hybrid Analytical + Textures
	// ✅ Normal System - 多層次平滑策略
	vec3 base_normal = v_wave_normal;
	
	// 🔧 Analytical Normal - 漸進式混合
	float wave_height_factor = clamp(v_world_pos.y / max(wave_length * 0.2, 0.5), 0.0, 1.0);
	if (wave_height_factor > 0.1 || storm_mode) {
		float interpolated_time = physics_time + render_alpha * (1.0 / 60.0);
		vec3 analytical_n = get_gerstner_normal_analytical(v_world_pos, interpolated_time, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos);
		
		// ✅ 使用雙重平滑
		float smooth_transition = smoothstep(0.2, 0.8, wave_height_factor); // 更寬範圍
		float mix_weight = mix(0.3, 0.7, smooth_transition); // 降低最大權重（原0.85→0.7）
		
		// ✅ 額外的邊緣衰減（防止網格邊界突變）
		mix_weight *= v_edge_damp; // 利用已有的邊緣衰減
		
		base_normal = normalize(mix(base_normal, analytical_n, mix_weight));
	}

	// ✅ Ripple/Weather - 限制振幅避免過度貢獻
	vec3 controlled_ripple = ripple_n_offset * clamp(swe_strength * 0.5, 0.0, 1.5);
	vec3 controlled_weather = weather_n_offset * clamp(weather_danger * 1.5, 0.0, 2.0);
	
	vec3 normal = normalize(base_normal + controlled_ripple + controlled_weather);
	
	// Detail Normals - Dual Sampling Anti-Tiling OR Flow Mapping
	vec3 detail_normal;
    // Flow Map Logic
    	vec2 flow_uv = v_world_pos.xz / sea_size + 0.5;
    	vec2 flow_vector = (texture(flow_map, flow_uv).rg * 2.0 - 1.0) * flow_strength;
    	
    	if (length(flow_vector) > 0.01) {
    		float flow_phase0 = fract(TIME * flow_speed);
    		float flow_phase1 = fract(TIME * flow_speed + 0.5);
    		float flow_lerp = abs(0.5 - flow_phase0) / 0.5;
    		
    		vec2 flow_uv1 = v_world_pos.xz * normal_tile * 0.1 - flow_vector * flow_phase0;
    		vec2 flow_uv2 = v_world_pos.xz * normal_tile * 0.1 - flow_vector * flow_phase1;
    		
    		vec3 f_n1 = texture(normal_map1, flow_uv1).rgb * 2.0 - 1.0;
    		vec3 f_n2 = texture(normal_map1, flow_uv2).rgb * 2.0 - 1.0;
    		
    		detail_normal = normalize(mix(f_n1, f_n2, flow_lerp));
    	} else {
    		// Original Dual Sampling Anti-Tiling
    		vec2 normal_uv1 = v_world_pos.xz * normal_tile * 0.1;
    		vec2 normal_uv2 = v_world_pos.zx * normal_tile * 0.11 + vec2(TIME * 0.05, -TIME * 0.03); 
    		
    		vec3 n1_a = texture(normal_map1, normal_uv1 + TIME * normal_speed).rgb * 2.0 - 1.0;
    		vec3 n1_b = texture(normal_map1, normal_uv2 - TIME * normal_speed * 0.7).rgb * 2.0 - 1.0;
    		vec3 n1_sample = normalize(n1_a + n1_b);
    		n1_sample.xy *= normal_scale; // Apply scale to XY
    		
    		vec3 n2_a = texture(normal_map2, normal_uv1 * 1.2 - TIME * normal_speed * 1.5).rgb * 2.0 - 1.0;
    		vec3 n2_b = texture(normal_map2, normal_uv2 * 0.9 + TIME * normal_speed * 0.8).rgb * 2.0 - 1.0;
    		vec3 n2_sample = normalize(n2_a + n2_b);
    		n2_sample.xy *= normal_scale; // Apply scale to XY (Consistency)
    		
    		// Combine detail layers (simple average usually works best for noise)
    		detail_normal = normalize(vec3(n1_sample.xy + n2_sample.xy, 1.0)); // Reconstruct Z
    	}
	
	// ✅ 減弱 detail_normal 的混合強度
	// ✅ 減弱 detail_normal 的混合強度 (智能禁用)
	float detail_fade = smoothstep(0.3, 1.5, abs(v_world_pos.y)); // 更激進的禁用範圍
	float detail_strength = normal_scale * 0.2 * (1.0 - detail_fade); // 降到 0.2（原0.3）
	
	// ✅ Storm Mode 下進一步降低
	if (storm_mode) {
		detail_strength *= 0.5; // Storm 下只保留10%
	}
	
	detail_normal = mix(vec3(0.0, 0.0, 1.0), detail_normal, detail_strength);
	// Use safer blending (Whiteout Blend)
	normal = normalize(blend_normals(normal, detail_normal));
	
	// 4. FFT Gradient Normal Injection (Step 5 Optimization)
	// Sample precomputed gradients from RG channels
	vec2 fft_grad = texture(fft_texture, (v_world_pos.xz / sea_size) + 0.5).rg;
	vec3 fft_normal = normalize(vec3(-fft_grad.x, 1.0, -fft_grad.y));
	// Unsuppressed FFT influence for more detail
	// ✅ 降低 FFT 法線的影響（從 1.5 降到 0.8）
	// ✅ 降低 FFT 法線的影響（從 1.5 降到 0.5，10秒漸進）
	float fft_ramp = smoothstep(0.0, 10.0, TIME); // 5秒→10秒
	float fft_norm_strength = wind_strength * fft_scale * 0.5 * fft_ramp; // 0.6→0.5
	normal = normalize(mix(normal, blend_normals(normal, fft_normal), fft_norm_strength));
	
	// CRITICAL: Set the fragment normal in VIEW SPACE for correct PBR shading and reflections
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	
	// 4. Foam System (Upgraded Sensitivity)
	vec2 foam_uv = v_world_pos.xz * 0.4;
	
	// ✅ Domain Distortion (Warping)
	// Use the wave normal to distort the UVs, making foam "swirl" and "stretch"
	vec2 distortion = v_wave_normal.xz * 0.1; 
	
	// 3-Layer Texture Mixing
	float f_base = texture(foam_noise, foam_uv + distortion + TIME * 0.02).r;
	float f_detail = texture(foam_detail, foam_uv * 3.0 + distortion * 2.0 - TIME * 0.05).r;
	float f_sparkle = texture(foam_sparkle, foam_uv * 8.0 + TIME * 0.1).r;
	
	// Relaxed noise blending to allow more continuous foam
	float combined_noise = (f_base * 0.5 + f_detail * 0.3 + f_sparkle * 0.2); // Weighted blend
	combined_noise = smoothstep(0.3, 0.8, combined_noise); 

	// Shore Foam (Slightly more sensitive)
	float shore_mask = clamp(1.0 - water_depth / max(foam_shore_spread, 0.01), 0.0, 1.0);
	float shore_foam = smoothstep(0.3, 0.7, shore_mask + combined_noise * 0.4) * shore_mask * foam_shore_strength;
	
	// Global steepness signal for Foam and SSS
	// ✅ Jacobian-based Foam (Physically correct folding)
	// v_jacobian = 1.0 - Det.
	// Det < 0.0 (Folding) -> v_jacobian > 1.0
	// Bias controls sensitivity.
    // Foam threshold
	float foam_jacob_signal = smoothstep(foam_jacobian_bias, foam_jacobian_bias + 0.2, v_jacobian);
	
	// Recover missing variables for SSS and Energy
	// Recover missing variables for SSS and Energy
	float steepness_signal = max(v_jacobian - foam_jacobian_bias, 0.0);
	// Fix: reduce base energy input to prevent global whiteout
	// Only add energy when waves are actually steep/folding
	float wave_energy = steepness_signal * wind_strength; 
    
    // Add Wake Foam (SWE Interaction + Weather)
    float swe_h_frag = texture(swe_texture, v_swe_uv).r;
    // Wake signal from Height + Weather Danger
    float wake_signal = smoothstep(0.1, 0.5, abs(swe_h_frag) * 2.0) * foam_wake_strength;
    wake_signal += clamp(weather_danger * 2.0, 0.0, 1.0); 
    
    // Combine with energy (Jacobian + Wave Steepness + Wake/Interaction)
    float energetic_signal = foam_jacob_signal * 1.0 + wave_energy * 0.5 + wake_signal;

	// Integrated Crest & Wake Foam
	float crest_foam = 0.0;
	// Generate foam if there is Wind, Storm, or significant Wake/Interaction
	if (wind_strength > 0.1 || storm_mode || wake_signal > 0.01) {
		crest_foam = smoothstep(0.4, 0.7, energetic_signal + combined_noise * 0.3) * foam_crest_strength;
	}
	
	// Total Stillness Mode check (Kill all foam if completely calm)
	if (wind_strength < 0.01 && abs(swe_h_frag) < 0.02 && weather_danger < 0.01) {
		crest_foam = 0.0;
	}
	
	// === Particle Foam ===
	float particle_foam = texture(foam_particle_texture, v_swe_uv).a; // Stored in Alpha
	
    float final_foam = clamp(max(shore_foam, crest_foam) + particle_foam * 2.0, 0.0, 1.0);
    
    // Foam Tinting Logic
    vec3 foam_tint_color = mix(vec3(0.9, 0.9, 0.85), vec3(1.0), foam_jacob_signal); // Old (Yellowish) to New (White)
    foam_tint_color = mix(foam_tint_color, color_foam.rgb, 0.5); // Blend with user color
    
    // Add sparkle highlights
    foam_tint_color += vec3(f_sparkle) * 0.5 * final_foam;
    
    // Apply tint
    // NOTE: This overrides the previous "mix(color, color_foam.rgb, final_foam)" logic later
    // We calculate color mixing here
    vec3 foam_contribution = foam_tint_color * final_foam;
	
	if (debug_mesh_only) {
		normal = v_wave_normal;
		final_foam = 0.0;
	}
	
	// 5. Shading & Visibility
	vec2 ref_uv = SCREEN_UV + normal.xz * refraction_strength * clamp(water_depth, 0.0, 0.5);
	vec3 ref_color = texture(screen_texture, ref_uv).rgb;
	
	// Allow subtle refraction/ripple detail even in deep water
	// Make deep water opaque (refraction visibility 0.0 in deep, 0.6 in shallow)
	float refraction_visibility = mix(0.0, 0.6, absorption); 
	
	// Apply Transparency (Volumetric)
	// If final_foam is high, opacity increases -> Refraction visibility decreases
	refraction_visibility = mix(refraction_visibility, 1.0, transparency * (1.0 - final_foam));
	
	vec3 color = mix(sea_color, ref_color, refraction_visibility);
	
	// Caustics
	if (water_depth > 0.01 && caustics_strength > 0.0) {
		vec3 floor_world_pos = (INV_VIEW_MATRIX * vec4(view_pos_raw.xyz, 1.0)).xyz;
		vec2 caustics_uv = floor_world_pos.xz * caustics_scale;
		float speed_val = TIME * caustics_speed;
		float c1 = texture(caustics_texture, caustics_uv + vec2(speed_val, speed_val * 0.8)).r;
		float c2 = texture(caustics_texture, caustics_uv * 1.3 - vec2(speed_val, -speed_val * 0.3)).r;
		float caustic_val = min(c1, c2) * 2.0; 
		// Caustics fade out in deep water
		if (water_depth < 10.0) {
			color += vec3(1.0) * caustic_val * caustics_strength * smoothstep(0.0, 0.5, water_depth) * exp(-water_depth * 0.2);
		}
	}
	
	// Apply Foam Color
    color = mix(color, foam_tint_color, final_foam);
    
    // Normal blending with Foam Normal (if available)
    // Assuming foam_normal texture exists
    // vec3 f_normal = texture(foam_normal, foam_uv * 2.0).rgb * 2.0 - 1.0;
    // normal = mix(normal, normalize(f_normal), final_foam * 0.5);
	
	if (show_wireframe) {
		vec2 grid_uv = fract(v_swe_uv * vec2(textureSize(swe_texture, 0)));
		float grid = step(0.95, grid_uv.x) + step(0.95, grid_uv.y);
		color = mix(color, vec3(0.0, 1.0, 1.0), grid * 0.5);
	}
	
	ALBEDO = color;
	// 5.5 Visual Edge Softening
	// Replaces hard clamp with smooth proximity fade
    // Combine depth fade with world-space edge fade
	ALPHA = clamp(smoothstep(0.0, max(edge_scale, 0.01), water_depth), 0.0, 1.0);
    
    // Foam Transparency Layering
    // Edges are semi-transparent, core is opaque
    float foam_alpha = final_foam * mix(0.3, 1.0, final_foam); // Dense foam is opaque
    ALPHA = max(ALPHA, foam_alpha); // Foam adds opacity
    
    ALPHA *= smoothstep(0.0, 0.2, v_edge_damp); // Extra smooth falloff at the very edge

	// Deep water lowers metallic/specular to avoid plastic look
	// Consistent PBR parameters
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 1.0, final_foam);
	SPECULAR = mix(specular, 0.3, final_foam); 
	
	// Always show Fresnel when there are waves
	
	if (debug_view) {
		// Debug Depth: White = Surface (Depth 0), Black = Deep
		// Visualize the depth fading factor
		// ALBEDO = vec3(water_depth); // Show raw depth
		
		float debug_val = water_depth / max(edge_scale, 0.01); 
		ALBEDO = vec3(clamp(debug_val, 0.0, 1.0));
		ALPHA = 1.0;
	}
	vec3 fresnel_color = vec3(0.0);

	if (wind_strength > 0.01) {
		// Fresnel highlights based on corrected view-space normal
		fresnel_color = mix(sea_color, vec3(0.3, 0.5, 0.7), 0.3) * fresnel_strength * reflection_strength;
		EMISSION = fresnel_color * pow(fresnel, 5.0) * (1.0 - final_foam);
		
		// Sharp highlights for wave crests
		EMISSION += vec3(1.0) * pow(fresnel, 120.0) * 0.3 * fresnel_strength * reflection_strength * (1.0 - final_foam);
        
        // Subsurface Scattering (SSS) for translucent wave crests
        // Higher waves and sharper peaks get more SSS
        float sss_mask = pow(steepness_signal, 4.0); // Sharper mask
        
        // SSS is most visible when looking through the wave against the light
        // Using a combination of eye vector and wave normal to simulate back-lighting
        float sss_view_mask = pow(clamp(dot(VIEW, -NORMAL), 0.0, 1.0), 3.0);
        
        // Particle Foam SSS
        float foam_sss = particle_foam * sss_strength * 2.0;
        
        EMISSION += sss_color.rgb * (sss_strength * sss_mask * (0.2 + 0.8 * sss_view_mask) + foam_sss) * (1.0 - final_foam);
	} else {
		EMISSION = vec3(0.0);
	}
	// 🔥 Break Wave Debug Visualization (Moved)
	if (debug_show_markers && breaking_wave_count > 0) {
		vec2 test_pos = breaking_wave_data[0].xz;
		float test_dist = length(v_world_pos.xz - test_pos);
		if (test_dist < breaking_wave_data[0].w) {
			ALBEDO = vec3(1.0, 0.0, 0.0); // Red Marker
			ALPHA = 0.5; // Semi-transparent to see shape
			EMISSION = vec3(0.5, 0.0, 0.0);
		}
	}
}
