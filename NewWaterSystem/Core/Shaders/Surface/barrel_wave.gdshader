shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// 🌊 桶浪專用 Shader
// 複製 ocean_surface.gdshader 的 Fragment 邏輯，但不做頂點位移
// 這樣可以讓桶浪與海面視覺上一致

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
uniform float sss_strength : hint_range(0.0, 2.0) = 0.5;
uniform vec4 sss_color : source_color = vec4(0.0, 0.6, 0.5, 1.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_arc_position;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_arc_position = UV.x;  // 0 = 後方, 1 = 唇部
}

void fragment() {
	// 觀察方向
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	
	// === 法線貼圖（雙層動態混合）===
	vec2 uv1 = v_world_pos.xz * normal_tile + TIME * normal_speed;
	vec2 uv2 = v_world_pos.zx * normal_tile * 1.2 - TIME * normal_speed * 0.7;
	
	vec3 n1 = texture(normal_map1, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map2, uv2).rgb * 2.0 - 1.0;
	vec3 detail_normal = normalize(vec3((n1.xy + n2.xy) * normal_scale, 1.0));
	
	// 混合幾何法線和細節法線
	vec3 final_normal = normalize(v_world_normal + detail_normal * 0.3);
	
	// === Fresnel ===
	float fresnel = pow(1.0 - max(dot(final_normal, view_dir), 0.0), 4.0);
	
	// === 深度顏色混合（基於弧形位置）===
	float depth_factor = v_arc_position;  // 唇部更淺
	vec3 sea_color = mix(color_deep.rgb, color_shallow.rgb, depth_factor);
	
	// === 泡沫（唇部和邊緣更多）===
	vec2 foam_uv = v_world_pos.xz * 0.3 + TIME * 0.02;
	float foam_noise_val = texture(foam_noise, foam_uv).r;
	
	// 唇部多泡沫，頂部少
	float foam_mask = smoothstep(0.5, 1.0, v_arc_position) * foam_amount;
	foam_mask += fresnel * 0.2;  // 邊緣也有泡沫
	foam_mask = clamp(foam_mask * foam_noise_val * 2.0, 0.0, 1.0);
	
	// 混合泡沫顏色
	vec3 final_color = mix(sea_color, color_foam.rgb, foam_mask);
	
	// === SSS 次表面散射 ===
	float sss_mask = pow(max(v_arc_position - 0.3, 0.0), 2.0);
	float sss_view = pow(max(dot(view_dir, -final_normal), 0.0), 3.0);
	vec3 sss_contribution = sss_color.rgb * sss_strength * sss_mask * (0.2 + 0.8 * sss_view);
	
	// === 最終輸出 ===
	ALBEDO = final_color;
	NORMAL = (VIEW_MATRIX * vec4(final_normal, 0.0)).xyz;
	
	ALPHA = (0.85 + foam_mask * 0.15) * alpha_mult;
	METALLIC = metallic * (1.0 - foam_mask);
	ROUGHNESS = mix(roughness, 0.5, foam_mask);
	SPECULAR = 0.5;
	
	// Fresnel 發光 + SSS
	EMISSION = mix(sea_color, vec3(0.3, 0.5, 0.7), 0.3) * fresnel_strength * pow(fresnel, 5.0) * (1.0 - foam_mask);
	EMISSION += sss_contribution * (1.0 - foam_mask);
}
