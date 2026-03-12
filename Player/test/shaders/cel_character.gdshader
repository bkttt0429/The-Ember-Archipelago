shader_type spatial;
render_mode ambient_light_disabled;

// 角色專用賽璐璜 shader
// 支援 Diffuse 貼圖 + Normal Map + 色階化光照

// === 貼圖 ===
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform bool use_normal_map = true;

// === 陰影設定 ===
uniform vec4 shadow_color : source_color = vec4(0.4, 0.35, 0.45, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.45;
uniform float shadow_smoothness : hint_range(0.001, 0.3) = 0.04;

// === 第二陰影（可選的更深陰影層） ===
uniform bool use_second_shadow = false;
uniform vec4 second_shadow_color : source_color = vec4(0.2, 0.15, 0.25, 1.0);
uniform float second_shadow_threshold : hint_range(0.0, 1.0) = 0.2;

// === 邊緣光 (Rim Light) ===
uniform vec4 rim_color : source_color = vec4(0.8, 0.85, 0.9, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.1;
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;
uniform bool rim_follows_light = true;

// === 高光色階帶 (Specular Band) ===
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular_threshold : hint_range(0.0, 1.0) = 0.85;
uniform float specular_smoothness : hint_range(0.001, 0.2) = 0.03;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// 基礎顏色（貼圖 × 色調）
	vec4 tex_color = texture(albedo_texture, UV);
	ALBEDO = tex_color.rgb * albedo_tint.rgb;
	ALPHA = tex_color.a;

	// 法線貼圖
	if (use_normal_map) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}

	// 邊緣光
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = pow(rim, rim_power) * rim_amount;

	// rim_follows_light 模式下，邊緣光存入 emission
	// 下面的 light() 會根據光照方向調整
	if (!rim_follows_light) {
		EMISSION = rim_color.rgb * rim;
	}
	// 如果跟隨光照，rim 值透過 varying 或在 light() 中重新計算
}

void light() {
	// === 色階化漫反射 ===
	float NdotL = dot(NORMAL, LIGHT) * 0.5 + 0.5;

	// 主陰影
	float shadow = smoothstep(
		shadow_threshold - shadow_smoothness,
		shadow_threshold + shadow_smoothness,
		NdotL
	);

	vec3 lit_color;
	if (use_second_shadow) {
		// 三段式：深陰影 → 淺陰影 → 亮面
		float deep_shadow = smoothstep(
			second_shadow_threshold - shadow_smoothness,
			second_shadow_threshold + shadow_smoothness,
			NdotL
		);
		vec3 shadow_mix = mix(second_shadow_color.rgb * ALBEDO, shadow_color.rgb * ALBEDO, deep_shadow);
		lit_color = mix(shadow_mix, ALBEDO, shadow);
	} else {
		// 兩段式：陰影 → 亮面
		lit_color = mix(shadow_color.rgb * ALBEDO, ALBEDO, shadow);
	}

	DIFFUSE_LIGHT += lit_color * ATTENUATION;

	// === 色階化高光帶 ===
	vec3 half_dir = normalize(LIGHT + VIEW);
	float NdotH = dot(NORMAL, half_dir) * 0.5 + 0.5;
	float spec = smoothstep(
		specular_threshold - specular_smoothness,
		specular_threshold + specular_smoothness,
		NdotH
	);
	SPECULAR_LIGHT += specular_color.rgb * spec * specular_strength * ATTENUATION;

	// === 光照方向邊緣光 ===
	if (rim_follows_light) {
		float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
		rim = pow(rim, rim_power) * rim_amount;
		// 邊緣光只在光照面顯示
		float rim_mask = smoothstep(0.2, 0.5, NdotL);
		DIFFUSE_LIGHT += rim_color.rgb * rim * rim_mask * ATTENUATION;
	}
}
