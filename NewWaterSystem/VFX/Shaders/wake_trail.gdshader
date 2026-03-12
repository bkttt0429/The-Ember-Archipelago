shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// 船隻尾跡泡沫 Shader（簡潔版）
// 純粹的中央漸淡白沫，不使用任何 V 型數學曲線

uniform sampler2D foam_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec2 flow_speed_1 = vec2(0.3, -1.5);
uniform vec2 flow_speed_2 = vec2(-0.2, -0.8);
uniform vec2 uv_scale = vec2(1.0, 3.0);
uniform vec4 base_color : source_color = vec4(0.92, 0.96, 1.0, 0.85);
uniform float erosion_threshold : hint_range(0.0, 1.0) = 0.45;

varying vec4 v_vertex_color;
varying vec3 v_world_pos;

void vertex() {
	v_vertex_color = COLOR;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 世界座標採樣，防止網格擴張時紋理拉伸
	vec2 world_uv = v_world_pos.xz * uv_scale * 0.3;

	// 雙層流動，互相交錯推擠
	vec2 uv1 = world_uv + flow_speed_1 * TIME;
	vec2 uv2 = world_uv * 1.4 + flow_speed_2 * TIME;

	float n1 = texture(foam_texture, uv1).r;
	float n2 = texture(foam_texture, uv2).r;

	// 用第二層雜訊扭曲第一層，增加流體感
	float n1_distorted = texture(foam_texture, uv1 + vec2(n2 * 0.12)).r;
	float foam = mix(n1_distorted, n2, 0.4);

	// === 極簡形狀遮罩：純粹的鐘型中央漸淡 ===
	// 不使用任何 V 型、開爾文波、高斯邊緣線等花俏數學
	// 中心最濃，往兩側自然消散
	float side = smoothstep(1.0, 0.3, abs(UV.x - 0.5) * 2.0);

	// 結合年齡淡出
	float mask = side * v_vertex_color.a;

	// 侵蝕閾值：只有 foam * mask 超過 threshold 的地方才可見
	float alpha = smoothstep(erosion_threshold, erosion_threshold + 0.2, foam * mask * 1.5);

	ALBEDO = base_color.rgb;
	ALPHA = alpha * base_color.a;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
