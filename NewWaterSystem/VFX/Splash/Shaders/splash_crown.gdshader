shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

// ★ 方案 A：Alpha 侵蝕薄膜 Crown
// 不靠頂點拉數來做齒冠，改用平滑碗狀 mesh + Voronoi 侵蝕
// 水花的「撕裂」和「飛散」全由 fragment shader 的 alpha cutoff 驅動

uniform float time : hint_range(0.0, 3.0) = 0.0;
uniform float crown_height : hint_range(0.5, 5.0) = 2.0;
uniform float crown_radius : hint_range(0.3, 3.0) = 0.8;
uniform vec3 water_color : source_color = vec3(0.55, 0.82, 1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

// ═══ Voronoi 細胞雜訊（Alpha 侵蝕用）═══
vec2 voronoi_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// 回傳 (最近距離, 次近距離)  →  邊緣 = f2 - f1
vec2 voronoi(vec2 uv, float scale) {
	vec2 cell = floor(uv * scale);
	vec2 frac_uv = fract(uv * scale);
	float f1 = 1.0, f2 = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = voronoi_hash(cell + neighbor);
			// 動態：讓細胞中心微微跳動
			point = 0.5 + 0.5 * sin(time * 2.5 + 6.2831 * point);
			float d = length(neighbor + point - frac_uv);
			if (d < f1) { f2 = f1; f1 = d; }
			else if (d < f2) { f2 = d; }
		}
	}
	return vec2(f1, f2);
}

// ═══ 簡易 value noise ═══
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
	           mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

void vertex() {
	float angle = atan(VERTEX.x, VERTEX.z);
	float h01 = clamp(VERTEX.y + 0.5, 0.0, 1.0); // 0=底, 1=頂

	// ═══ 平滑碗狀輪廓（不做鋸齒！）═══
	float rise  = smoothstep(0.0, 0.2, time);
	float expand = smoothstep(0.05, 0.35, time);
	float fall  = smoothstep(0.25, 0.8, time);

	// 高度：底部固定，頂部上升並回落
	float height = h01 * crown_height * rise;
	height -= fall * h01 * crown_height * 0.7;

	// 徑向：漏斗形（底窄頂寬），平滑展開
	float funnel = 0.5 + h01 * 0.5;
	float radius = crown_radius * funnel * (1.0 + expand * h01 * 0.4);

	// ★ 只有極輕微的波浪起伏（不是鋸齒），用低頻正弦
	float wave = sin(angle * 5.0 + time * 3.0) * 0.04 * h01;
	height += wave;

	float r = length(VERTEX.xz);
	if (r > 0.001) {
		VERTEX.xz = (VERTEX.xz / r) * radius * (0.4 + h01 * 0.6);
	}
	VERTEX.y = height;
}

void fragment() {
	// ═══ UV 空間：用圓柱展開的 UV ═══
	float angle_uv = UV.x;           // 0~1 繞圓柱一圈
	float height_uv = UV.y;          // 0=底, 1=頂

	// ═══ 1) Voronoi 侵蝕遮罩 ═══
	// 大尺度 Voronoi 細胞：水膜撕裂成大塊
	vec2 vor_large = voronoi(vec2(angle_uv * 3.0, height_uv * 2.0), 4.0);
	float cell_edge_large = vor_large.y - vor_large.x;  // 細胞邊界 = 較亮

	// 小尺度 Voronoi：水珠碎片
	vec2 vor_small = voronoi(vec2(angle_uv * 6.0 + time * 0.3, height_uv * 4.0), 8.0);
	float cell_edge_small = vor_small.y - vor_small.x;

	// ═══ 2) 侵蝕閾值：越往上、越晚越容易被裁切 ═══
	// dissolve=0 → 全實體；dissolve=1 → 全消散
	// 從頂端開始侵蝕（水花頂端先破裂成水珠）
	float erosion_bias = height_uv * 0.6;  // 頂部更容易被侵蝕
	float erosion_threshold = dissolve * 1.4 + erosion_bias;

	// 混合大小 Voronoi 的細胞中心距離作為侵蝕遮罩
	float erosion_mask = mix(vor_large.x, vor_small.x, 0.4);
	// 加上少許 noise 打破規律性
	erosion_mask += vnoise(vec2(angle_uv * 8.0, height_uv * 6.0 + time * 0.5)) * 0.2;

	// ★ 核心 Alpha 裁切：低於閾值的像素被丟棄
	float alpha = smoothstep(erosion_threshold - 0.08, erosion_threshold + 0.08, erosion_mask);

	// ═══ 3) 邊緣高光（撕裂邊緣發亮 — 水的表面張力）═══
	float edge_glow = smoothstep(0.04, 0.0, abs(erosion_mask - erosion_threshold)) * 0.8;

	// ═══ 4) Fresnel + 水色 ═══
	float NdotV = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - NdotV, 2.5);

	vec3 col = mix(water_color * 0.75, vec3(0.92, 0.97, 1.0), fresnel * 0.5);
	// 邊緣散射（側面偏青藍）
	col += vec3(0.0, 0.06, 0.12) * (1.0 - NdotV);
	// 細胞邊界微亮（水膜厚薄差異）
	col += vec3(0.15) * cell_edge_large * (1.0 - dissolve);
	// 撕裂邊緣高光
	col += vec3(0.9, 0.95, 1.0) * edge_glow;

	// ═══ 5) 底部不透明，頂部半透明（薄膜感）═══
	float thickness_alpha = mix(0.9, 0.25, height_uv);

	ALBEDO = col;
	ALPHA = alpha * thickness_alpha;
	METALLIC = 0.05;
	ROUGHNESS = 0.04;
	SPECULAR = 0.95;
	// SSS 透光（水體特有的藍色背光）
	EMISSION = water_color * (0.08 + fresnel * 0.2 + edge_glow * 0.3) * (1.0 - dissolve);

	if (ALPHA < 0.01) discard;
}
