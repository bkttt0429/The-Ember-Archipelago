shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;

// ★ Kelvin 風格漣漪 — 透明、有形狀、自然擴散
// 真實水面漣漪特徵：
// 1. 波紋隨距離拉長波長（色散 dispersion）
// 2. 前方波紋較密，後方較疏
// 3. 高頻細節在遠處消失（深水 capillary 效應）

uniform float time : hint_range(0.0, 5.0) = 0.0;
uniform float ring_count : hint_range(1.0, 12.0) = 6.0;
uniform float ring_speed : hint_range(0.5, 5.0) = 2.5;
uniform float normal_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float fade_power : hint_range(0.5, 4.0) = 1.5;
uniform float dispersion : hint_range(0.0, 1.0) = 0.5;  // 波長色散（越大越不均勻）

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	vec2 dir = centered / max(dist, 0.001);
	
	// === 生命週期衰減 ===
	float life = clamp(time / 3.0, 0.0, 1.0);
	float fade = pow(1.0 - life, fade_power);
	
	// === 真實色散：近處高頻、遠處低頻 ===
	// 深水重力波色散關係：ω² = gk → 長波走得快、短波走得慢
	// 反映在視覺上：靠近中心的環間距小（高頻），外圍間距大（低頻）
	float dispersed_dist = pow(max(dist, 0.001), 1.0 + dispersion * 0.5);
	
	// === 擴張的同心環（帶色散）===
	float expanding_radius = time * ring_speed;
	float phase = dispersed_dist * ring_count * 6.2832 - expanding_radius * 6.2832;
	
	// === 包絡線：只在波前附近顯示 ===
	// 真實漣漪的波前向外擴張，內部逐漸平靜
	float wave_front = dist / max(time * ring_speed * 0.2, 0.01);
	float envelope = smoothstep(0.0, 0.3, wave_front) * smoothstep(1.3, 0.7, wave_front);
	
	// 中心平靜區（漣漪源頭不會永遠震盪）
	float inner_fade = smoothstep(0.0, 0.15, dist);
	
	// === 波形：sin + 高頻諧波 ===
	float wave = sin(phase) * 0.7 + sin(phase * 2.1 + 0.5) * 0.2 + sin(phase * 3.7) * 0.1;
	wave *= envelope * inner_fade * fade;
	
	// === 邊緣圓形遮罩（柔和淡出）===
	float edge = 1.0 - smoothstep(0.8, 1.0, dist);
	wave *= edge;
	
	// === 1/r 衰減（真實水波能量守恆）===
	float amplitude_decay = 1.0 / (1.0 + dist * 3.0);
	wave *= amplitude_decay;
	
	// === 法線計算（解析梯度，非 ddx/ddy）===
	// ∂wave/∂dist 的解析導數用於精確法線
	float dphase_dr = (1.0 + dispersion * 0.5) * pow(max(dist, 0.001), dispersion * 0.5) * ring_count * 6.2832;
	float slope = (cos(phase) * 0.7 + cos(phase * 2.1 + 0.5) * 0.2 * 2.1 + cos(phase * 3.7) * 0.1 * 3.7);
	slope *= dphase_dr * envelope * inner_fade * fade * edge * amplitude_decay;
	
	vec3 normal_out = vec3(0.0, 0.0, 1.0);
	normal_out.xy = dir * slope * normal_intensity * -0.08;
	normal_out = normalize(normal_out);
	
	// === 輸出 ===
	NORMAL_MAP = normal_out * 0.5 + 0.5;
	
	// ★ 透明波紋：微白色光澤 + 折射感
	float highlight = max(wave, 0.0);
	float shadow = max(-wave, 0.0);
	vec3 ripple_color = vec3(0.85, 0.92, 1.0) * highlight * 0.4 + vec3(0.0, 0.05, 0.15) * shadow * 0.2;
	ALBEDO = ripple_color;
	ALPHA = (abs(wave) * 0.5 + highlight * 0.15) * 0.7;
	
	if (ALPHA < 0.005) discard;
}
