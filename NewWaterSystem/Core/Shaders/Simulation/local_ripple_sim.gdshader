shader_type canvas_item;

// Ping-Pong 波動方程模擬
// SubViewport 的 SCREEN_TEXTURE = 上一幀的結果
// R = 當前高度, G = 前一幀高度

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float damping : hint_range(0.9, 1.0) = 0.997;
uniform float wave_speed : hint_range(0.1, 0.5) = 0.4;

// 衝擊點（最多 8 個同時生效）
uniform vec4 impulses[8];  // xy = UV 座標, z = 強度, w = 半徑
uniform int impulse_count = 0;

void fragment() {
	vec2 uv = UV;
	vec2 texel = SCREEN_PIXEL_SIZE;
	
	// 讀取當前狀態
	vec4 state = texture(screen_tex, uv);
	float h = state.r;       // 當前高度
	float h_prev = state.g;  // 前一幀高度
	
	// 四鄰取樣（波動方程 Laplacian）
	float h_l = texture(screen_tex, uv + vec2(-texel.x, 0.0)).r;
	float h_r = texture(screen_tex, uv + vec2(texel.x, 0.0)).r;
	float h_u = texture(screen_tex, uv + vec2(0.0, -texel.y)).r;
	float h_d = texture(screen_tex, uv + vec2(0.0, texel.y)).r;
	
	// 波動方程：h_new = 2h - h_prev + c²·Laplacian
	float laplacian = h_l + h_r + h_u + h_d - 4.0 * h;
	float h_new = 2.0 * h - h_prev + wave_speed * wave_speed * laplacian;
	
	// 阻尼（能量逐漸消散）
	h_new *= damping;
	
	// ★ HPWater 風格海綿層（Sponge Layer）
	// 邊緣 10% 漸進吸收波浪能量，防止假反射
	float sponge_thickness = 0.10;  // HPWater 用 width * 0.1
	vec2 dist_to_edge = min(uv, vec2(1.0) - uv);
	vec2 edge_factor = smoothstep(vec2(0.0), vec2(sponge_thickness), dist_to_edge);
	float sponge = edge_factor.x * edge_factor.y;
	// 二次方吸收（HPWater: absorption = 1 - (1-edgeX)*(1-edgeY), absorption²）
	float energy_retention = sponge * sponge;
	h_new = mix(0.0, h_new, energy_retention);
	
	// 加入衝擊
	for (int i = 0; i < impulse_count; i++) {
		vec2 imp_uv = impulses[i].xy;
		float imp_str = impulses[i].z;
		float imp_radius = impulses[i].w;
		
		float d = length(uv - imp_uv);
		float imp = imp_str * exp(-d * d / (imp_radius * imp_radius + 0.0001));
		h_new += imp;
	}
	
	// 輸出：R = 新高度, G = 當前高度（下一幀的 "前一幀"）
	COLOR = vec4(h_new, h, 0.0, 1.0);
}
