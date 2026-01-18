shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// 🌊 桶浪專用 Shader（增強版）
// 包含：透明度修復、SSS增強、切線空間法線、內部高光、泡沫分層、顏色梯度、曲面擾動

// === 基礎顏色 ===
uniform vec4 color_deep : source_color = vec4(0.0, 0.1, 0.3, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.0, 0.5, 0.7, 1.0);
uniform vec4 color_foam : source_color = vec4(0.9, 0.95, 1.0, 1.0);

// === 表面屬性 ===
uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;
uniform float fresnel_strength : hint_range(0.0, 3.0) = 1.5;

// === 法線貼圖 ===
uniform sampler2D normal_map1 : hint_normal;
uniform sampler2D normal_map2 : hint_normal;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.5;
uniform float normal_tile : hint_range(0.01, 1.0) = 0.1;
uniform float normal_speed : hint_range(0.0, 0.5) = 0.02;

// === 泡沫 ===
uniform sampler2D foam_noise : hint_default_white;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.4;

// === 生命週期 ===
uniform float alpha_mult : hint_range(0.0, 1.0) = 1.0;

// === SSS ===
uniform float sss_strength : hint_range(0.0, 2.0) = 0.8;
uniform vec4 sss_color : source_color = vec4(0.0, 0.6, 0.5, 1.0);

// === Step 7: 曲面擾動 ===
uniform float surface_disturbance : hint_range(0.0, 1.0) = 0.3;
uniform float disturbance_scale : hint_range(0.01, 0.2) = 0.05;

// === Varying ===
varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_arc_position;
varying float v_water_thickness;  // Step 1: 水體厚度
varying float v_edge_blend;       // Step 1: 邊緣混合
varying vec3 v_tangent;           // Step 3: 切線方向
varying vec3 v_wave_normal;       // Step 3: 原始波浪法線

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_arc_position = UV.x;  // 0 = 後方, 1 = 唇部
	
	// Step 1: 從 COLOR 獲取厚度和邊緣數據（由 BarrelWaveMeshGenerator 設置）
	// COLOR.r = edge_blend, COLOR.g = water_thickness (normalized), COLOR.b = arc_position
	v_edge_blend = COLOR.r;
	v_water_thickness = COLOR.g * 3.0;  // 還原到實際厚度範圍 (0-3)
	
	// Step 3: 計算切線方向（沿弧形）
	v_tangent = normalize((MODEL_MATRIX * vec4(TANGENT.xyz, 0.0)).xyz);
	v_wave_normal = v_world_normal;
	
	// Step 7: 非均勻曲面擾動
	float surface_noise_val = texture(foam_noise, v_world_pos.xz * disturbance_scale + TIME * 0.01).r;
	float disturbance = (surface_noise_val - 0.5) * surface_disturbance * v_arc_position;
	
	// 頂點擾動
	VERTEX.y += disturbance;
	VERTEX.xz += NORMAL.xz * disturbance * 0.5;
	
	// 更新世界位置
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// 粗略法線更新
	vec3 neighbor_offset = vec3(0.1, 0.0, 0.0);
	float neighbor_noise = texture(foam_noise, (v_world_pos.xz + neighbor_offset.xz) * disturbance_scale + TIME * 0.01).r;
	float slope = (neighbor_noise - surface_noise_val) * surface_disturbance * v_arc_position;
	v_world_normal = normalize(v_world_normal + vec3(slope, 0.0, slope) * 0.5);
}

