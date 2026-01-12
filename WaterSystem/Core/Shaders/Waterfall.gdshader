shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_prepass_alpha;

uniform vec4 water_color : source_color = vec4(0.3, 0.7, 0.9, 0.8);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D noise_tex : repeat_enable;
uniform float flow_speed = 2.0;
uniform float foam_threshold = 0.5;
uniform float edge_softness = 0.2;
uniform float sea_level = 0.0;
uniform float splash_intensity = 1.0;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Scrolling noise for water flow
	vec2 scrolling_uv = vec2(UV.x, UV.y - TIME * flow_speed);
	float n = texture(noise_tex, scrolling_uv).r;
	float n2 = texture(noise_tex, scrolling_uv * 2.0 + TIME * 0.1).r;
	float combined_noise = (n + n2) * 0.5;
	
	// Splash effect near sea level
	float dist_to_sea = abs(v_world_y - sea_level);
	float splash_mask = smoothstep(1.5, 0.0, dist_to_sea) * splash_intensity;
	
	// Create turbulent foam look
	float foam_mask = smoothstep(foam_threshold - 0.2, foam_threshold + 0.2, combined_noise + splash_mask * 0.5);
	vec3 final_color = mix(water_color.rgb, foam_color.rgb, foam_mask);
	
	// Edge softness (Vignette-like alpha at top)
	// We remove softness at bottom to meet the sea
	float alpha_mask = smoothstep(0.0, edge_softness, UV.y);
	
	ALBEDO = final_color;
	ALPHA = water_color.a * alpha_mask;
	
	// Impact highlight
	EMISSION = foam_color.rgb * splash_mask * 0.8 + foam_color.rgb * foam_mask * 0.3;
	
	ROUGHNESS = 0.1;
	SPECULAR = 0.5;
}
