/*
	Pixel Water Shader by: Taillight Games - contact@taillight.games
	Optimized and Modified for The Ember Archipelago
	MIT License
*/

shader_type spatial;
// 优化：符合 DesignRules - Low-Poly Flat Shading (平面着色)
// Flat Shading：每个面统一颜色，硬边光照
render_mode cull_disabled, depth_draw_always, diffuse_toon, specular_toon;

// --- Physical Context ---
uniform float sync_time; 

// --- Visual Overhaul (符合 DesignRules: Low-Poly Flat Shading 海水风格) ---
group_uniforms Visual_Overhaul;
// Low-Poly 海水风格：硬边、Flat Shading、清晰的色彩分层
// 修复：调整颜色和深度阈值，避免过浅
uniform vec3 shallow_color : source_color = vec3(0.15, 0.55, 0.75); // 海蓝偏绿（修复：从 0.4,0.8,1.0 降低）
uniform vec3 mid_color : source_color = vec3(0.05, 0.35, 0.55); // 深海蓝（修复：从 0.1,0.5,0.8 降低）
uniform vec3 deep_color : source_color = vec3(0.0, 0.15, 0.35); // 深海深蓝（修复：从 0.0,0.2,0.4 降低）
uniform float depth_band_1 : hint_range(0.0, 20.0) = 5.0; // 浅水区域（修复：从 2.0 → 5.0）
uniform float depth_band_2 : hint_range(0.0, 50.0) = 15.0; // 深水区域（修复：从 6.0 → 15.0）

uniform vec3 foam_outer_color : source_color = vec3(0.9, 0.95, 1.0); // 白色泡沫（Low-Poly 风格）
uniform float foam_outer_extent : hint_range(0.0, 1.0) = 0.2;
uniform float color_saturation : hint_range(0.0, 2.0) = 1.2; // 适中的饱和度（海水风格）

// Low-Poly Flat Shading 风格参数
uniform float contrast : hint_range(0.5, 2.0) = 1.0; // 对比度（默认 1.0 = 无效果）
uniform float color_bands : hint_range(1.0, 8.0) = 1.0; // 色彩阶数（默认 1.0 = 无量化）
uniform float shimmer_intensity : hint_range(0.0, 2.0) = 0.8; // 闪烁强度（海水风格：适中）

// --- Waterspout (Prompt B + Realism Enhancement) ---
group_uniforms Waterspout;
uniform vec3 waterspout_pos = vec3(0.0);
uniform float waterspout_radius = 5.0;
uniform float waterspout_strength = 3.0;
uniform float waterspout_spiral_strength : hint_range(0.0, 20.0) = 8.0;
uniform int waterspout_spiral_arms : hint_range(1, 10) = 4;
uniform float waterspout_foam_ring_inner : hint_range(0.0, 10.0) = 2.0;
uniform float waterspout_foam_ring_outer : hint_range(0.0, 15.0) = 5.0;
uniform float waterspout_darkness_factor : hint_range(0.0, 1.0) = 0.8;

// --- Existing Uniforms Retained ---
group_uniforms Basic;
uniform float wave_speed = 0.18;  // 优化：从 0.05 增加到 0.18
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
uniform float foam_opacity : hint_range(0.0, 1.0) = 0.6;
uniform sampler2D foam_tex : repeat_enable;
uniform float foam_crest_threshold : hint_range(0.0, 5.0) = 2.8;
uniform float foam_crest_extent : hint_range(0.0, 1.0) = 0.2;
uniform float foam_shore_threshold : hint_range(0.0, 2.0) = 0.25;
uniform float foam_shore_extent : hint_range(0.0, 2.0) = 0.2;
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

vec3 gerstner_wave(vec4 wave_params, vec3 p, float phase_offset) {
	float steepness = wave_params.z;
	float wavelength = wave_params.w;
	float k = 2.0 * 3.14159 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave_params.xy);
	
	// Perturb sampling position with noise to break perfect lines
	float noise_p = texture(vertex_noise_big, p.xz * 0.02 + sync_time * 0.05).r * 2.0;
	float f = k * (dot(d, p.xz + noise_p) - c * (sync_time + phase_offset) * wave_speed);
	
	float a = steepness / k;
	return vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
}

