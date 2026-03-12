shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage, depth_draw_always;

// Varying for Jacobian (Foam)
varying float v_jacobian;

uniform float peak_sharpness : hint_range(0.1, 4.0) = 1.0;
uniform float sss_strength : hint_range(0.0, 5.0) = 0.5;
uniform vec4 sss_color : source_color = vec4(0.0, 0.6, 0.5, 1.0);

// Inline WaterWaves.gdshaderinc logic for self-containment
// Redundant PI removed

uniform float horizontal_displacement_scale : hint_range(0.0, 1.0) = 0.8;
uniform float lod_scale = 1.0;  // Moved early: needed by get_layer_lod_fade()

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

// LOD layer fade: returns 0.0-1.0 energy multiplier for each wave layer based on distance
// Layers 0-3 = low freq (always full), Layers 4-5 = mid (fade 50-120m), Layers 6-7 = high (fade 25-70m)
float get_layer_lod_fade(int layer_index, float cam_dist) {
    if (layer_index < 4) return 1.0;  // Low-frequency layers always active
    if (layer_index < 6) {
        // Mid-frequency: fade out between 50-120m
        return 1.0 - smoothstep(50.0 * lod_scale, 120.0 * lod_scale, cam_dist);
    }
    // High-frequency: fade out between 25-70m
    return 1.0 - smoothstep(25.0 * lod_scale, 70.0 * lod_scale, cam_dist);
}

