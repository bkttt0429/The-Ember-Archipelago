shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D particle_texture : hint_default_white;
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);

// INSTANCE_CUSTOM 只能在 vertex() 存取，需用 varying 傳到 fragment()
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	float life_factor = v_custom.r;
	float velocity = v_custom.g;

	// 圓形遮罩
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv);
	float circle_mask = smoothstep(0.5, 0.3, dist);

	// 噪聲變化
	float noise = texture(particle_texture, UV * 2.0).r;
	circle_mask *= mix(0.7, 1.0, noise);

	// 速度拉伸
	float stretch = mix(1.0, 0.5, velocity);
	circle_mask *= mix(1.0, stretch, step(0.5, UV.y));

	ALBEDO = foam_color;
	ALPHA = circle_mask * life_factor * 0.8;
	EMISSION = foam_color * 0.2 * life_factor;
}
