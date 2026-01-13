shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

// Inline WaterWaves.gdshaderinc logic for self-containment
// Redundant PI removed

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

vec3 get_waves_displacement(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, inout vec3 tangent, inout vec3 binormal) {
    vec3 disp = vec3(0.0);
    
    // 8-Layer Wave Data
    float wave_data[32] = float[](
        wave_length, wave_steepness, 1.0, 0.0,
        wave_length * 1.3, wave_steepness * 0.7, 0.8, 1.1,
        wave_length * 0.6, wave_steepness * 0.9, 1.5, 2.4,
        wave_length * 0.3, wave_steepness * 1.2, 2.1, -0.6,
        wave_length * 2.1, wave_steepness * 0.4, 0.6, 4.3,
        wave_length * 0.8, wave_steepness * 0.8, 1.3, -1.2,
        wave_length * 0.45, wave_steepness * 1.0, 1.9, 5.2,
        wave_length * 1.7, wave_steepness * 0.3, 0.5, 0.7
    );

    // Normalize steepness to prevent self-intersection (fractures)
    float total_relative_steepness = 0.0;
    for (int i = 0; i < 8; i++) total_relative_steepness += wave_data[i * 4 + 1];
    
    float steepness_norm = 1.0;
    if (wave_steepness * total_relative_steepness > 0.9) {
        steepness_norm = 0.9 / (wave_steepness * total_relative_steepness);
    }

    float base_angle = atan(wind_dir.y, wind_dir.x);

    for (int i = 0; i < 8; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx];
        float w_steep = wave_data[idx+1] * wind_strength * wave_steepness * steepness_norm;
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * wave_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        disp += gerstner_wave(pos, t, d, w_len, w_steep, w_speed, tangent, binormal);
    }
    
    // Fix: Ensure noise is also suppressed when wind is 0
    if (wind_strength > 0.001) {
        float noise = sin(pos.x * 2.0 + t) * cos(pos.z * 2.0 - t * 0.5) * 0.2;
        disp.y += noise * wind_strength * wave_chaos;
    }
    
    return disp;
}
// End of inlined logic

uniform sampler2D swe_texture : hint_default_black, filter_linear, repeat_disable; 
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
uniform float absorption_coeff = 1.2;
uniform float refraction_strength = 0.03;

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 1.0;

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

uniform sampler2D foam_noise : repeat_enable; 
uniform sampler2D normal_map1 : hint_normal, repeat_enable;
uniform sampler2D normal_map2 : hint_normal, repeat_enable;

uniform float normal_scale : hint_range(0.0, 2.0) = 0.5;
uniform float normal_speed : hint_range(0.0, 0.5) = 0.1;
uniform float normal_tile : hint_range(1.0, 100.0) = 20.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec2 v_swe_uv;
varying vec3 v_world_pos;
varying vec3 v_wave_normal;
varying float v_jacobian_proxy;

