shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords, depth_prepass_alpha;

#include "res://WaterSystem/Core/Shaders/WaterWaves.gdshaderinc"

uniform sampler2D swe_texture : hint_default_black, filter_linear; 
uniform float swe_strength = 2.0;
uniform vec2 sea_size = vec2(40.0, 40.0);

uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.5);
uniform float wave_steepness = 0.2;
uniform float wave_length = 10.0;
uniform float wave_chaos = 0.5; 

uniform vec4 color_deep : source_color = vec4(0.05, 0.25, 0.45, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.3, 0.7, 0.9, 1.0);
uniform vec4 color_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float absorption_coeff = 1.2;
uniform float refraction_strength = 0.03;

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 1.0;

uniform float foam_shore_spread = 0.5;
uniform float foam_shore_strength = 1.0;
uniform float foam_crest_spread = 0.2;
uniform float foam_crest_strength = 0.8;
uniform float foam_wake_strength = 1.5;
// Jacobian Foam Bias (Adjusts threshold for foam appearance)
uniform float foam_jacobian_bias : hint_range(0.0, 1.0) = 0.3;

// Caustics
uniform sampler2D caustics_texture : hint_default_black, repeat_enable;
uniform float caustics_strength : hint_range(0.0, 5.0) = 1.0;
uniform float caustics_scale = 0.5;
uniform float caustics_speed = 0.1;

uniform bool debug_show_markers = false;

uniform sampler2D foam_noise : repeat_enable; 
uniform sampler2D normal_map1 : hint_normal, repeat_enable;
uniform sampler2D normal_map2 : hint_normal, repeat_enable;

uniform float normal_scale : hint_range(0.0, 2.0) = 0.5;
uniform float normal_speed : hint_range(0.0, 0.5) = 0.1;
uniform float normal_tile : hint_range(1.0, 100.0) = 20.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_jacobian;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (world_pos.xz / sea_size) + 0.5;
	vec4 swe_sample = texture(swe_texture, uv);
	float swe_h = swe_sample.r;
	float is_obstacle = swe_sample.b;
	
	float t = TIME;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	
	vec3 wave_disp = get_waves_displacement(world_pos, t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, tangent, binormal);
	
	float wave_weight = 1.0 - is_obstacle;
	VERTEX.xyz += wave_disp * wave_weight;
	VERTEX.y += swe_h * swe_strength * wave_weight;
	
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_height = VERTEX.y;
	
	vec3 n_vec = cross(binormal, tangent);
	v_normal = normalize(n_vec);
	
	// Jacobian = Vertical component of un-normalized normal (area expansion factor)
	// Lower value = more compression (crests)
	v_jacobian = n_vec.y;
    
    // Calculate SWE Normals via finite difference
    // We utilize the same uv coordinates
    float texel_size = 1.0 / 128.0; // Estimate, or use textureSize
    // Ideally pass grid_res, but hardcoding for safety if uniform missing
    
    float h_r = texture(swe_texture, uv + vec2(texel_size, 0.0)).r;
    float h_l = texture(swe_texture, uv - vec2(texel_size, 0.0)).r;
    float h_d = texture(swe_texture, uv + vec2(0.0, texel_size)).r;
    float h_u = texture(swe_texture, uv - vec2(0.0, texel_size)).r;
    
    // Scale by strength
    float dHx = (h_r - h_l) * swe_strength * 0.5;
    float dHz = (h_d - h_u) * swe_strength * 0.5;
    
    // Perturb existing normal
    // Assuming original normal is roughly (0,1,0), the perturbation is (-dHx, 1, -dHz)
    // We add this perturbation to the wave normal
    vec3 swe_normal_offset = vec3(-dHx, 0.0, -dHz);
    
    // Apply wave weight (obstacles shouldn't have ripples)
    swe_normal_offset *= wave_weight;
    
    // Combine method: distinct separation or direct addition. 
    // Direct addition to n_vec (which is cross product of waves) works well.
    // Note: n_vec is NOT normalized at this point, but v_normal IS.
    
    // We can rotate the n_vec? No, just adding the tilt is sufficient for heightfield
    n_vec += swe_normal_offset * 4.0;
    
	v_normal = normalize(n_vec);
}

