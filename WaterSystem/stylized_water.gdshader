/*
	Pixel Water Shader by: Taillight Games - contact@taillight.games
	Optimized and Modified for The Ember Archipelago
	MIT License
*/

shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_always, diffuse_burley, specular_schlick_ggx;

// --- Physical Context ---
uniform float sync_time; 

// --- Visual Overhaul (Prompt C) ---
group_uniforms Visual_Overhaul;
uniform vec3 shallow_color : source_color = vec3(0.0, 0.7, 0.9);
uniform vec3 mid_color : source_color = vec3(0.0, 0.4, 0.7);
uniform vec3 deep_color : source_color = vec3(0.0, 0.2, 0.4);
uniform float depth_band_1 : hint_range(0.0, 20.0) = 0.5;
uniform float depth_band_2 : hint_range(0.0, 50.0) = 5.0;

uniform vec3 foam_outer_color : source_color = vec3(0.1, 0.3, 0.5); // Double layered foam edge
uniform float foam_outer_extent : hint_range(0.0, 1.0) = 0.2;
uniform float color_saturation : hint_range(0.0, 2.0) = 1.2;

// --- Waterspout (Prompt B) ---
group_uniforms Waterspout;
uniform vec3 waterspout_pos = vec3(0.0, -100.0, 0.0);
uniform float waterspout_radius = 5.0;
uniform float waterspout_strength = 0.0;

// --- Existing Uniforms Retained ---
group_uniforms Basic;
uniform float wave_speed = 0.05;
uniform float height_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed = 0.5;
uniform sampler2D vertex_noise_big : repeat_enable;
uniform float ripple_height_scale = 0.1;

group_uniforms Gerstner_Waves;
uniform vec4 wave_a = vec4(1.0, 0.0, 0.15, 10.0);
uniform vec4 wave_b = vec4(0.0, 1.0, 0.15, 20.0);
uniform vec4 wave_c = vec4(0.7, 0.7, 0.1, 5.0);
uniform vec4 wave_d = vec4(-0.5, 0.5, 0.08, 3.0);
uniform vec4 wave_e = vec4(0.2, -0.8, 0.05, 1.5);

group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(1.0);
uniform float foam_opacity : hint_range(0.0, 1.0) = 0.8;
uniform sampler2D foam_tex : repeat_enable;
uniform float foam_crest_threshold : hint_range(0.0, 5.0) = 1.35;
uniform float foam_crest_extent : hint_range(0.0, 1.0) = 0.2;
uniform float foam_shore_threshold : hint_range(0.0, 2.0) = 0.25;
uniform float foam_shore_extent : hint_range(0.0, 2.0) = 0.5;
uniform sampler2D foam_mask : filter_nearest;
uniform float foam_mask_size = 10.0;

uniform vec3 sky_color : source_color;
uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D depth_texture : hint_depth_texture;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_normal;

// --- Helper Functions ---
float remap(float in_low, float in_high, float out_low, float out_high, float value) {
	return out_low + (value - in_low) * (out_high - out_low) / (in_high - in_low);
}

vec3 gerstner_wave(vec4 wave_params, vec3 p) {
	float steepness = wave_params.z;
	float wavelength = wave_params.w;
	float k = 2.0 * 3.14159 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave_params.xy);
	float f = k * (dot(d, p.xz) - c * sync_time * wave_speed);
	float a = steepness / k;
	return vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
}

