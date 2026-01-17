shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, alpha_to_coverage, depth_draw_always;

// 🌊 Barrel Wave Specific Shader
// This is a simplified version of ocean_surface.gdshader without vertex displacement
// to avoid "double displacement" when applied to the procedural barrel mesh.

uniform vec4 water_color : source_color = vec4(0.01, 0.03, 0.05, 1.0);
uniform vec4 deep_water_color : source_color = vec4(0.0, 0.01, 0.02, 1.0);
uniform float beer_law_factor : hint_range(0.0, 2.0) = 0.5;
uniform float fresnel_power : hint_range(1.0, 10.0) = 5.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 v_world_pos;
varying vec3 v_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Simple Water Look (Compatible with main ocean)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_raw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_raw.xyz /= view_pos_raw.w;
	float geometry_z = -view_pos_raw.z;
	float surface_z = -VERTEX.z;
	float depth = max(geometry_z - surface_z, 0.0);

	// Beer's Law for color
	float beer = exp(-depth * beer_law_factor);
	vec3 final_color = mix(water_color.rgb, deep_water_color.rgb, 1.0 - beer);

	// Fresnel
	float fresnel = pow(1.0 - clamp(dot(normalize(v_normal), VIEW), 0.0, 1.0), fresnel_power);
	
	ALBEDO = final_color;
	ALPHA = 0.9;
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	SPECULAR = 0.5;
	EMISSION = water_color.rgb * fresnel * 0.2;
}
