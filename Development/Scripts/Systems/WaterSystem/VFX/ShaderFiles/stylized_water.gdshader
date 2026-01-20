/*
	Stylized Water Shader - Refactored for "The Last Night" Aesthetic
	Optimized with Domain Warping & FBM for Natural Layering
	Technical Artist Revision 2.0
*/

shader_type spatial;
render_mode cull_disabled, depth_draw_always, diffuse_toon, specular_toon;

// --- Uniforms ---
uniform float sync_time;

group_uniforms Visual_Overhaul;
uniform vec3 shallow_color : source_color = vec3(0.25, 0.7, 0.85);
uniform vec3 mid_color : source_color = vec3(0.1, 0.45, 0.65);
uniform vec3 deep_color : source_color = vec3(0.05, 0.25, 0.45);
uniform float depth_band_1 : hint_range(0.0, 20.0) = 5.0;
uniform float depth_band_2 : hint_range(0.0, 50.0) = 15.0;

uniform vec3 foam_outer_color : source_color = vec3(0.9, 0.95, 1.0);
uniform float foam_outer_extent : hint_range(0.0, 1.0) = 0.2;
uniform float color_saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.0;
uniform float color_bands : hint_range(1.0, 8.0) = 1.0;
uniform float shimmer_intensity : hint_range(0.0, 5.0) = 1.2;

group_uniforms Wave_System_FBM;
uniform float wave_speed = 0.1;
uniform float height_scale = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform vec2 flow_direction = vec2(1.0, 0.0);

// Domain Warping (打破规律性)
uniform float warp_strength : hint_range(0.0, 5.0) = 1.0;
uniform float warp_scale : hint_range(0.0, 0.2) = 0.05;

// Layered Noise (自然层次)
uniform sampler2D vertex_noise_big : repeat_enable; // Reverted name to match Material
uniform float noise_scale_base : hint_range(0.0, 0.2) = 0.04;
uniform float noise_amp_base : hint_range(0.0, 5.0) = 1.5;
uniform float noise_scale_detail : hint_range(0.0, 0.5) = 0.15;
uniform float noise_amp_detail : hint_range(0.0, 2.0) = 0.5;
uniform float noise_scale_micro : hint_range(0.0, 1.0) = 0.4;
uniform float noise_amp_micro : hint_range(0.0, 1.0) = 0.2;

// Shaping (波形塑形)
uniform float wave_peak_power : hint_range(1.0, 4.0) = 1.5; // 波峰尖锐度
uniform float wave_trough_flatten : hint_range(0.0, 1.0) = 0.3; // 波谷平坦度

group_uniforms Waterspout;
uniform vec3 waterspout_pos = vec3(0.0);
uniform float waterspout_radius = 5.0;
uniform float waterspout_strength = 3.0;
uniform float waterspout_spiral_strength : hint_range(0.0, 20.0) = 8.0;
uniform int waterspout_spiral_arms : hint_range(1, 10) = 4;
uniform float waterspout_foam_ring_inner : hint_range(0.0, 10.0) = 2.0;
uniform float waterspout_foam_ring_outer : hint_range(0.0, 15.0) = 5.0;
uniform float waterspout_darkness_factor : hint_range(0.0, 1.0) = 0.8;

group_uniforms Foam_System;
uniform vec3 foam_color : source_color = vec3(1.0);
uniform float foam_opacity : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D foam_tex : repeat_enable;
uniform float foam_crest_threshold : hint_range(0.0, 5.0) = 0.8; // 重新调整阈值以适应 FBM
uniform float foam_crest_extent : hint_range(0.0, 1.0) = 0.2;
uniform float foam_shore_threshold : hint_range(0.0, 2.0) = 0.25;
uniform float foam_shore_extent : hint_range(0.0, 2.0) = 0.2;
uniform sampler2D foam_mask : filter_nearest;
uniform float foam_mask_size = 10.0;
// Legacy uniforms kept to avoid script errors
uniform float ripple_height_scale = 0.3;
uniform vec4 wave_a; uniform vec4 wave_b; uniform vec4 wave_c; uniform vec4 wave_d; uniform vec4 wave_e;

uniform vec3 sky_color : source_color;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture;

varying float v_height;
varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_noise_debug;

