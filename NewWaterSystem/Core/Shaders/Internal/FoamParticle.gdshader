shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform sampler2D noise_texture : hint_default_white;
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying float v_life;
varying float v_random;

void vertex() {
	// Billboarding
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]
	);
	
	// Billboard size adjustment (optional scale)
	// MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	
	v_life = INSTANCE_CUSTOM.x; // Age/Lifetime 0->1
	v_random = INSTANCE_CUSTOM.y;
}

void fragment() {
	// Circular mask
	vec2 uv_centered = UV - 0.5;
	float dist_sq = dot(uv_centered, uv_centered);
	if (dist_sq > 0.25) discard;
	
	float mask = 1.0 - smoothstep(0.1, 0.25, dist_sq);
	
	// Noise Texture
	float noise = texture(noise_texture, UV + vec2(TIME * 0.1, v_random)).r;
	
	// Fade edges and over life
	float alpha = mask * noise * (1.0 - v_life);
	alpha *= smoothstep(0.0, 0.2, v_life); // Fade in
	
	ALBEDO = foam_color.rgb;
	ALPHA = clamp(alpha * foam_color.a, 0.0, 1.0);
}
