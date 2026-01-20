shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 bg_color : source_color = vec3(0.15, 0.15, 0.18);
uniform vec3 grid_color : source_color = vec3(0.4, 0.4, 0.45);
uniform float grid_scale = 1.0;
uniform float line_width = 0.02;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 使用世界座標生成網格，這樣地板縮放也不會變形
	vec2 grid_uv = world_pos.xz / grid_scale;
	vec2 grid = abs(fract(grid_uv - 0.5) - 0.5) / fwidth(grid_uv);
	float line = min(grid.x, grid.y);
	float mask = 1.0 - smoothstep(0.0, line_width * 50.0, line);
	
	ALBEDO = mix(bg_color, grid_color, mask);
	ROUGHNESS = 0.8;
}