// --- Math Helpers ---
vec2 rotate_uv(vec2 uv, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec2(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

// 获取噪声值 (0.0 to 1.0)
float get_noise(vec2 uv) {
	return texture(vertex_noise_big, uv).r;
}

// 核心：基于 FBM 和 Domain Warping 的位移函数
float get_wave_height_fbm(vec3 p) {
	vec2 base_uv = p.xz;
	float time = sync_time * wave_speed;
	
	// 1. Domain Warping (坐标扭曲)
	// 使用低频噪声来偏移采样坐标，打破网格感
	vec2 warp_offset = vec2(
		get_noise(base_uv * warp_scale + vec2(time * 0.5, time * 0.2)),
		get_noise(base_uv * warp_scale - vec2(time * 0.3, time * 0.6))
	);
	vec2 warped_uv = base_uv + (warp_offset - 0.5) * warp_strength;
	
	// 2. Layered Noise (三层 FBM)
	float h = 0.0;
	
	// Layer A: Base Swell (大浪)
	// 调整：降低 noise_scale_base 以获得更大的波浪
	float n1 = get_noise(warped_uv * 0.015 + vec2(time, time * 0.8));
	// Shaping: Smoothstep 让波峰更圆润，pow 让波峰更尖
	n1 = smoothstep(wave_trough_flatten, 1.0, n1); 
	n1 = pow(n1, wave_peak_power);
	h += (n1 - 0.5) * noise_amp_base;
	
	// Layer B: Detail (中层细节, 旋转角度以增加混乱感)
	vec2 uv2 = rotate_uv(warped_uv, 1.0); // 旋转 1 弧度
	float n2 = get_noise(uv2 * 0.05 - vec2(time * 1.5, 0.0));
	n2 = smoothstep(0.2, 1.0, n2);
	h += (n2 - 0.5) * noise_amp_detail;
	
	// Layer C: Micro (细碎波纹)
	float n3 = get_noise(base_uv * 0.15 + vec2(0.0, time * 2.0)); // 不 Warp 保持细碎感
	h += (n3 - 0.5) * noise_amp_micro;
	
	return h * height_scale;
}

// 获取总位移，包含 Waterspout
vec3 get_total_displacement(vec3 p) {
	float h = get_wave_height_fbm(p);
	
	// Ripple Overlay (Simple noise add)
	float ripples = texture(vertex_noise_big, p.xz * 0.2 + sync_time * 0.2).r * ripple_height_scale;
	h += ripples;
	
	vec3 disp = vec3(0.0, h, 0.0);
	
	// Waterspout Displacement
	float dist_to_spout = distance(p.xz, waterspout_pos.xz);
	if (dist_to_spout < waterspout_radius * 2.0) {
		float spout_m = 1.0 - step(waterspout_radius, dist_to_spout);
		disp.y -= spout_m * waterspout_strength * (1.0 - dist_to_spout / waterspout_radius);
	}
	
	return disp;
}

// 有限差分法计算法线 (Finite Difference)
// 适用于无法解析求导的复杂 FBM 波形
vec3 get_normal_finite(vec3 p) {
	float e = 0.1; // 采样间距
	vec3 p_c = get_total_displacement(p);
	vec3 p_x = get_total_displacement(p + vec3(e, 0.0, 0.0));
	vec3 p_z = get_total_displacement(p + vec3(0.0, 0.0, e));
	
	// 计算切线向量
	vec3 tangent_x = vec3(e, p_x.y - p_c.y, 0.0);
	vec3 tangent_z = vec3(0.0, p_z.y - p_c.y, e);
	
	// 叉积得法线
	vec3 normal_dir = cross(tangent_z, tangent_x);
	float len = length(normal_dir);
	if (len < 0.0001) {
		return vec3(0.0, 1.0, 0.0);
	}
	return normalize(normal_dir);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// 计算位移
	vec3 disp = get_total_displacement(v_world_pos);
	VERTEX += disp;
	v_height = disp.y;
	
	// 计算法线
	v_normal = get_normal_finite(v_world_pos);
	NORMAL = v_normal;
}

void fragment() {
	// --- Depth Color Logic (3-Band Hard Edge) ---
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	float depth_diff = depth_band_2 * 2.0; // 默认深海
	
	if (depth_raw < 1.0) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view_pos.xyz /= view_pos.w;
		vec4 world_pos = INV_VIEW_MATRIX * view_pos;
		depth_diff = abs(world_pos.y - v_world_pos.y);
	}
	depth_diff = clamp(depth_diff, 0.0, depth_band_2 * 2.0);
	
	// 3-Band Color Quantization
	vec3 water_color;
	if (depth_diff < depth_band_1) {
		water_color = shallow_color; // 浅水带
	} else if (depth_diff < depth_band_2) {
		water_color = mid_color; // 中深带
	} else {
		water_color = deep_color; // 深水带
	}
	
	// Apply saturation
	vec3 grayscale = vec3(dot(water_color, vec3(0.299, 0.587, 0.114)));
	water_color = mix(grayscale, water_color, color_saturation);
	
	// --- Flat Shading Geometry (Key Technique) ---
	// 重算法线以获得"折纸"般的硬边几何感
	// 注意：这会忽略 vertex shader 中的法线平滑，强制面法线
	vec3 flat_normal = normalize(cross(dFdy(v_world_pos), dFdx(v_world_pos)));
	NORMAL = flat_normal;

	// --- Foam Logic (Dual-Layer Hard Edge) ---
	// 动态调整泡沫阈值：基于波高和噪声
	// 使用 Flat Normal 的向上分量检测陡峭度
	float steepness_factor = clamp(1.0 - flat_normal.y, 0.0, 1.0); 
	float height_factor = smoothstep(0.0, 1.0, v_height * 0.5 + 0.5);
	
	// Foam Noise
	vec2 flow_offset = flow_direction * sync_time * wave_speed;
	float foam_noise = texture(foam_tex, v_world_pos.xz * 0.1 + flow_offset).r;
	
	// Crest Foam Calculation
	float crest_trigger = steepness_factor * 1.2 + height_factor * 0.6 + foam_noise * 0.4;
	
	// Dual-Layer Steps
	// Layer 1 (Outer): 较宽，稍暗或半透明
	float is_crest_outer = step(foam_crest_threshold - 0.3, crest_trigger); // 阈值较低
	// Layer 2 (Inner): 核心，纯白
	float is_crest_core = step(foam_crest_threshold, crest_trigger); // 阈值较高
	
	// Exclude inner from outer for layering logic if needed, or just overlay
	float is_crest_only_outer = is_crest_outer * (1.0 - is_crest_core);
	
	// Shore Foam
	float is_shore = 1.0 - step(foam_shore_threshold, depth_diff + foam_noise * foam_shore_extent);

	// --- Visuals ---
	vec3 final_albedo = water_color;
	
	// Apply Shore Foam
	final_albedo = mix(final_albedo, foam_color, is_shore * foam_opacity);
	
	// Apply Dual-Layer Crest Foam
	// Outer layer (Darker/Translucent)
	final_albedo = mix(final_albedo, foam_outer_color, is_crest_only_outer * foam_opacity * 0.8);
	// Core layer (Bright White)
	final_albedo = mix(final_albedo, foam_color, is_crest_core * foam_opacity);

	// --- Waterspout Visuals ---
	float dist_to_spout = distance(v_world_pos.xz, waterspout_pos.xz);
	if (dist_to_spout < waterspout_radius * 2.0) {
		vec2 rel = v_world_pos.xz - waterspout_pos.xz;
		float r = length(rel);
		float theta = atan(rel.y, rel.x) + r * 0.2 + sync_time * 2.0;
		float ring_mask = smoothstep(waterspout_foam_ring_inner, waterspout_foam_ring_outer, r) * 
						  (1.0 - smoothstep(waterspout_foam_ring_outer - 1.0, waterspout_foam_ring_outer + 2.0, r));
		float spiral_noise = texture(foam_tex, vec2(r * 0.1, theta)).r;
		float spout_foam = step(0.4, spiral_noise * ring_mask);
		
		final_albedo = mix(final_albedo, foam_color, spout_foam * foam_opacity);
		
		float abyss = smoothstep(waterspout_radius, 0.0, r);
		final_albedo = mix(final_albedo, vec3(0.01), abyss * waterspout_darkness_factor);
	}

	ALBEDO = final_albedo;
	ROUGHNESS = roughness;
}

void light() {
	float NdotL = max(0.0, dot(NORMAL, LIGHT));
	
	// Cel Shading Ramp
	float diff = smoothstep(0.0, 0.1, NdotL) * 0.5 + 0.5; // Softer toon
	diff = floor(diff * 3.0) / 3.0; // 3 Bands
	
	// Ambient
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * diff * 0.8 + (ALBEDO * 0.2);
	
	// Specular
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = max(0.0, dot(NORMAL, H));
	float spec_thresh = 0.95 - roughness * 0.2;
	float spec = step(spec_thresh, NdotH);
	SPECULAR_LIGHT += LIGHT_COLOR * spec * ATTENUATION * (1.0 - roughness) * 0.2;
}