// 优化：Gerstner 波的解析法线计算（单个波）
// 返回法线的贡献（未归一化，height_scale 在最后统一应用）
vec3 gerstner_wave_normal(vec4 wave_params, vec3 p, float phase_offset) {
	float steepness = wave_params.z;
	float wavelength = wave_params.w;
	
	// 安全检查：避免除以零或无效波长
	if (wavelength < 0.001) {
		return vec3(0.0);
	}
	
	float k = 2.0 * 3.14159 / wavelength;
	float c = sqrt(9.8 / k);
	
	// 安全检查：避免归一化零向量
	vec2 wave_dir = wave_params.xy;
	float dir_len_sq = dot(wave_dir, wave_dir);
	if (dir_len_sq < 0.000001) {
		return vec3(0.0);
	}
	vec2 d = normalize(wave_dir);
	
	// 使用相同的 noise 扰动以保持一致性
	float noise_p = texture(vertex_noise_big, p.xz * 0.02 + sync_time * 0.05).r * 2.0;
	float f = k * (dot(d, p.xz + noise_p) - c * (sync_time + phase_offset) * wave_speed);
	
	// 安全检查：避免无效的 steepness
	if (abs(k) < 0.0001) {
		return vec3(0.0);
	}
	
	float a = steepness / k;
	
	// 解析法线计算：对位移函数求偏导数
	// 对于 Gerstner 波，法线的 xz 分量来自波的倾斜
	// 法线 ≈ (-d.x * k * A * sin(f), 1 - k * A * cos(f), -d.y * k * A * sin(f))
	// 注意：这里返回的是相对于垂直方向的偏移
	vec3 normal_contrib = vec3(
		-d.x * k * a * sin(f),
		-k * a * cos(f),  // y 分量的变化（相对于 1.0）
		-d.y * k * a * sin(f)
	);
	
	// 安全检查：防止 NaN 或 Inf
	if (any(isnan(normal_contrib)) || any(isinf(normal_contrib))) {
		return vec3(0.0);
	}
	
	return normal_contrib;
}