void vertex() {
	v_swe_uv = (VERTEX.xz / sea_size) + 0.5;
	v_swe_uv = clamp(v_swe_uv, 0.0, 1.0);
	
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Sample SWE for displacement
	vec4 swe_sample = texture(swe_texture, v_swe_uv);
	float swe_h = swe_sample.r;
	float is_obstacle = swe_sample.b;
	float wave_weight = 1.0 - is_obstacle;
	
	// Gerstner Waves
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 wave_disp = vec3(0.0);
	
	if (wind_strength > 0.001) {
		wave_disp = get_waves_displacement(world_pos, TIME, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, tangent, binormal);
		v_wave_normal = normalize(cross(binormal, tangent));
		v_jacobian_proxy = cross(binormal, tangent).y;
	} else {
		v_wave_normal = vec3(0.0, 1.0, 0.0);
		v_jacobian_proxy = 1.0;
	}
	
	VERTEX.xyz += wave_disp; 
	VERTEX.y += swe_h * swe_strength * wave_weight;
	
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. Depth & Water Color
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_raw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_raw.xyz /= view_pos_raw.w;
	
	float geom_dist = length(view_pos_raw.xyz);
	float surface_dist = length(VERTEX);
	float water_depth = max(geom_dist - surface_dist, 0.0);
	
	float absorption = exp(-water_depth * absorption_coeff);
	vec3 sea_color = mix(color_deep.rgb, color_shallow.rgb, absorption);
	
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
	vec3 normal = normalize(v_wave_normal + ripple_n_offset);
	
	// Detail Normals
	vec2 normal_uv = v_world_pos.xz * normal_tile * 0.1;
	vec3 n1_sample = texture(normal_map1, normal_uv + TIME * normal_speed).rgb * 2.0 - 1.0;
	vec3 n2_sample = texture(normal_map2, normal_uv * 1.2 - TIME * normal_speed * 1.5).rgb * 2.0 - 1.0;
	vec3 detail_normal = normalize(n1_sample + n2_sample);
	
	normal = normalize(normal + detail_normal * normal_scale);
	float fresnel = pow(1.0 - clamp(dot(normal, VIEW), 0.0, 1.0), 4.0);
	
	// 4. Foam System
	vec2 foam_uv = v_world_pos.xz * 0.4;
	float f_n1 = texture(foam_noise, foam_uv + TIME * 0.02).r;
	float f_n2 = texture(foam_noise, foam_uv * 2.5 - TIME * 0.05).r;
	
	// Normalize and filter combined noise to avoid noise floor triggering foam
	float combined_noise = (f_n1 * 0.5 + f_n2 * 0.5);
	combined_noise = smoothstep(0.4, 0.6, combined_noise);

	// Shore Foam
	float shore_mask = clamp(1.0 - water_depth / max(foam_shore_spread, 0.01), 0.0, 1.0);
	float shore_foam = smoothstep(0.4, 0.7, shore_mask + combined_noise * 0.5) * shore_mask * foam_shore_strength;
	
	// Crest & Wake Foam (Improved: require signal > 0 to avoid noise-only foam)
	float jacobian_signal = clamp(1.0 - v_jacobian_proxy, 0.0, 1.0); 
	float j_threshold = 0.6 - (foam_jacobian_bias * 0.4); 
	float crest_foam = 0.0;
	if (jacobian_signal > 0.05 && wind_strength > 0.1) {
		crest_foam = smoothstep(j_threshold, j_threshold + 0.3, jacobian_signal * (0.6 + combined_noise * 0.4)) * foam_crest_strength;
	}
	
	float ripple_h = texture(swe_texture, v_swe_uv).r;
	float wake_signal = max(abs(ripple_h) * swe_strength, 0.0) + weather_danger * 2.0;
	float wake_foam = 0.0;
	if (wake_signal > 0.2) {
		wake_foam = smoothstep(0.2, 1.0, wake_signal + combined_noise * 0.1) * foam_wake_strength;
	}
	
	float final_foam = clamp(max(shore_foam, max(crest_foam, wake_foam)), 0.0, 1.0);
	
	// 5. Shading
	vec2 ref_uv = SCREEN_UV + normal.xz * refraction_strength * clamp(water_depth, 0.0, 0.3);
	vec3 ref_color = texture(screen_texture, ref_uv).rgb;
	
	vec3 color = mix(ref_color, sea_color, 1.0 - absorption * 0.4);
	
	// Caustics
	if (water_depth > 0.01 && caustics_strength > 0.0) {
		vec3 floor_world_pos = (INV_VIEW_MATRIX * vec4(view_pos_raw.xyz, 1.0)).xyz;
		vec2 caustics_uv = floor_world_pos.xz * caustics_scale;
		float speed_val = TIME * caustics_speed;
		float c1 = texture(caustics_texture, caustics_uv + vec2(speed_val, speed_val * 0.8)).r;
		float c2 = texture(caustics_texture, caustics_uv * 1.3 - vec2(speed_val, -speed_val * 0.3)).r;
		float caustic_val = min(c1, c2) * 2.0; 
		ref_color += vec3(1.0) * caustic_val * caustics_strength * smoothstep(0.0, 0.5, water_depth) * exp(-water_depth * 0.2);
	}
	
	color = mix(color, color_foam.rgb, final_foam);
	
	ALBEDO = color;
	ALPHA = clamp(water_depth * 10.0, 0.0, 1.0);
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	
	vec3 fresnel_color = vec3(0.1, 0.2, 0.3) * fresnel_strength;
	EMISSION = fresnel_color * fresnel * (1.0 - final_foam); 
	EMISSION += vec3(1.0) * pow(fresnel, 16.0) * 0.8 * fresnel_strength; 
}