vec3 get_displacement(vec3 p) {
	vec3 disp = vec3(0.0);
	disp += gerstner_wave(wave_a, p);
	disp += gerstner_wave(wave_b, p);
	disp += gerstner_wave(wave_c, p);
	disp += gerstner_wave(wave_d, p);
	disp += gerstner_wave(wave_e, p);
	
	// APPLY GLOBAL SCALE
	disp *= height_scale;
	
	// Waterspout Displacement (Prompt B)
	float dist_to_spout = distance(p.xz, waterspout_pos.xz);
	if (dist_to_spout < waterspout_radius * 2.0) {
		float spout_m = 1.0 - step(waterspout_radius, dist_to_spout);
		// Funnel downward
		disp.y -= spout_m * waterspout_strength * (1.0 - dist_to_spout / waterspout_radius);
		// Spin effect in vertex? Usually better in Frag but we can tilt normals here
	}
	
	return disp;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 disp = get_displacement(v_world_pos);
	
	// Add Noise Ripples
	float ripples = texture(vertex_noise_big, v_world_pos.xz * 0.05 + sync_time * 0.01).r * ripple_height_scale;
	disp.y += ripples;
	
	VERTEX += disp;
	v_height = disp.y;
	
	// Normal Calculation (Finite Difference)
	float e = 0.05;
	vec3 p = v_world_pos;
	vec3 d_c = get_displacement(p);
	vec3 d_r = get_displacement(p + vec3(e, 0, 0));
	vec3 d_f = get_displacement(p + vec3(0, 0, e));
	vec3 tangent = normalize(vec3(e, d_r.y - d_c.y, 0));
	vec3 binormal = normalize(vec3(0, d_f.y - d_c.y, e));
	NORMAL = normalize(cross(binormal, tangent));
	v_normal = NORMAL;
}

void fragment() {
	// --- Depth Color Banding (Prompt C) ---
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	float depth_diff = linear_depth - VERTEX.z;
	
	// Hard Banding instead of lerp
	vec3 water_color = deep_color;
	water_color = mix(water_color, mid_color * color_saturation, 1.0 - step(depth_band_2, depth_diff));
	water_color = mix(water_color, shallow_color * color_saturation, 1.0 - step(depth_band_1, depth_diff));
	
	// --- Double Layered Foam (Prompt C) ---
	// 1. Shore/Contact Foam
	float shore_foam_mask = 1.0 - step(foam_shore_threshold, depth_diff);
	float shore_outer_mask = (1.0 - step(foam_shore_extent, depth_diff)) * step(foam_shore_threshold, depth_diff);
	
	// 2. Crest Foam
	vec2 flow_offset = flow_direction * sync_time * flow_speed;
	float crest_noise = texture(foam_tex, v_world_pos.xz * 0.1 + flow_offset).r;
	float crest_foam_mask = step(foam_crest_threshold, v_height + crest_noise);
	float crest_outer_mask = step(foam_crest_threshold - foam_crest_extent, v_height + crest_noise) * (1.0 - crest_foam_mask);
	
	// Integrate Foam
	vec3 final_albedo = water_color;
	
	// Apply Outer Edge Foam (Darker/Blueish)
	float total_outer = clamp(shore_outer_mask + crest_outer_mask, 0.0, 1.0);
	final_albedo = mix(final_albedo, foam_outer_color, total_outer);
	
	// Apply Core Foam (Pure White with Opacity)
	float total_foam = clamp(shore_foam_mask + crest_foam_mask, 0.0, 1.0);
	final_albedo = mix(final_albedo, foam_color, total_foam * foam_opacity);

	// Wake Foam (from mask)
	vec2 wake_uv = (v_world_pos.xz - NODE_POSITION_WORLD.xz + vec2(foam_mask_size/2.0)) / foam_mask_size;
	float wake_raw = texture(foam_mask, wake_uv).r;
	float wake_foam = step(0.5, wake_raw * crest_noise * 1.5);
	final_albedo = mix(final_albedo, foam_color, wake_foam * foam_opacity);

	ALBEDO = final_albedo;
	ROUGHNESS = roughness;
	
	// Subtle Fresnel for reflection
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(ALBEDO, sky_color, fresnel * 0.3);
}

void light() {
	// Simple Toon Lighting for Hard Edges
	float NdotL = dot(NORMAL, LIGHT);
	float diff = step(0.2, NdotL * ATTENUATION);
	
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * diff * 0.8;
	
	// Specular highlight (Hard)
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = dot(NORMAL, H);
	float spec = step(0.98, pow(NdotH, 64.0));
	SPECULAR_LIGHT += LIGHT_COLOR * spec * ATTENUATION;
}
