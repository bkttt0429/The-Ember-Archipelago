shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// 水珠粒子 — Shadertoy 風格著色
uniform vec3 droplet_color : source_color = vec3(0.85, 0.93, 1.0);

void fragment() {
	// 圓形遮罩（SDF 球體投影）
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	float mask = 1.0 - smoothstep(0.7, 1.0, dist);
	
	// === Shadertoy 水珠著色 ===
	
	// 1. Fresnel：邊緣亮，中間透
	float NdotV = max(0.0, dot(normalize(-VERTEX), NORMAL));
	float fresnel = pow(1.0 - NdotV, 3.0);
	
	// 2. 薄膜干涉色（水珠有微妙彩虹）
	float thickness = NdotV * 0.3;
	vec3 iridescence = 0.5 + 0.5 * cos(
		vec3(0.0, 2.094, 4.188) + thickness * 15.0
	);
	
	// 3. SSS：小水珠幾乎全透光
	float sss = pow(max(0.0, dot(normalize(VERTEX), NORMAL)), 5.0) * 0.6;
	
	// 4. 焦散亮點（球體頂部的聚焦反光）
	float caustic = pow(max(0.0, NdotV), 12.0) * 0.8;
	
	// 合成
	vec3 col = droplet_color;
	col = mix(col, iridescence, fresnel * 0.2);  // 微妙彩虹邊
	col += vec3(0.7, 0.85, 1.0) * sss;            // 透光
	
	ALBEDO = col;
	ALPHA = mask * (0.25 + fresnel * 0.75) * COLOR.a;
	
	// 邊緣反光 + 焦散亮點
	EMISSION = droplet_color * fresnel * 0.5 + vec3(1.0) * caustic;
	
	METALLIC = 0.8;
	ROUGHNESS = 0.02;  // 水珠非常光滑
	SPECULAR = 0.5;
	
	if (ALPHA < 0.01) discard;
}