void fragment() {
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_raw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_raw.xyz /= view_pos_raw.w;
	
	float geom_dist = length(view_pos_raw.xyz);
	float surface_dist = length(VERTEX);
	float water_depth = max(geom_dist - surface_dist, 0.0);
	
	float absorption = exp(-water_depth * absorption_coeff);
	vec3 sea_color = mix(color_deep.rgb, color_shallow.rgb, absorption);
	
	// Detail Normals (Added safety)
	vec2 normal_uv = v_world_pos.xz * normal_tile * 0.1;
	vec4 n1_sample = texture(normal_map1, normal_uv + TIME * normal_speed);
	vec4 n2_sample = texture(normal_map2, normal_uv * 1.2 - TIME * normal_speed * 1.5);
	
	vec3 detail_normal = vec3(0.0, 1.0, 0.0);
	if (n1_sample.a + n2_sample.a > 0.001) {
		vec3 n1_tex = n1_sample.rgb * 2.0 - 1.0;
		vec3 n2_tex = n2_sample.rgb * 2.0 - 1.0;
		detail_normal = normalize(n1_tex + n2_tex);
	}
	
	vec3 normal = normalize(v_normal + detail_normal * normal_scale);
	float fresnel = pow(1.0 - clamp(dot(normal, VIEW), 0.0, 1.0), 4.0);
	
	// --- Foam System (Jacobian Based) ---
	vec2 foam_uv = v_world_pos.xz * 0.4;
	vec4 f_n1 = texture(foam_noise, foam_uv + TIME * 0.02);
	vec4 f_n2 = texture(foam_noise, foam_uv * 2.5 - TIME * 0.05);
	
	float combined_noise = 0.5;
	if (f_n1.a + f_n2.a > 0.001) {
		combined_noise = (f_n1.r + f_n2.r) * 0.5;
	}

	// Shore Foam
	float shore_mask = clamp(1.0 - water_depth / max(foam_shore_spread, 0.01), 0.0, 1.0);
	float shore_foam = smoothstep(0.4, 0.7, shore_mask + combined_noise * 0.5) * shore_mask * foam_shore_strength;
	
	// Crest Foam (Simplified for Stability)
	// Crest Foam (Jacobian Based - Improved)
	// v_jacobian < 1.0 means compression (crest), > 1.0 means expansion (trough)
	// We want foam when compression is high (jacobian is low)
	float jacobian_signal = 1.0 - v_jacobian; // Positive at crests
	
	// Bias allows shifting the "foam line" up/down the wave
	// foam_jacobian_bias: 0.0 = only very sharp crests, 1.0 = more foam
	float j_threshold = 0.6 - (foam_jacobian_bias * 0.4); 
	
	float crest_base = smoothstep(j_threshold, j_threshold + 0.3, jacobian_signal + combined_noise * 0.3);
	float crest_foam = crest_base * foam_crest_strength;
	
	// Wake Foam (from SWE simulation)
	vec2 swe_uv = (v_world_pos.xz / sea_size) + 0.5;
	float ripple_h = texture(swe_texture, swe_uv).r;
	if (isnan(ripple_h) || isinf(ripple_h)) ripple_h = 0.0;

	// Determine if ripple is significant (signed)
	// Bias foam towards negative height (troughs) or strong turbulence
	// But usually wake foam is visually nice on crests too.
	// We use abs() but with a much higher threshold to avoid "entire surface white"
	float wake_signal = abs(ripple_h);
	
	// Distance mask for SWE to prevent tiling artifacts
	vec2 center_dist_uv = abs(swe_uv - 0.5);
	float swe_mask = 1.0 - smoothstep(0.45, 0.5, max(center_dist_uv.x, center_dist_uv.y));
	
	float wake_foam = smoothstep(0.5, 1.5, wake_signal * swe_mask + combined_noise * 0.2) * foam_wake_strength;
	
	// Better Foam Blending (Control saturation)
	float foam_base = max(shore_foam, max(crest_foam, wake_foam));
	float final_foam = clamp(foam_base, 0.0, 1.0);
	
	vec2 ref_uv = SCREEN_UV + normal.xz * refraction_strength * clamp(water_depth, 0.0, 0.3);
	vec3 ref_color = texture(screen_texture, ref_uv).rgb;
	
	vec3 color = mix(ref_color, sea_color, 1.0 - absorption * 0.4);
	
	// Color modulation by wave height (simpler than mix)
	// Color modulation by wave height (simpler than mix)
	// Reduced intensity and threshold to avoid whole-surface teal flash
	if (abs(ripple_h) > 0.2) {
		color += vec3(0.05, 0.1, 0.15) * (abs(ripple_h) - 0.2) * swe_mask;
	}
	
	// Caustics Integration
	if (water_depth > 0.01 && caustics_strength > 0.0) {
		// Reconstruct world position of the sea floor
		vec3 floor_world_pos = (INV_VIEW_MATRIX * vec4(view_pos_raw.xyz, 1.0)).xyz;
		
		vec2 caustics_uv = floor_world_pos.xz * caustics_scale;
		float speed_val = TIME * caustics_speed;
		
		vec4 c1 = texture(caustics_texture, caustics_uv + vec2(speed_val, speed_val * 0.8));
		vec4 c2 = texture(caustics_texture, caustics_uv * 1.3 - vec2(speed_val, -speed_val * 0.3));
		
		float caustic_val = min(c1.r, c2.r) * 2.0; // Sharpen caustics
		
		// Masking
		// 1. Fade near surface (don't show caustics instantly at water line)
		float depth_mask = smoothstep(0.0, 0.5, water_depth);
		// 2. Fade at extreme depth (light attenuation)
		float attenuation = exp(-water_depth * 0.2);
		
		vec3 caustic_light = vec3(1.0) * caustic_val * caustics_strength * depth_mask * attenuation;
		
		// Add caustics to the background color (refraction color)
		ref_color += caustic_light * 0.8;
	}
	
	color = mix(color, color_foam.rgb, final_foam);
	
	if (debug_show_markers) {
		vec2 grid = fract(v_world_pos.xz * 1.0); 
		float dist = length(grid - 0.5);
		if (dist < 0.05) { color = mix(color, vec3(1.0, 0.0, 0.0), 0.9); }
	}

	ALBEDO = color;
	ALPHA = clamp(water_depth * 10.0, 0.0, 1.0);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	
	// Reflection & Fresnel Highlights
	vec3 fresnel_color = vec3(0.1, 0.2, 0.3) * fresnel_strength;
	EMISSION = fresnel_color * fresnel * (1.0 - final_foam); 
	EMISSION += vec3(1.0) * pow(fresnel, 16.0) * 0.8 * fresnel_strength; // Bright glints at extreme angles
}
