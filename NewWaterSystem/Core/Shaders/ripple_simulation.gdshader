shader_type canvas_item;
// GPU 波動方程模擬著色器 v10
// ★ 單次迭代 + 雙半徑取樣 + 風場偏移
// ★ UV 偏移補償 + 輸出防爆 clamp

uniform sampler2D prev_state : filter_linear;

uniform float damping : hint_range(0.90, 0.999) = 0.993;

// UV 偏移補償
uniform vec2 uv_offset = vec2(0.0);

// 衝擊（10 點尾流）
uniform vec2 impulse_pos_0 = vec2(-1.0);
uniform vec2 impulse_pos_1 = vec2(-1.0);
uniform vec2 impulse_pos_2 = vec2(-1.0);
uniform vec2 impulse_pos_3 = vec2(-1.0);
uniform vec2 impulse_pos_4 = vec2(-1.0);
uniform vec2 impulse_pos_5 = vec2(-1.0);
uniform vec2 impulse_pos_6 = vec2(-1.0);
uniform vec2 impulse_pos_7 = vec2(-1.0);
uniform vec2 impulse_pos_8 = vec2(-1.0);
uniform vec2 impulse_pos_9 = vec2(-1.0);
uniform float impulse_radius = 0.03;
uniform float impulse_strength = 0.05;

// ★ C8: 風場偏移 — 讓波紋往下風處傳播更快
uniform vec2 wind_uv_bias = vec2(0.0);

uniform bool is_first_frame = true;

void fragment() {
	if (is_first_frame) {
		COLOR = vec4(0.5, 0.5, 0.0, 1.0);
	} else {
		vec2 texel = vec2(1.0) / vec2(textureSize(prev_state, 0));

		// 限制 UV 偏移（防止快速移動爆炸）
		vec2 max_offset = texel * 4.0;
		vec2 safe_offset = clamp(uv_offset, -max_offset, max_offset);
		vec2 shifted_uv = UV + safe_offset;

		// 超出邊界 → 中性值
		bool oob = (shifted_uv.x < 0.0 || shifted_uv.x > 1.0 ||
		            shifted_uv.y < 0.0 || shifted_uv.y > 1.0);

		float current_h, prev_h;
		float p_up, p_down, p_left, p_right;
		float p_up2, p_down2, p_left2, p_right2;

		if (oob) {
			current_h = 0.5; prev_h = 0.5;
			p_up = 0.5; p_down = 0.5; p_left = 0.5; p_right = 0.5;
			p_up2 = 0.5; p_down2 = 0.5; p_left2 = 0.5; p_right2 = 0.5;
		} else {
			current_h = texture(prev_state, shifted_uv).r;
			prev_h    = texture(prev_state, shifted_uv).g;

			// ★ 雙半徑取樣：1x texel（高頻細節）
			p_up    = texture(prev_state, shifted_uv + vec2(0.0, -texel.y)).r;
			p_down  = texture(prev_state, shifted_uv + vec2(0.0,  texel.y)).r;
			p_left  = texture(prev_state, shifted_uv + vec2(-texel.x, 0.0)).r;
			p_right = texture(prev_state, shifted_uv + vec2( texel.x, 0.0)).r;

			// ★ 2x texel（低頻傳播 — 讓波紋跑更遠）
			p_up2    = texture(prev_state, shifted_uv + vec2(0.0, -texel.y * 2.0)).r;
			p_down2  = texture(prev_state, shifted_uv + vec2(0.0,  texel.y * 2.0)).r;
			p_left2  = texture(prev_state, shifted_uv + vec2(-texel.x * 2.0, 0.0)).r;
			p_right2 = texture(prev_state, shifted_uv + vec2( texel.x * 2.0, 0.0)).r;
		}

		// ★★★ 風場偏移波動方程 ★★★
		// 近鄰 (1x)
		float w_up    = 1.0 - wind_uv_bias.y * 0.3;  // 上（-Y）
		float w_down  = 1.0 + wind_uv_bias.y * 0.3;  // 下（+Y）
		float w_left  = 1.0 - wind_uv_bias.x * 0.3;  // 左（-X）
		float w_right = 1.0 + wind_uv_bias.x * 0.3;  // 右（+X）
		float w_sum = w_up + w_down + w_left + w_right;
		
		float near_avg = (p_up * w_up + p_down * w_down + p_left * w_left + p_right * w_right) / w_sum;
		// 遠鄰 (2x) — 同樣的偏移
		float far_avg  = (p_up2 * w_up + p_down2 * w_down + p_left2 * w_left + p_right2 * w_right) / w_sum;
		float blended_avg = near_avg * 0.6 + far_avg * 0.4;

		float new_h = blended_avg * 2.0 - prev_h;

		// 阻尼
		new_h = 0.5 + (new_h - 0.5) * damping;

		// 邊界吸收
		float edge_x = min(UV.x, 1.0 - UV.x);
		float edge_y = min(UV.y, 1.0 - UV.y);
		float edge_min = min(edge_x, edge_y);
		float edge_absorb = smoothstep(0.0, 0.08, edge_min);
		new_h = mix(0.5, new_h, edge_absorb);

		// === 衝擊 ===
		vec2 impulse_positions[10] = vec2[10](
			impulse_pos_0, impulse_pos_1, impulse_pos_2, impulse_pos_3, impulse_pos_4,
			impulse_pos_5, impulse_pos_6, impulse_pos_7, impulse_pos_8, impulse_pos_9
		);

		for (int i = 0; i < 10; i++) {
			vec2 ip = impulse_positions[i];
			if (ip.x >= 0.0 && ip.x <= 1.0 && ip.y >= 0.0 && ip.y <= 1.0) {
				float dist = length(UV - ip);
				if (dist < impulse_radius) {
					float norm_dist = dist / impulse_radius;
					float falloff = (1.0 - norm_dist * norm_dist);
					falloff *= falloff;
					new_h -= impulse_strength * falloff;
				}
			}
		}

		// 防爆 clamp
		new_h = clamp(new_h, 0.1, 0.9);
		current_h = clamp(current_h, 0.1, 0.9);

		COLOR = vec4(new_h, current_h, 0.0, 1.0);
	}
}
