shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_linear_mipmap;

// 色階數量 (越少越卡通)
uniform int color_levels : hint_range(2, 8) = 4;
// 邊緣線粗細
uniform float outline_thickness : hint_range(0.0, 3.0) = 1.0;
// 邊緣線顏色
uniform vec4 outline_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
// 深度邊緣靈敏度
uniform float depth_threshold : hint_range(0.0, 0.1) = 0.01;
// 法線邊緣靈敏度
uniform float normal_threshold : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 original = texture(screen_texture, uv);
	
	// === 色階量化 (Cel Shading) ===
	vec3 quantized = floor(original.rgb * float(color_levels)) / float(color_levels - 1);
	
	// === 邊緣檢測 (Sobel) ===
	vec2 pixel = vec2(1.0) / vec2(textureSize(screen_texture, 0));
	float edge = 0.0;
	
	// 深度邊緣
	float d = texture(depth_texture, uv).r;
	float d_l = texture(depth_texture, uv + vec2(-pixel.x, 0.0) * outline_thickness).r;
	float d_r = texture(depth_texture, uv + vec2(pixel.x, 0.0) * outline_thickness).r;
	float d_u = texture(depth_texture, uv + vec2(0.0, -pixel.y) * outline_thickness).r;
	float d_d = texture(depth_texture, uv + vec2(0.0, pixel.y) * outline_thickness).r;
	
	float depth_diff = abs(d_l - d_r) + abs(d_u - d_d);
	edge = max(edge, step(depth_threshold, depth_diff));
	
	// 法線邊緣
	vec3 n = texture(normal_texture, uv).rgb;
	vec3 n_l = texture(normal_texture, uv + vec2(-pixel.x, 0.0) * outline_thickness).rgb;
	vec3 n_r = texture(normal_texture, uv + vec2(pixel.x, 0.0) * outline_thickness).rgb;
	vec3 n_u = texture(normal_texture, uv + vec2(0.0, -pixel.y) * outline_thickness).rgb;
	vec3 n_d = texture(normal_texture, uv + vec2(0.0, pixel.y) * outline_thickness).rgb;
	
	float normal_diff = length(n_l - n_r) + length(n_u - n_d);
	edge = max(edge, step(normal_threshold, normal_diff));
	
	// === 合成 ===
	vec3 final_color = mix(quantized, outline_color.rgb, edge * outline_color.a);
	COLOR = vec4(final_color, 1.0);
}
