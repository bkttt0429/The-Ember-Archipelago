shader_type spatial;
render_mode depth_draw_always, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.05, 0.35, 0.7, 0.7);
uniform vec4 foam_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float refraction_strength : hint_range(0.0, 0.5) = 0.05;
uniform float surface_smoothness : hint_range(0.0, 1.0) = 0.9;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

varying float v_speed;
varying float v_pressure;

void vertex() {
	// Extract speed and pressure from instance color (sent by controller)
	// Color channel: R=Pressure, G=Speed
	v_pressure = COLOR.r;
	v_speed = COLOR.g;
}

void fragment() {
	// 1. RECONSTRUCT NORMAL FOR BLOBBY LOOK
	// We assume UV is standard 0..1 for a quad or sphere.
	// Since we are using a SphereMesh, we can use UV to find the normal.
	vec2 center_uv = UV * 2.0 - 1.0;
	float dist_sq = dot(center_uv, center_uv);
	
	// Discard outside circle to keep it blobby even on quads 
	// (though we use SphereMesh, this helps with silhouette)
	if (dist_sq > 1.0) discard;
	
	float z = sqrt(1.0 - dist_sq);
	vec3 normal = normalize(vec3(center_uv, z));
	
	// 2. ADAPTIVE OPACITY (Metaball blending)
	// Soften the edges to merge with neighbors
	float edge_mask = smoothstep(1.0, 0.0, dist_sq);
	float alpha = water_color.a * pow(edge_mask, 0.5);
	
	// 3. COLOR & LIGHTING
	vec3 base_color = water_color.rgb;
	
	// Fresnel effect (reflective at grazing angles)
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	
	// Add speed-based highlights or foam
	float speed_factor = clamp(v_speed * 1.5, 0.0, 1.0);
	base_color = mix(base_color, foam_color.rgb, speed_factor * 0.4);
	
	// Pressure-based depth darken (absorption)
	base_color *= mix(1.0, 0.3, clamp(v_pressure * 3.0, 0.0, 1.0));
	
	// 4. SCREEN-SPACE REFRACTION
	// Use the normals to distort the background
	vec2 screen_uv_offset = normal.xy * refraction_strength;
	vec3 ref_color = texture(screen_texture, SCREEN_UV + screen_uv_offset).rgb;
	
	// 5. FINAL COMPOSITION
	// Mix base and refraction, boosted by fresnel reflectivity
	vec3 final_rgb = mix(base_color, ref_color, 0.3);
	final_rgb = mix(final_rgb, foam_color.rgb, fresnel * 0.5);
	
	ALBEDO = final_rgb;
	ALPHA = clamp(alpha * 1.5 + fresnel * 0.5, 0.0, 1.0); // Boosted alpha for cohesion
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	
	METALLIC = 0.2;
	ROUGHNESS = 0.05 + (1.0 - edge_mask) * 0.2;
	SPECULAR = 0.9;
}