vec3 get_displacement(vec3 p) {
	vec3 disp = vec3(0.0);
	disp += gerstner_wave(wave_a, p, 0.0);
	disp += gerstner_wave(wave_b, p, 1.4);
	disp += gerstner_wave(wave_c, p, 2.7);
	disp += gerstner_wave(wave_d, p, 4.1);
	disp += gerstner_wave(wave_e, p, 6.3);
	
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

// 优化：使用解析法线计算（替代有限差分）
// 性能提升：减少 2 次 get_displacement() 调用
vec3 get_normal_analytical(vec3 p) {
	// 1. 计算所有 Gerstner 波的法线贡献
	vec3 normal_sum = vec3(0.0, 1.0, 0.0); // 从垂直向上开始（y = 1.0）
	
	// 累加所有波的法线贡献
	vec3 wave_normal = gerstner_wave_normal(wave_a, p, 0.0);
	wave_normal += gerstner_wave_normal(wave_b, p, 1.4);
	wave_normal += gerstner_wave_normal(wave_c, p, 2.7);
	wave_normal += gerstner_wave_normal(wave_d, p, 4.1);
	wave_normal += gerstner_wave_normal(wave_e, p, 6.3);
	
	// 应用 height_scale（统一应用）
	wave_normal *= height_scale;
	
	// 组合到法线（y 分量是 1.0 + 变化）
	normal_sum.x += wave_normal.x;
	normal_sum.y += wave_normal.y; // y 从 1.0 开始，加上变化
	normal_sum.z += wave_normal.z;
	
	// 2. 考虑 Ripples 对法线的影响（使用梯度采样）
	// 因为 ripples 是 noise texture，我们需要采样梯度
	float e = 0.1;
	vec2 ripple_uv = p.xz * 0.05 + sync_time * 0.01;
	float ripple_c = texture(vertex_noise_big, ripple_uv).r;
	float ripple_r = texture(vertex_noise_big, ripple_uv + vec2(e, 0.0)).r;
	float ripple_f = texture(vertex_noise_big, ripple_uv + vec2(0.0, e)).r;
	
	vec2 ripple_gradient = vec2(
		(ripple_r - ripple_c) / e,
		(ripple_f - ripple_c) / e
	) * ripple_height_scale * 0.05; // 0.05 是 UV scale
	
	// 将 ripple 梯度添加到法线（ripple 增加高度，法线向下倾斜）
	normal_sum.x -= ripple_gradient.x;
	normal_sum.z -= ripple_gradient.y;
	
	// 3. 考虑 Waterspout 对法线的影响（简化处理）
	float dist_to_spout = distance(p.xz, waterspout_pos.xz);
	if (dist_to_spout < waterspout_radius * 2.0 && waterspout_strength > 0.01 && dist_to_spout > 0.001) {
		// 安全检查：避免除以零（当距离太小时）
		vec2 to_spout_dir = p.xz - waterspout_pos.xz;
		float dist_sq = dot(to_spout_dir, to_spout_dir);
		if (dist_sq > 0.000001) { // 避免归一化零向量
			vec2 to_spout = normalize(to_spout_dir);
			float spout_influence = smoothstep(waterspout_radius * 2.0, 0.0, dist_to_spout);
			// Waterspout 会产生向内的法线倾斜
			normal_sum.xz += to_spout * spout_influence * waterspout_strength * 0.1;
		}
	}
	
	// 安全检查：确保法线有效（防止 NaN）
	float normal_len = length(normal_sum);
	if (normal_len < 0.0001 || isnan(normal_len) || isinf(normal_len)) {
		// 如果法线无效，返回默认向上法线
		return vec3(0.0, 1.0, 0.0);
	}
	
	return normalize(normal_sum);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 disp = get_displacement(v_world_pos);
	
	// Add Noise Ripples
	float ripples = texture(vertex_noise_big, v_world_pos.xz * 0.05 + sync_time * 0.01).r * ripple_height_scale;
	disp.y += ripples;
	
	VERTEX += disp;
	v_height = disp.y;
	
	// 优化：使用解析法线计算（减少 2 次 get_displacement() 调用）
	vec3 computed_normal = get_normal_analytical(v_world_pos);
	
	// 最终安全检查：确保法线有效
	if (any(isnan(computed_normal)) || any(isinf(computed_normal)) || length(computed_normal) < 0.1) {
		// 回退到默认向上法线
		computed_normal = vec3(0.0, 1.0, 0.0);
	}
	
	NORMAL = computed_normal;
	v_normal = NORMAL;
}

void fragment() {
	// --- Depth Color Banding (The Last Night 风格：硬边、高对比) ---
	// 修复：简化深度计算，避免复杂转换导致的问题
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	
	// 计算深度差（水面到海底的距离）
	float depth_diff = 0.0;
	if (depth_raw < 1.0) { // 有效深度值
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
		vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view_pos.xyz /= view_pos.w;
		
		// 计算水面到海底的距离
		vec4 world_pos = INV_VIEW_MATRIX * view_pos;
		depth_diff = abs(world_pos.y - v_world_pos.y);
	} else {
		// 如果没有有效深度（天空或无限远），使用默认浅水
		depth_diff = depth_band_1 * 0.5;
	}
	
	// 确保深度值有效
	depth_diff = clamp(depth_diff, 0.0, depth_band_2 * 2.0);
	
	// --- Low-Poly Flat Shading 风格：硬边色彩分离（海水） ---
	// 1. 硬边色彩分层（符合 Flat Shading：每个区域统一颜色）
	vec3 water_color = deep_color;
	
	// Low-Poly 风格：使用硬边 step，无平滑过渡
	// 浅水：depth_diff < depth_band_1
	// 中水：depth_band_1 <= depth_diff < depth_band_2  
	// 深水：depth_diff >= depth_band_2
	float is_shallow = step(depth_diff, depth_band_1); // 浅水 = 1
	float is_mid = step(depth_band_1, depth_diff) * step(depth_diff, depth_band_2); // 中水 = 1
	
	// 硬边混合（Flat Shading：无渐变）
	water_color = mix(water_color, mid_color * color_saturation, is_mid);
	water_color = mix(water_color, shallow_color * color_saturation, is_shallow);
	
	// 2. 色彩量化（可选，Low-Poly 风格）
	if (color_bands > 1.0) {
		water_color = floor(water_color * color_bands) / color_bands;
	}
	
	// 3. 对比度（可选，保持海水自然感）
	if (contrast > 1.0) {
		water_color = (water_color - 0.5) * contrast + 0.5;
		water_color = clamp(water_color, 0.0, 1.0);
	}
	
	// 2. Crest Foam Logic (Low-Poly 风格：硬边泡沫)
	vec2 flow_offset = flow_direction * sync_time * flow_speed;
	float crest_noise = texture(foam_tex, v_world_pos.xz * 0.05 + flow_offset).r;
	
	// 动态阈值
	float peak_threshold = height_scale * 1.5; 
	if (foam_crest_threshold > 0.1) peak_threshold = foam_crest_threshold;
	
	// 适中的闪烁效果（海水风格：自然动态）
	float pulse = 0.5 + 0.5 * sin(sync_time * 2.0 + v_world_pos.x * 0.5);
	float shimmer = sin(sync_time * 3.0 + v_world_pos.x * 0.2 + v_world_pos.z * 0.3) * shimmer_intensity;
	
	// 硬边泡沫遮罩（Flat Shading：使用 step 创建硬边）
	float crest_foam_mask = step(peak_threshold, v_height + crest_noise * 0.5 + pulse * 0.2 + shimmer * 0.1);
	float crest_outer_mask = step(peak_threshold - foam_crest_extent, v_height + crest_noise * 0.5 + pulse * 0.2 + shimmer * 0.1) * (1.0 - crest_foam_mask);
	
	vec3 final_albedo = water_color;
	
	// --- Waterspout Visuals ---
	float dist_to_spout = distance(v_world_pos.xz, waterspout_pos.xz);
	
	// A. Spiral Foam Texture
	vec2 rel_pos = v_world_pos.xz - waterspout_pos.xz;
	float r = length(rel_pos);
	float theta = atan(rel_pos.y, rel_pos.x);
	
	// Spiral distortion
	float spiral_theta = theta + r * 0.1 * waterspout_spiral_strength + sync_time * 2.0;
	vec2 spiral_uv = vec2(r * 0.1, spiral_theta * float(waterspout_spiral_arms) / 6.28);
	float spout_foam_noise = texture(foam_tex, spiral_uv).r;
	
	// B. Foam Ring Mask (Swapped arguments to fix global white-out)
	float spout_ring_mask = smoothstep(waterspout_foam_ring_inner, (waterspout_foam_ring_inner + waterspout_foam_ring_outer) * 0.5, r) * 
						   (1.0 - smoothstep((waterspout_foam_ring_inner + waterspout_foam_ring_outer) * 0.5, waterspout_foam_ring_outer, r));
	
	float spout_spiral_mask = smoothstep(waterspout_radius * 1.5, waterspout_radius * 0.5, r);
	float spout_final_mask = step(0.4, spout_foam_noise * (spout_ring_mask + spout_spiral_mask * 0.5));
	
	// --- RESTORING FINAL ALBEDO ---
	// Apply Spout Foam
	final_albedo = mix(final_albedo, foam_color, spout_final_mask * foam_opacity);
	
	// Merge Wave Foam
	final_albedo = mix(final_albedo, foam_outer_color, crest_outer_mask * foam_opacity * (1.0 - spout_final_mask));
	final_albedo = mix(final_albedo, foam_color, crest_foam_mask * foam_opacity * (1.0 - spout_final_mask));
	
	// C. Center Darkness (Abyss)
	float abyss_mask = smoothstep(waterspout_radius, 0.0, r);
	final_albedo = mix(final_albedo, vec3(0.005, 0.015, 0.04), abyss_mask * waterspout_darkness_factor);
	
	// D. Shore/Contact Foam (Subtle)
	float shore_foam_mask = 1.0 - step(foam_shore_threshold, depth_diff);
	final_albedo = mix(final_albedo, foam_color, shore_foam_mask * foam_opacity * 0.6);

	// Low-Poly Flat Shading：最终色彩处理
	// 只在参数有效时应用效果
	if (color_bands > 1.0) {
		final_albedo = floor(final_albedo * color_bands) / color_bands;
	}
	if (contrast > 1.0) {
		final_albedo = (final_albedo - 0.5) * contrast + 0.5;
		final_albedo = clamp(final_albedo, 0.0, 1.0);
	}
	
	// 确保海水颜色不为黑色（最小亮度保护）
	float min_brightness = 0.15; // 海水应该有一定亮度
	float brightness = dot(final_albedo, vec3(0.299, 0.587, 0.114));
	if (brightness < min_brightness) {
		final_albedo = mix(vec3(0.1, 0.3, 0.5), final_albedo, brightness / min_brightness); // 混合到海水蓝
	}
	
	ALBEDO = final_albedo;
	ROUGHNESS = 0.8; // Flat Shading：高粗糙度（低反射，符合 Low-Poly 风格）
	
	// The Last Night 风格：硬边 Fresnel（可选）
	// float fresnel = step(0.7, 1.0 - dot(NORMAL, VIEW)); // 硬边反射
	// ALBEDO = mix(ALBEDO, sky_color * 1.2, fresnel * 0.2);
}

void light() {
	// Low-Poly Flat Shading：硬边 Toon Lighting
	float NdotL = dot(NORMAL, LIGHT);
	
	// Flat Shading：硬边光照（2-3 阶，符合 Low-Poly 风格）
	float toon_levels = 3.0;
	float diff_raw = NdotL * ATTENUATION;
	float diff = floor(diff_raw * toon_levels) / toon_levels;
	diff = step(0.05, diff); // Low-Poly：更低的阈值，确保有光照
	
	// 基础环境光（海水应该有一定亮度）
	float ambient = 0.4; // 海水环境光（比之前更亮）
	diff = max(diff, ambient);
	
	// Flat Shading：统一的光照强度
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * diff * 1.3;
	
	// 硬边高光（Low-Poly 风格：清晰的高光）
	vec3 H = normalize(VIEW + LIGHT);
	float NdotH = dot(NORMAL, H);
	float spec = step(0.85, pow(NdotH, 24.0)); // 硬边高光
	SPECULAR_LIGHT += LIGHT_COLOR * spec * ATTENUATION * 1.2; // 适中的高光强度
}
