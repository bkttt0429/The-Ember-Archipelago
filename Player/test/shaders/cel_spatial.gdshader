shader_type spatial;
render_mode ambient_light_disabled;

// 賽璐璜風格 - 使用 light() 接收場景燈光
// 適用於場景物件（地板、障礙物、樓梯等）
// ambient_light_disabled: 停用環境光，避免與 cel shading 疊加過亮

// === 基礎顏色 ===
uniform vec4 base_color : source_color = vec4(0.3, 0.35, 0.4, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float uv_scale : hint_range(0.1, 50.0) = 1.0;

// === 陰影 ===
uniform vec4 shadow_color : source_color = vec4(0.15, 0.15, 0.2, 1.0);
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float shadow_smoothness : hint_range(0.001, 0.3) = 0.05;

// === 邊緣光 (Rim Light) ===
uniform vec4 rim_color : source_color = vec4(0.6, 0.65, 0.7, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.15;
uniform float rim_power : hint_range(1.0, 8.0) = 3.0;

// === 高光色階帶 (Specular Band) ===
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular_threshold : hint_range(0.0, 1.0) = 0.8;
uniform float specular_smoothness : hint_range(0.001, 0.2) = 0.05;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// 基礎顏色
	vec2 scaled_uv = UV * uv_scale;
	if (use_texture) {
		ALBEDO = texture(albedo_texture, scaled_uv).rgb * base_color.rgb;
	} else {
		ALBEDO = base_color.rgb;
	}

	// 邊緣光（在 fragment 中計算，與光源無關）
	float rim = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	rim = pow(rim, rim_power) * rim_amount;
	EMISSION = rim_color.rgb * rim;
}

void light() {
	// === 色階化漫反射 (Cel Diffuse) ===
	float NdotL = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float shadow = smoothstep(
		shadow_threshold - shadow_smoothness,
		shadow_threshold + shadow_smoothness,
		NdotL
	);

	// 明暗兩段式：陰影區用 shadow_color 著色，亮面保持原色
	vec3 diffuse = mix(shadow_color.rgb * ALBEDO, ALBEDO, shadow);
	DIFFUSE_LIGHT += diffuse * ATTENUATION;

	// === 色階化高光 (Cel Specular) ===
	vec3 half_dir = normalize(LIGHT + VIEW);
	float NdotH = dot(NORMAL, half_dir) * 0.5 + 0.5;
	float spec = smoothstep(
		specular_threshold - specular_smoothness,
		specular_threshold + specular_smoothness,
		NdotH
	);
	SPECULAR_LIGHT += specular_color.rgb * spec * specular_strength * ATTENUATION;
}
