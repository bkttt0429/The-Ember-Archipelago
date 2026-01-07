shader_type spatial;
render_mode cull_disabled, blend_mix;

uniform vec3 albedo : source_color = vec3(0.5, 0.7, 1.0);
uniform sampler2D noise_tex : repeat_enable;
uniform float speed = 2.0;
uniform float swirl_strength = 2.0;
uniform float taper = 0.5;
uniform float wobble = 0.3;
uniform float sync_time;

uniform float proximity_fade_distance = 2.0;
uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D depth_texture : hint_depth_texture;

varying float v_y_norm;

void vertex() {
	// Normalized Y (assuming height is 25.0 and mesh is centered)
	v_y_norm = (VERTEX.y + 12.5) / 25.0;
	
	// Taper: Narrow at bottom (y_norm=0), wider at top
	float radius_mult = 1.0 + v_y_norm * 4.0; 
	VERTEX.xz *= radius_mult;
	
	// Wobble (stronger at the top)
	float w = sync_time * speed;
	VERTEX.x += sin(w + v_y_norm * 3.0) * wobble * v_y_norm * 5.0;
	VERTEX.z += cos(w + v_y_norm * 3.0) * wobble * v_y_norm * 5.0;
}

void fragment() {
	// Spiral UV
	vec2 uv = UV;
	uv.x += UV.y * swirl_strength; // Swirl
	uv.y -= sync_time * speed * 0.5; // Upward panning
	
	float noise = texture(noise_tex, uv).r;
	
	// Fresnel
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	
	// Fade at top/bottom
	float edge_fade = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.8, 1.0, UV.y));
	
	// Proximity Fade
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	float proximity_fade = clamp((linear_depth - VERTEX.z) / proximity_fade_distance, 0.0, 1.0);

	ALBEDO = albedo;
	ALPHA = noise * (fresnel + 0.2) * edge_fade * proximity_fade * 0.8;
	EMISSION = albedo * 0.5;
}
