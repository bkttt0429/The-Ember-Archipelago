shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, unshaded;

// SWE 測試專用 shader — 簡潔、清楚地展示 SWE 水位
uniform sampler2D swe_texture : filter_linear, repeat_disable;
uniform vec2 sea_size;
uniform vec3 manager_world_pos;
uniform vec3 swe_world_origin;
uniform float swe_strength : hint_range(0.0, 50.0) = 5.0;
uniform float swe_fill_threshold : hint_range(0.001, 0.5) = 0.02;

// 顏色
uniform vec4 shallow_color : source_color = vec4(0.2, 0.6, 0.9, 0.8);
uniform vec4 deep_color : source_color = vec4(0.05, 0.15, 0.4, 0.95);
uniform float deep_threshold : hint_range(0.1, 5.0) = 1.5;

varying float v_swe_h;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// SWE UV
	vec2 swe_uv = (world_pos.xz - swe_world_origin.xz) / sea_size + 0.5;
	swe_uv = clamp(swe_uv, vec2(0.001), vec2(0.999));
	
	vec4 swe_data = texture(swe_texture, swe_uv);
	float h = swe_data.r;
	v_swe_h = h;
	
	// 用 SWE 高度位移頂點
	VERTEX.y += h * swe_strength;
	
	// 簡單法線（從鄰居差分）
	float texel = 1.0 / float(textureSize(swe_texture, 0).x);
	float h_l = texture(swe_texture, swe_uv + vec2(-texel, 0.0)).r;
	float h_r = texture(swe_texture, swe_uv + vec2(texel, 0.0)).r;
	float h_d = texture(swe_texture, swe_uv + vec2(0.0, -texel)).r;
	float h_u = texture(swe_texture, swe_uv + vec2(0.0, texel)).r;
	
	float dx = (h_r - h_l) * swe_strength;
	float dz = (h_u - h_d) * swe_strength;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	// 基於水位混合淺/深色
	float depth_factor = smoothstep(0.0, deep_threshold, v_swe_h);
	vec4 water_col = mix(shallow_color, deep_color, depth_factor);
	
	// 簡單的光照高光
	float ndotl = max(dot(NORMAL, normalize(vec3(0.3, 1.0, 0.2))), 0.0);
	float spec = pow(max(dot(reflect(-normalize(vec3(0.3, 1.0, 0.2)), NORMAL), VIEW), 0.0), 32.0);
	
	ALBEDO = water_col.rgb * (0.6 + 0.4 * ndotl) + vec3(spec * 0.3);
	
	// Alpha：SWE 高度越高越不透明，低於閾值完全透明
	float fill_alpha = smoothstep(0.0, swe_fill_threshold * 5.0, v_swe_h);
	ALPHA = fill_alpha * water_col.a;
}
