shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// ★ 改良擴散環 — 透明水面光澤，帶法線擾動
uniform float ring_inner : hint_range(0.0, 1.0) = 0.3;
uniform float ring_outer : hint_range(0.0, 1.0) = 0.5;
uniform float ring_softness : hint_range(0.01, 0.3) = 0.08;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	vec2 dir = centered / max(dist, 0.001);
	
	// 環形遮罩（更柔和的過渡）
	float inner = smoothstep(ring_inner - ring_softness, ring_inner + ring_softness * 0.5, dist);
	float outer = 1.0 - smoothstep(ring_outer - ring_softness * 0.5, ring_outer + ring_softness, dist);
	float ring = inner * outer;
	
	// ★ 環內微波紋（真實擴散環有微小波動）
	float micro_wave = sin(dist * 60.0) * 0.15 + 0.85;
	ring *= micro_wave;
	
	// ★ 透明光澤效果（不是純白色）
	// 真實水波：高處反射光（亮），低處折射光（暗）
	float ring_phase = (dist - ring_inner) / max(ring_outer - ring_inner, 0.001);
	float wave_shape = sin(ring_phase * 3.14159);
	
	// 光澤色：微帶藍的白色反射
	vec3 highlight = vec3(0.9, 0.95, 1.0) * max(wave_shape, 0.0) * 0.3;
	vec3 shadow = vec3(0.0, 0.05, 0.1) * max(-wave_shape, 0.0) * 0.15;
	
	ALBEDO = highlight + shadow;
	ALPHA = ring * COLOR.a * 0.5;
	
	// 微弱發光（模擬反射）
	EMISSION = vec3(0.7, 0.85, 1.0) * ring * 0.08;
	
	if (ALPHA < 0.005) discard;
}