vec3 get_waves_displacement(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, inout vec3 tangent, inout vec3 binormal, int iterations, inout float jacobian_det, float cam_dist) {
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
    if (global_energy_scale * total_relative_steepness * wind_strength > 0.75) {
        steepness_norm = 0.75 / (global_energy_scale * total_relative_steepness * wind_strength);
    }

    float base_angle = atan(wind_dir.y, wind_dir.x);
    
    // ✅ Safety Clamp for Chaos (Prevent Moiré patterns)
    float safe_chaos = min(wave_chaos, 0.3);

    for (int i = 0; i < iterations; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx] * wave_length;
        
        // ✅ LOD fade: smoothly reduce high-freq layer energy at distance
        float lod_fade = get_layer_lod_fade(i, cam_dist);
        float w_steep = wave_data[idx+1] * global_energy_scale * wind_strength * steepness_norm * lod_fade;
        
        // Skip fully faded layers
        if (lod_fade < 0.001) continue;
        
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

vec3 get_gerstner_normal_analytical(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, float cam_dist) {
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
    for (int i = 0; i < 8; i++) total_relative_steepness += wave_data[i * 4 + 1];
    
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
        
        // ✅ LOD fade: smoothly reduce high-freq layer contribution at distance
        float lod_fade = get_layer_lod_fade(i, cam_dist);
        float w_steep = wave_data[idx+1] * global_energy_scale * wind_strength * steepness_norm * lod_fade;
        
        // Skip fully faded layers for performance
        if (lod_fade < 0.001) continue;
        
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * safe_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        float k = 2.0 * PI / w_len;
        float c = sqrt(9.81 / k) * w_speed;
        float f = k * (dot(d, pos.xz) - c * t);
        
        // Derivative of height w.r.t. phase (always smooth cos)
        float dh_df = cos(f);
        
        // ✅ Standard Gerstner Analytic Normal with LOD fade applied
        normal.x -= d.x * w_steep * dh_df;
        normal.y -= w_steep * dh_df;
        normal.z -= d.y * w_steep * dh_df;
    }
    
    // ✅ Standard normalization
    return normalize(normal);
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
uniform float wave_height_multiplier = 1.0;  // Direct height control (1.0 = normal) 

uniform vec4 color_deep : source_color = vec4(0.05, 0.18, 0.4, 1.0); 
uniform vec4 color_shallow : source_color = vec4(0.0, 0.73, 0.99, 1.0);  
uniform vec4 color_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float absorption_coeff = 0.3;
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


// === Volumetric & Particle Foam ===
uniform sampler2D foam_particle_texture : hint_default_black;
uniform float water_transparency : hint_range(0.0, 1.0) = 0.8;
uniform vec3 water_scatter_color : source_color = vec3(0.1, 0.6, 0.8);
uniform float physics_time = 0.0;
uniform float render_alpha = 0.0;

uniform float fft_scale = 1.0;
uniform float normal_tile = 10.0;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D flow_map : hint_default_black, filter_linear, repeat_enable;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.5;

// === Analytic Player Interaction Ripples ===
uniform int ar_count = 0;
// x,y: world_pos.x,z; z: start_time; w: intensity
uniform vec4 ar_data[64];
uniform float ar_lifetime = 3.0;
uniform float ar_speed = 2.0;
uniform float ar_freq = 15.0;
uniform float ar_decay = 2.0;
uniform float ripple_normal_strength = 2.0;
uniform float ripple_height_scale = 0.15;


uniform float edge_scale : hint_range(0.0, 5.0) = 0.5;
uniform float far_fade_start : hint_range(0.0, 500.0) = 150.0;
uniform float far_fade_max : hint_range(0.0, 1000.0) = 300.0;
// === Debug Normal Visualization ===
// 0 = Off, 1 = Final Normal RGB, 2 = Analytical Normal Only, 3 = Vertex Normal Only, 4 = Difference Heatmap
uniform int debug_normal_mode : hint_range(0, 5) = 0;



// ... (Existing uniforms)
varying vec2 v_swe_uv;
varying vec3 v_wave_normal;
varying vec3 v_world_pos;
varying float v_edge_damp;
varying float v_cam_dist;  // Camera distance for fragment LOD matching

// === 新增 Uniforms for Breaking Waves ===
uniform int breaking_wave_count = 0;
uniform vec4 breaking_wave_data[3];  // xyz=pos+height, w=width
uniform vec4 breaking_wave_params[3];  // x=curl, y=break_point, z=state
// envelope_tex already defined at line 236

// 1D Envelope Sampling for Rogue Wave
float sample_envelope(float dist, float width) {
    float u = clamp((dist / width) * 0.5 + 0.5, 0.0, 1.0);
    float val = texture(envelope_tex, vec2(u, 0.0)).r;
    
    // ✅ Procedural Safety: Force fade to 0.0 at the edges 
    // This handles texture sampling artifacts or non-zero edge pixels
    float dist_norm = abs(dist / width);
    float window = smoothstep(1.0, 0.9, dist_norm);
    
    return val * window;
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
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_pos;
	
	// Standard Ocean Surface Vertex Logic
	v_swe_uv = (VERTEX.xz / sea_size) + 0.5;
	v_swe_uv = clamp(v_swe_uv, 0.0, 1.0);
	float cam_dist = length(world_pos - manager_world_pos); // Or CAMERA_POSITION_WORLD if available
	
	// === 新增：破碎波浪捲曲 ===
	for (int i = 0; i < breaking_wave_count; i++) {
		vec3 wave_center = breaking_wave_data[i].xyz;
		float wave_width = breaking_wave_data[i].w; // Ensure wave_width is float
		float curl_strength = breaking_wave_params[i].x;
		float break_point = breaking_wave_params[i].y;
		
		// 計算到波浪中心的距離
		vec2 to_wave = world_pos.xz - wave_center.xz;
		float dist_along = dot(to_wave, normalize(wind_dir));  // 沿波浪方向
		float dist_across = length(to_wave - dist_along * normalize(wind_dir));
		
		// 只影響波浪寬度範圍內
		if (abs(dist_across) > wave_width) continue;
		
		// 橫向衰減
		float lateral_fade = smoothstep(wave_width, wave_width * 0.5, abs(dist_across));
		
		// 縱向形態（Sech 包絡）
		float u = clamp(dist_along / wave_width * 0.5 + 0.5, 0.0, 1.0);
		float envelope = texture(envelope_tex, vec2(u, 0.0)).r;
		
		// === 關鍵：水平位移創造 "捲曲" ===
		// 在波峰前方（u > break_point）產生向前的位移
		float curl_zone = smoothstep(break_point - 0.2, break_point + 0.1, u);
		
		// 捲曲方向：沿著波浪前進方向，但向下彎曲
		vec3 curl_offset = vec3(
			normalize(wind_dir).x * curl_zone * curl_strength * 3.0,
			-curl_zone * curl_strength * 2.0,  // 向下彎曲
			normalize(wind_dir).y * curl_zone * curl_strength * 3.0
		);
		
		// 應用捲曲（疊加到現有位移）
		// FIX: Use += to accumulate
		VERTEX += curl_offset * envelope * lateral_fade * wave_center.y; 
	}

	// Sample SWE for displacement
	vec4 swe_sample = texture(swe_texture, v_swe_uv);
	float swe_h = swe_sample.r;
		float is_obstacle = swe_sample.a;
		float wave_weight = 1.0 - is_obstacle;
		
		// Time Interpolation for smooth vertex movement
		float interpolated_time = physics_time + render_alpha * (1.0 / 60.0);
		
		// ✅ LOD Strategy: Always run 8 iterations, but per-layer fade handles energy
		// The get_layer_lod_fade() function smoothly fades high-freq layers at distance
		// instead of hard-stepping iterations (which caused aliasing pop-in)
		int iterations = 8;
		v_cam_dist = cam_dist;  // Pass to fragment for analytical normal LOD matching

		// Gerstner Waves
		vec3 tangent = vec3(1.0, 0.0, 0.0);
		vec3 binormal = vec3(0.0, 0.0, 1.0);
		vec3 wave_disp = vec3(0.0);

		// Jacobian accumulator (Determinant initialized to 1.0)
		float j_det = 1.0;

		// Calculate Distance Damping for smooth horizon
		float dist = length(world_pos - CAMERA_POSITION_WORLD);
		float wave_damp = 1.0 - smoothstep(far_fade_start, far_fade_max, dist);
		
		// World Space Edge Damping (Box Projection)
		vec2 dist_from_center = abs(world_pos.xz - manager_world_pos.xz);
		vec2 half_size = sea_size * 0.5;
		
		vec2 margin_general = half_size * 0.4;
		vec2 edge_t_gen = smoothstep(half_size - margin_general, half_size, dist_from_center);
		edge_t_gen = smoothstep(0.0, 1.0, edge_t_gen);
		
		vec2 margin_horizontal = half_size * 0.2;
		vec2 edge_t_hor = smoothstep(half_size - margin_horizontal, half_size, dist_from_center);
		edge_t_hor = smoothstep(0.0, 1.0, edge_t_hor);
		
		float edge_damp_gen = (1.0 - edge_t_gen.x) * (1.0 - edge_t_gen.y);
		float edge_damp_hor = (1.0 - edge_t_hor.x) * (1.0 - edge_t_hor.y);
		
		float final_damp = wave_damp * edge_damp_gen;
		float h_damp = edge_damp_hor;
		v_edge_damp = edge_damp_gen; // Pass to fragment for Alpha fade
		
		if (wind_strength > 0.001) {
			wave_disp = get_waves_displacement(world_pos, interpolated_time, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, tangent, binormal, iterations, j_det, cam_dist);
		}

		v_jacobian = 1.0 - j_det;
		
		vec3 rogue_disp = get_rogue_wave_displacement(world_pos, interpolated_time, tangent, binormal, tangent, binormal);
		wave_disp += rogue_disp;
		
		// ✅ Recalculate normal including Rogue Wave influence
		v_wave_normal = normalize(cross(binormal, tangent));
		
		wave_disp.xz *= h_damp;
		wave_disp.y *= final_damp;
		
		// Apply manual height multiplier
		wave_disp.y *= wave_height_multiplier;
		
		// === Breaking Wave Logic Removed ===

		
		// 🔥 Global Sea Level Floor
		
		VERTEX.xyz += wave_disp; 
		VERTEX.y += swe_h * swe_strength * wave_weight * final_damp;
		
		vec2 fft_uv = (world_pos.xz / sea_size) + 0.5;
		float fft_h = texture(fft_texture, fft_uv).b;
		VERTEX.y += fft_h * wind_strength * wave_weight * fft_scale * final_damp;
		
		// === Analytic Ripple Vertex Displacement ===
		{
			float ar_vert_h = 0.0;
			for (int i = 0; i < ar_count; i++) {
				vec4 r = ar_data[i];
				float age = physics_time - r.z;
				if (age <= 0.0 || age > ar_lifetime) continue;
				
				vec2 offset = world_pos.xz - r.xy;
				float dist = length(offset);
				float radius = age * ar_speed;
				float wave_val = 1.0 - abs(dist - radius) * ar_freq;
				
				if (wave_val > 0.0) {
					float spatial_decay = 1.0 - clamp(dist * ar_decay, 0.0, 1.0);
					float time_decay = spatial_decay * (1.0 - age / ar_lifetime);
					ar_vert_h += wave_val * r.w * time_decay;
				}
			}
			VERTEX.y += ar_vert_h * ripple_height_scale * final_damp;
		}

		
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
	
	// === 改進：半透明水體 ===
	// 淺水區更透明，深水區更不透明
	float transparency = mix(water_transparency, 0.95, smoothstep(0.0, 5.0, water_depth));
	
	// 波浪內部的體積散射
	float wave_thickness = max(0.0, v_world_pos.y - manager_world_pos.y);
	vec3 scattered_light = water_scatter_color * exp(-wave_thickness * 0.3);
	
	float absorption = exp(-water_depth * absorption_coeff);
	vec3 sea_color = mix(color_deep.rgb, color_shallow.rgb, absorption);
	
	// 從 Refraction 混合散射光
	// (Apply later after foam calculation)
	
	// ... (Rest of logic needs careful integration)
	
	// 2. Sample Weather Influence
	vec4 weather_data = texture(weather_influence, v_swe_uv);
	float weather_danger = weather_data.a;
	sea_color = mix(sea_color, sea_color * 0.3, clamp(weather_danger * 2.0, 0.0, 1.0));

	// ... (Normal Reconstruction - Keeping Existing Logic)
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

	// Normal System
	vec3 base_normal = v_wave_normal;
	
	// ✅ Always compute analytic normal (wind_strength naturally attenuates when calm)
	{
		float interpolated_time = physics_time + render_alpha * (1.0 / 60.0);
		vec3 analytical_n = get_gerstner_normal_analytical(v_world_pos, interpolated_time, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
		
		// Blend weight: stronger analytic contribution at wave peaks, softer in troughs
		float wave_height_factor = clamp(v_world_pos.y / max(wave_length * 0.2, 0.5), 0.0, 1.0);
		float smooth_transition = smoothstep(0.0, 0.6, wave_height_factor);
		float mix_weight = mix(0.4, 0.8, smooth_transition);
		mix_weight *= v_edge_damp * wind_strength;  // Natural fade when calm
		
		base_normal = normalize(mix(base_normal, analytical_n, clamp(mix_weight, 0.0, 1.0)));
	}

	vec3 controlled_ripple = ripple_n_offset * clamp(swe_strength * 0.5, 0.0, 1.5);
	vec3 controlled_weather = weather_n_offset * clamp(weather_danger * 1.5, 0.0, 2.0);
	
	// === Analytic Ripple Normal Perturbation ===
	vec3 gpu_ripple_normal = vec3(0.0);
	float ripple_height_val = 0.5;  // ★ 儲存漣漪高度供 wake foam 使用 (<0.5: 波谷)
	float ripple_fade_val = 1.0;
	{
		float ar_h = 0.0;
		vec3 ar_norm_offset = vec3(0.0);
		
		for (int i = 0; i < ar_count; i++) {
			vec4 r = ar_data[i];
			float age = physics_time - r.z; // use continuous physics time
			if (age <= 0.0 || age > ar_lifetime) continue;
			
			vec2 offset = v_world_pos.xz - r.xy;
			float dist = length(offset);
			
			float radius = age * ar_speed;
			float wave_val = 1.0 - abs(dist - radius) * ar_freq;
			
			if (wave_val > 0.0) {
				float spatial_decay = 1.0 - clamp(dist * ar_decay, 0.0, 1.0);
				float time_decay = spatial_decay * (1.0 - age / ar_lifetime);
				float h = wave_val * r.w * time_decay;
				ar_h += h;
				
				// Analytical Normal Approximation (Derivative of distance)
				if (dist > 0.001) {
					vec2 dir = offset / dist;
					float slope = -sign(dist - radius) * ar_freq * r.w * time_decay;
					ar_norm_offset.x -= dir.x * slope * ripple_normal_strength;
					ar_norm_offset.z -= dir.y * slope * ripple_normal_strength;
				}
			}
		}
		
		gpu_ripple_normal = ar_norm_offset;
		
		// 映射回 0.0~1.0 區間供泡沫判斷  
		// 原有 wake_foam 邏輯中，`smoothstep(0.35, 0.20, ripple_height_val)` 用波谷觸發泡沫。
		// 衝擊點(h>0)的周圍理應凹陷，為簡化，我們直接將 h(突起) 視為凹陷反轉，
		// 這樣 ar_h 越大，ripple_height_val 越小，就能激發泡沫。
		ripple_height_val = 0.5 - ar_h * 1.5; 
		
		// 焦散強度近似 (利用法線變化量)
		// ★ 大幅限制焦散亮度，避免漣漪密集時 ALBEDO 和 NORMAL 爆炸
		float caustic_raw = length(ar_norm_offset) * 5.0;
		float caustic_bright = clamp(pow(max(caustic_raw, 0.0), 1.5), 0.0, 0.3);
		gpu_ripple_normal.y = caustic_bright;
	}
	
	vec3 normal = normalize(base_normal + controlled_ripple + controlled_weather + gpu_ripple_normal);

	
	// Detail Normals (Keeping existing dual sampling logic simplified for brevity in this replacement, assume mostly unchanged)
	// ... (Skipping full detail normal re-implementation for brevity, assuming standard mix)
	// For implementing the new foam logic, we focus on the Foam section below.
	
	// ... (Detail Normal Logic) ...
	// To minimize code replacement risk, I will re-implement the detail normal logic as it was, to ensure it works.
	
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
    		vec2 normal_uv1 = v_world_pos.xz * normal_tile * 0.1;
    		vec2 normal_uv2 = v_world_pos.zx * normal_tile * 0.11 + vec2(TIME * 0.05, -TIME * 0.03); 
    		
    		vec3 n1_a = texture(normal_map1, normal_uv1 + TIME * normal_speed).rgb * 2.0 - 1.0;
    		vec3 n1_b = texture(normal_map1, normal_uv2 - TIME * normal_speed * 0.7).rgb * 2.0 - 1.0;
    		vec3 n1_sample = normalize(n1_a + n1_b);
    		n1_sample.xy *= normal_scale; 
    		
    		vec3 n2_a = texture(normal_map2, normal_uv1 * 1.2 - TIME * normal_speed * 1.5).rgb * 2.0 - 1.0;
    		vec3 n2_b = texture(normal_map2, normal_uv2 * 0.9 + TIME * normal_speed * 0.8).rgb * 2.0 - 1.0;
    		vec3 n2_sample = normalize(n2_a + n2_b);
    		n2_sample.xy *= normal_scale; 
    		detail_normal = normalize(vec3(n1_sample.xy + n2_sample.xy, 1.0)); 
    	}
	
	float detail_fade = smoothstep(0.3, 1.5, abs(v_world_pos.y)); 
	float detail_strength = normal_scale * 0.2 * (1.0 - detail_fade); 
	if (storm_mode) detail_strength *= 0.5;
	detail_normal = mix(vec3(0.0, 0.0, 1.0), detail_normal, detail_strength);
	normal = normalize(blend_normals(normal, detail_normal));
	
	// FFT Normal Injection
	vec2 fft_grad = texture(fft_texture, (v_world_pos.xz / sea_size) + 0.5).rg;
	vec3 fft_normal = normalize(vec3(-fft_grad.x, 1.0, -fft_grad.y));
	float fft_ramp = smoothstep(0.0, 10.0, TIME);
	float fft_norm_strength = wind_strength * fft_scale * 0.5 * fft_ramp;
	normal = normalize(mix(normal, blend_normals(normal, fft_normal), fft_norm_strength));
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	
	// Initialize color variable
	vec3 color = sea_color;
	
	// === 改進：泡沫粒子疊加 ===
    float particle_foam = texture(foam_particle_texture, v_swe_uv).a;
    
    // === 改進：泡沫材質 (3 層混合) ===
    vec2 foam_uv_fine = v_world_pos.xz * 2.0 + TIME * 0.1;
    vec2 foam_uv_coarse = v_world_pos.xz * 0.5 - TIME * 0.05;
    
    float foam_detail_1 = texture(foam_noise, foam_uv_fine).r;
    float foam_detail_2 = texture(foam_noise, foam_uv_coarse * 1.3).r;
    float foam_sparkle_value = pow(texture(foam_noise, foam_uv_fine * 3.0).r, 4.0);
    
    // 計算一般波浪泡沫 (Jacobian)
    float foam_jacob_signal = smoothstep(foam_jacobian_bias, foam_jacobian_bias + 0.2, v_jacobian);
    float steepness_signal = max(v_jacobian - foam_jacobian_bias, 0.0);
    float wave_energy = steepness_signal * wind_strength; 
    float swe_h_frag = texture(swe_texture, v_swe_uv).r;
    // ★ wake_signal is intentionally EXCLUDED from crest_foam:
    // Using abs(swe_h) here creates circular halos around any SWE disturbanc.
    // SWE-based foam is handled by physical gradient below in the wake_foam block.
    float weather_energy = clamp(weather_danger * 2.0, 0.0, 1.0);
    float energetic_signal = foam_jacob_signal * 1.0 + wave_energy * 0.5 + weather_energy;
    float crest_foam = 0.0;
	if (wind_strength > 0.1 || storm_mode) {
		crest_foam = smoothstep(0.4, 0.7, energetic_signal);
	}
	
	// ★★★ B4: 尾流泡沫 ★★★
	// 漣漪高度 < 0.45 表示水面被壓低（衝擊點）→ 產生泡沫
	float wake_foam = 0.0;
	{
		// ★ Analytic Ripple Foam (原有)
		// 大幅提高閾值並降低強度，避免玩家走動時漣漪重疊產生巨大白色螢光塊
		float depression = smoothstep(0.40, 0.0, ripple_height_val) * 0.3;
		float ripple_gradient = length(gpu_ripple_normal.xz);
		float gradient_foam = smoothstep(2.0, 5.0, ripple_gradient) * 0.3;
		
		wake_foam = max(depression, gradient_foam) * ripple_fade_val;
		
		// ★ SWE Compute Shader Ship Wake Foam (Modified to use physical slope)
		// 透過採樣周圍的高度計算 SWE 波浪的物理坡度 (高度差 / 實際距離)，只有在陡峭邊緣產生泡沫
		vec2 ts = 1.0 / vec2(textureSize(swe_texture, 0));
		float swe_h_r = texture(swe_texture, v_swe_uv + vec2(ts.x, 0.0)).r;
		float swe_h_u = texture(swe_texture, v_swe_uv - vec2(0.0, ts.y)).r;
		
		// 物理距離 = UV距離 * 總海面大小
		float phys_dx = ts.x * sea_size.x;
		float phys_dy = ts.y * sea_size.y;
		
		float swe_dx = (swe_h_r - swe_h_frag) / phys_dx;
		float swe_dy = (swe_h_u - swe_h_frag) / phys_dy;
		float swe_slope = length(vec2(swe_dx, swe_dy));
		
		// 物理坡度大於 0.6 才產生白沫，最多到 2.0 完全起沫.
		// ★ swe_foam_crest (abs height threshold) is INTENTIONALLY REMOVED:
		// It generated circular halos. Only the steep gradient at the V-wake edge produces foam.
		float swe_foam_edge = smoothstep(0.6, 2.0, swe_slope) * 0.9;
		
		// 只有「極度深陷、已拉垮」的凹陷才起沫（鈎魚線切割）
		float swe_depression_foam = smoothstep(-0.8, -2.0, swe_h_frag) * 0.3;
		
		wake_foam = max(wake_foam, max(swe_foam_edge, swe_depression_foam) * foam_wake_strength);
		
		// 風大時抑制部分 Analytical 尾流，但 Compute Shader 的大型尾跡可能不受影響
		wake_foam *= mix(1.0, (1.0 - smoothstep(0.5, 1.5, wind_strength)), 0.5);
	}
	
	// 合併所有泡沫源
    float total_foam = clamp(
        crest_foam +           // 波峰/岸邊泡沫
        particle_foam * 2.0 +  // 粒子泡沫
        wake_foam,             // ★ 尾流泡沫
        0.0, 1.0
    );
    
    // 混合細節
    float foam_detail_mix = foam_detail_1 * 0.5 + foam_detail_2 * 0.3 + foam_sparkle_value * 0.2;
    // Add procedural generic noise in case texturing is solid white
    float procedural_foam_noise = fract(sin(dot(v_world_pos.xz * 2.0, vec2(12.9898, 78.233))) * 43758.5453);
    foam_detail_mix = mix(procedural_foam_noise * 0.8, foam_detail_mix, 0.5);
    
    float foam_final_mask = total_foam * foam_detail_mix;
    foam_final_mask = smoothstep(0.1, 0.9, foam_final_mask) * total_foam; // Thresholding to keep boundaries organic
    
    // 泡沫著色（帶微妙的藍色調）
    vec3 foam_color_tint = mix(
        vec3(0.85, 0.92, 0.98),  // 基礎淺藍白
        vec3(1.0, 1.0, 1.0),     // 純白高光
        foam_sparkle_value
    );
    
    // Apply Foam to Color (Soft blend instead of direct replacement)
    // By keeping the blend factor maxed out at 0.75, we still see sub-surface water (no MS Paint look)
    color = mix(color, foam_color_tint, foam_final_mask * 0.75);
    
    // Refraction Transparency (Modified by foam)
    // Foam makes water more opaque, but not 100% solid instantly
    transparency = mix(transparency, 1.0, foam_final_mask * 0.8); 
    
    // 5. Shading & Visibility (Refraction)
	vec2 ref_uv = SCREEN_UV + normal.xz * refraction_strength * clamp(water_depth, 0.0, 0.5);
	vec3 ref_color = texture(screen_texture, ref_uv).rgb;
	
	// Refraction visibility based on transparency
	// When transparency is high (opaque water), use sea_color
	// When transparency is low (shallow/clear water), blend with refracted background
	float refraction_visibility = 1.0 - transparency;
	
	// Fix: Blend sea_color with refraction, NOT replace it entirely
	// sea_color is our base, ref_color is what we see through the water
	vec3 water_base_color = sea_color + scattered_light * 0.3;
	
	// Only apply refraction in shallow water (when transparency is low)
	// Use a much lower refraction influence to prevent gray wash-out
	float refract_blend = refraction_visibility * 0.2 * (1.0 - fresnel);
	color = mix(water_base_color, ref_color, refract_blend);
	
	// Add sky reflection based on fresnel (makes water look more realistic)
	color = mix(color, water_base_color * 1.2, fresnel * 0.3);
	
	// Re-apply foam on top of refracted color
	color = mix(color, foam_color_tint, foam_final_mask);

    ALBEDO = color;
	
	// ★★★ B5: 動態焦散（雙層旋轉 UV）★★★
	float dynamic_caustic = 0.0;
	if (caustics_strength > 0.01) {
		// 層 1：順時針旋轉
		float angle1 = TIME * caustics_speed;
		mat2 rot1 = mat2(vec2(cos(angle1), sin(angle1)), vec2(-sin(angle1), cos(angle1)));
		vec2 caustic_uv1 = rot1 * (v_world_pos.xz * caustics_scale) + TIME * 0.02;
		// 層 2：逆時針旋轉 + 不同縮放
		float angle2 = -TIME * caustics_speed * 0.7;
		mat2 rot2 = mat2(vec2(cos(angle2), sin(angle2)), vec2(-sin(angle2), cos(angle2)));
		vec2 caustic_uv2 = rot2 * (v_world_pos.xz * caustics_scale * 1.3) - TIME * 0.015;
		// 取 min → 產生交叉聚焦圖案
		float c1 = texture(caustics_texture, caustic_uv1).r;
		float c2 = texture(caustics_texture, caustic_uv2).r;
		dynamic_caustic = min(c1, c2);
		dynamic_caustic = pow(dynamic_caustic, 1.5) * caustics_strength;
		// 風大時減弱（水面太亂焦散不明顯）
		dynamic_caustic *= (1.0 - smoothstep(0.5, 2.0, wind_strength));
		// 淺水處更明顯
		dynamic_caustic *= smoothstep(2.0, 0.5, water_depth);
	}
	
	// 漣漪焦散 + 動態焦散
	// ★ 抑制漣漪區域的焦散，避免密集漣漪時焦散疊加而發白
	float ripple_activity = clamp(length(gpu_ripple_normal.xz) * 0.5, 0.0, 1.0);
	float ripple_caustic = max(gpu_ripple_normal.y, 0.0) * (1.0 - ripple_activity);
	float total_caustic = ripple_caustic + dynamic_caustic;
	ALBEDO += vec3(total_caustic * 0.3, total_caustic * 0.35, total_caustic * 0.4);
    
    // === 透明度最終混合 ===
    ALPHA = mix(
        smoothstep(0.0, edge_scale, water_depth) * transparency,  // 水深 Alpha + Transparency
        1.0,                                       // 泡沫不透明
        foam_final_mask
    );
    ALPHA *= smoothstep(0.0, 0.2, v_edge_damp);
    
    // PBR
	METALLIC = metallic * (1.0 - foam_final_mask);
	ROUGHNESS = mix(roughness, 1.0, foam_final_mask);
	SPECULAR = mix(specular, 0.0, foam_final_mask);

	vec3 fresnel_color = vec3(0.0);
	if (wind_strength > 0.01) {
		// ★ 在漣漪活動區域壓制 fresnel EMISSION，避免法線擾動導致 HDR 爆光
		float fresnel_suppress = 1.0 - ripple_activity;
		fresnel_color = mix(sea_color, color_shallow.rgb, 0.5) * fresnel_strength * reflection_strength;
		EMISSION = fresnel_color * pow(fresnel, 5.0) * (1.0 - foam_final_mask) * fresnel_suppress;
		
		// === 改進：Fresnel 與波峰高光 ===
		// 破碎波浪的波峰應該有強烈的高光
		float crest_highlight = pow(steepness_signal, 8.0) * fresnel_strength;
		EMISSION += vec3(1.0) * crest_highlight * 0.5 * (1.0 - foam_final_mask) * fresnel_suppress;
		
		// 泡沫區域的次表面散射
		float foam_sss = particle_foam * sss_strength * 2.0;
		EMISSION += sss_color.rgb * foam_sss * (1.0 - foam_final_mask);
		
		// Standard SSS
		float sss_mask = pow(steepness_signal, 4.0);
        float sss_view_mask = pow(clamp(dot(VIEW, -NORMAL), 0.0, 1.0), 3.0);
        EMISSION += sss_color.rgb * sss_strength * sss_mask * (0.2 + 0.8 * sss_view_mask) * (1.0 - foam_final_mask);
		
		// ★★★ B6: 漣漪波峰次表面散射 ★★★
		// 漣漪波峰處（height < 0.45）有薄水膜效果
		// ★ 在漣漪密集區域壓制 SSS，避免與 fresnel 疊加造成爆光
		float ripple_crest_mask = smoothstep(0.45, 0.35, ripple_height_val) * ripple_fade_val;
		float ripple_sss_view = pow(max(dot(VIEW, -NORMAL), 0.0), 4.0);
		EMISSION += sss_color.rgb * ripple_crest_mask * ripple_sss_view * sss_strength * 0.5 * fresnel_suppress;
		// ★ 最終安全：硬性限制 EMISSION 防止任何來源導致 HDR Bloom
		EMISSION = min(EMISSION, vec3(0.4));
	}
	
	// === Debug Normal Visualization (Amplified XZ Deviation) ===
	if (debug_normal_mode > 0) {
		vec3 debug_color = vec3(0.0);
		
		// Helper: Convert normal's XZ tilt to visible color
		// Amplifies the horizontal component 5x so subtle tilts become obvious
		// Color wheel: Red=+X, Green=+Z, Cyan=-X, Magenta=-Z
		// Brightness = tilt amount, Dark center = perfectly vertical
		
		if (debug_normal_mode == 1) {
			// Mode 1: Final blended normal — XZ tilt amplified
			vec2 tilt = normal.xz * 5.0;  // 5x amplification
			float tilt_amount = clamp(length(tilt), 0.0, 1.0);
			debug_color = vec3(
				tilt.x * 0.5 + 0.5,          // Red = X direction
				tilt.y * 0.5 + 0.5,          // Green = Z direction
				1.0 - tilt_amount             // Blue = flatness (bright=flat)
			);
		}
		else if (debug_normal_mode == 2) {
			// Mode 2: Pure analytical Gerstner normal — XZ tilt amplified
			float interp_t = physics_time + render_alpha * (1.0 / 60.0);
			vec3 ana_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
			vec2 tilt = ana_n.xz * 5.0;
			float tilt_amount = clamp(length(tilt), 0.0, 1.0);
			debug_color = vec3(
				tilt.x * 0.5 + 0.5,
				tilt.y * 0.5 + 0.5,
				1.0 - tilt_amount
			);
		}
		else if (debug_normal_mode == 3) {
			// Mode 3: Vertex normal — XZ tilt amplified
			vec2 tilt = v_wave_normal.xz * 5.0;
			float tilt_amount = clamp(length(tilt), 0.0, 1.0);
			debug_color = vec3(
				tilt.x * 0.5 + 0.5,
				tilt.y * 0.5 + 0.5,
				1.0 - tilt_amount
			);
		}
		else if (debug_normal_mode == 4) {
			// Mode 4: Difference heatmap — 10x more sensitive
			float interp_t = physics_time + render_alpha * (1.0 / 60.0);
			vec3 ana_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
			float diff = length(ana_n - v_wave_normal) * 5.0;  // Amplify difference
			// More sensitive gradient: Blue(0) → Cyan(0.1) → Green(0.2) → Yellow(0.5) → Red(1.0)
			debug_color.r = smoothstep(0.05, 0.3, diff);
			debug_color.g = smoothstep(0.0, 0.05, diff) * (1.0 - smoothstep(0.5, 1.0, diff));
			debug_color.b = 1.0 - smoothstep(0.0, 0.1, diff);
		}
		else if (debug_normal_mode == 5) {
			// Mode 5: Split-screen A/B comparison
			// LEFT  = With LOD fade (what player sees)
			// RIGHT = Full 8 layers (no LOD fade, reference)
			float interp_t = physics_time + render_alpha * (1.0 / 60.0);
			
			// LOD-faded normal (uses cam_dist for fade)
			vec3 lod_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
			
			// Full-detail normal (cam_dist=0 means no fade applied)
			vec3 full_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, 0.0);
			
			// Split screen using SCREEN_UV.x
			vec2 screen_uv = SCREEN_UV;
			bool is_left = screen_uv.x < 0.5;
			
			// Show normal-mapped grayscale (tilt intensity = detail level)
			vec3 chosen_n = is_left ? lod_n : full_n;
			float detail = length(chosen_n.xz) * 4.0;
			
			// Grayscale with slight color tint: left=blue tint, right=green tint
			if (is_left) {
				debug_color = vec3(0.2, 0.4, 0.8) * (0.3 + detail);  // Blue tint
			} else {
				debug_color = vec3(0.2, 0.8, 0.3) * (0.3 + detail);  // Green tint
			}
			
			// Red divider line (2px wide)
			if (abs(screen_uv.x - 0.5) < 0.003) {
				debug_color = vec3(1.0, 0.0, 0.0);
			}
		}
		
		ALBEDO = debug_color;
		EMISSION = debug_color * 0.5;  // Brighter emission so it's clearly visible
		ALPHA = 1.0;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);  // Flat normal so lighting doesn't interfere
	}
}