void fragment() {
	// 觀察方向
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	// === Step 3: 切線空間法線流動 ===
	vec3 tangent_world = normalize(v_tangent);
	vec3 binormal_world = normalize(cross(v_wave_normal, tangent_world));
	
	// 投影世界坐標到切線空間
	float u_tangent = dot(v_world_pos, tangent_world);
	float v_binormal = dot(v_world_pos, binormal_world);
	
	// 生成UV（考慮曲率）
	vec2 curved_uv = vec2(u_tangent, v_binormal) * normal_tile * 0.1;
	
	// 流速隨弧形位置變化（唇部更快）
	float flow_speed_mult = mix(0.5, 2.5, smoothstep(0.3, 0.9, v_arc_position));
	
	// 添加時間偏移
	vec2 flow_offset = normalize(v_tangent.xz + vec2(0.001)) * TIME * normal_speed * flow_speed_mult;
	vec2 uv1 = curved_uv + flow_offset;
	vec2 uv2 = curved_uv * 1.2 - flow_offset * 0.7;
	
	vec3 n1 = texture(normal_map1, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map2, uv2).rgb * 2.0 - 1.0;
	vec3 detail_normal = normalize(vec3((n1.xy + n2.xy) * normal_scale, 1.0));
	
	// 混合幾何法線和細節法線
	vec3 final_normal = normalize(v_world_normal + detail_normal * 0.3);
	
	// === Fresnel ===
	float fresnel = pow(1.0 - max(dot(final_normal, view_dir), 0.0), 4.0);
	
	// === Step 6: 顏色深度梯度（增強厚度感）===
	// 🔥 關鍵：底部厚水牆需要更深、更不透明的效果
	
	// 基於厚度的顏色（底部厚 = 深色，唇部薄 = 亮色）
	float thickness_factor = clamp(v_water_thickness / 2.0, 0.0, 1.0);
	
	// 厚水區域使用更深的顏色
	vec3 very_deep_color = color_deep.rgb * 0.6;  // 底部最深處
	vec3 thick_water_color = mix(very_deep_color, color_deep.rgb, v_arc_position);
	vec3 thin_water_color = color_shallow.rgb * 1.3;  // 薄水更亮
	
	// 顏色隨厚度和弧形位置變化
	vec3 depth_color = mix(thin_water_color, thick_water_color, thickness_factor);
	
	// 環境光遮蔽（底部內側更暗，模擬厚水牆的陰影）
	float ao = mix(0.4, 1.0, v_arc_position);  // 底部暗 40%（更強的陰影）
	ao *= mix(0.7, 1.0, v_edge_blend);  // 邊緣也稍暗
	
	vec3 sea_color = depth_color * ao;
	
	// === Step 5: 泡沫分層 ===
	// Layer 1: 底部翻滾泡沫（大塊、慢速）
	float bottom_foam = 0.0;
	if (v_arc_position < 0.4) {
		vec2 bottom_uv = v_world_pos.xz * 0.2 + TIME * 0.01;
		float bottom_noise = texture(foam_noise, bottom_uv).r;
		bottom_foam = smoothstep(0.6, 0.9, bottom_noise) * (0.4 - v_arc_position) * 2.0;
	}
	
	// Layer 2: 唇部爆炸泡沫（小塊、高速）
	float lip_foam = 0.0;
	if (v_arc_position > 0.6) {
		vec2 lip_uv = v_world_pos.xz * 0.8 + TIME * 0.05;  // 更高頻率
		float lip_noise = texture(foam_noise, lip_uv).r;
		float explosion_mask = smoothstep(0.6, 0.95, v_arc_position);
		lip_foam = pow(lip_noise, 0.5) * explosion_mask * 0.9;
	}
	
	// Layer 3: 邊緣霧化（基於 Fresnel）
	float mist_foam = fresnel * 0.2 * smoothstep(0.7, 1.0, v_arc_position);
	
	// 組合泡沫
	float foam_mask = clamp(bottom_foam + lip_foam + mist_foam, 0.0, 1.0) * foam_amount;
	
	// 混合泡沫顏色
	vec3 final_color = mix(sea_color, color_foam.rgb, foam_mask);
	
	// === Step 2: 增強SSS次表面散射 ===
	// 計算太陽方向（簡化版，假設從右上方照射）
	vec3 sun_dir = normalize(vec3(0.6, 0.8, 0.3));
	
	// 計算背光透射（太陽光從背後穿透水體）
	float sun_transmission = pow(max(dot(sun_dir, -final_normal), 0.0), 1.5);
	
	// 薄水層強散射（唇部區域）
	float thinness_factor = 1.0 / max(v_water_thickness, 0.1);  // 越薄越亮
	float sss_intensity = sss_strength * 3.0 * thinness_factor;
	
	// 顏色隨厚度變化（薄=青綠，厚=深藍）
	vec3 thin_color = vec3(0.2, 0.9, 0.8);   // 青綠色
	vec3 thick_color = vec3(0.0, 0.3, 0.6);  // 深藍色
	vec3 sss_final_color = mix(thick_color, thin_color, thinness_factor * 0.5);
	
	// SSS遮罩（唇部更強）
	float sss_mask = pow(max(v_arc_position - 0.3, 0.0), 2.0);
	float sss_view = pow(max(dot(view_dir, -final_normal), 0.0), 3.0);
	
	// 組合所有因素
	vec3 sss_contribution = sss_final_color * sss_intensity 
						* (0.3 + 0.7 * sun_transmission)  // 背光面更亮
						* sss_mask 
						* (0.5 + 0.5 * sss_view);
	
	// === Step 1: 修復透明度（增強厚度感）===
	// 🔥 厚水牆必須更不透明才能顯示出來
	
	// 基於實際水體厚度的不透明度（厚 = 幾乎不透明）
	float thickness_opacity = 0.5 + v_water_thickness * 0.25;  // 最厚可達 0.5 + 0.75 = 1.25 → clamp 到 1.0
	
	// 底部區域（arc < 0.4）大幅增加不透明度
	float depth_boost = smoothstep(0.4, 0.0, v_arc_position) * 0.35;  // 底部 +35% 不透明
	
	// 邊緣柔和漸變（避免硬邊）
	float edge_fade = smoothstep(0.0, 0.2, v_edge_blend);
	
	// 組合所有透明度因素
	float base_alpha = (thickness_opacity + depth_boost) * edge_fade;
	
	// === 最終輸出 ===
	ALBEDO = final_color;
	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;
	
	ALPHA = clamp(base_alpha + foam_mask * 0.15, 0.3, 0.98) * alpha_mult;
	METALLIC = metallic * (1.0 - foam_mask);
	ROUGHNESS = mix(roughness, 0.5, foam_mask);
	SPECULAR = 0.5;
	
	// === Step 4: 內部高光 + Fresnel發光 + SSS ===
	// 模擬光線在水體內部的反射（類似玉石效果）
	float view_tangent = abs(dot(view_dir, tangent_world));
	float internal_highlight = pow(view_tangent, 8.0)           // 窄高光
						  * smoothstep(0.4, 0.7, v_arc_position)  // 只在中段出現
						  * (v_water_thickness / 3.0);            // 厚度調制
	
	// Fresnel 發光
	EMISSION = mix(sea_color, vec3(0.3, 0.5, 0.7), 0.3) * fresnel_strength * pow(fresnel, 5.0) * (1.0 - foam_mask);
	
	// SSS
	EMISSION += sss_contribution * (1.0 - foam_mask);
	
	// 內部高光
	EMISSION += vec3(0.4, 0.7, 0.9) * internal_highlight * 0.5 * (1.0 - foam_mask);
	
	// 🔥 厚水牆邊緣光（讓厚度在視覺上更明顯）
	// 底部厚水區域的輪廓發光
	float thickness_rim = pow(fresnel, 3.0) * thickness_factor * (1.0 - v_arc_position);
	EMISSION += color_deep.rgb * 0.4 * thickness_rim * (1.0 - foam_mask);
}
