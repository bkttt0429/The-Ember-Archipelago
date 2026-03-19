shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 spray_color : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform float edge_softness : hint_range(0.5, 6.0) = 2.2;
uniform float brightness : hint_range(0.0, 4.0) = 1.35;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float gaussian = exp(-r2 * edge_softness);
	float alpha = gaussian * COLOR.a;
	ALBEDO = spray_color.rgb * COLOR.rgb * brightness;
	ALPHA = alpha;
	EMISSION = ALBEDO * alpha;
}
