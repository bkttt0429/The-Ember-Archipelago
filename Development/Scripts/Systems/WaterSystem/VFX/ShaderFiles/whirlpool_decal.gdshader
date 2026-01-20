shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 center_world = vec3(0.0, 0.0, 0.0);
uniform float radius = 15.0;
uniform float depth = 1.5;
uniform float swirl_speed = 1.5;
uniform float ring_freq = 8.0;
uniform float ring_strength = 0.2;
uniform vec4 color_deep : source_color = vec4(0.05, 0.15, 0.25, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.1, 0.35, 0.45, 1.0);

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world_pos.xz - center_world.xz;
	float r = length(p);
	float sigma = radius * 0.4;
	float falloff = exp(- (r * r) / (2.0 * sigma * sigma));

	float angle = atan(p.y, p.x);
	float swirl = sin(angle * ring_freq + TIME * swirl_speed);

	float height_offset = -depth * falloff;
	height_offset += swirl * ring_strength * falloff;

	VERTEX.y += height_offset;
}

void fragment() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world_pos.xz - center_world.xz;
	float r = length(p);
	float t = clamp(r / radius, 0.0, 1.0);

	vec4 base = mix(color_deep, color_shallow, t);
	ALBEDO = base.rgb;
	ALPHA = base.a;
}
