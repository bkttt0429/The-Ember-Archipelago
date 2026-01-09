shader_type spatial;

uniform float coverage_radius = 50.0;
uniform float grid_resolution = 32.0;
uniform float sphere_radius = 0.5;
uniform float radial_bias = 2.0;
uniform vec3 player_pos = vec3(0.0);

// Global FFT
uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 64.0;
uniform float height_scale = 1.0;
uniform float choppiness = 1.0;

// Local SWE
uniform sampler2D swe_simulation_map : filter_linear;
uniform vec4 swe_area; // xy: min, zw: size
uniform float swe_height_scale = 1.0;
uniform bool ripple_debug_mode = false;

varying vec3 v_world_pos;
varying float v_height;
varying float v_biased_dist;
varying float v_swe_h;
varying float v_swe_foam;

void vertex() {
	// Instance position stores (u, 0, v) grid coords in 0..1
	vec2 grid_uv = MODEL_MATRIX[3].xz;
	
	// World position before displacement (Y=0)
	vec2 mesh_center_uv = vec2(0.5, 0.5);
	vec2 dir = grid_uv - mesh_center_uv;
	float dist_uv = length(dir) * 2.0; // 0..1 from center to edge
	
	// Apply radial bias to UVs to concentrate points at center
	float biased_dist = pow(dist_uv, radial_bias);
	v_biased_dist = biased_dist;
	
	vec2 biased_grid_uv = mesh_center_uv + (dist_uv > 0.0 ? (dir / length(dir)) * (biased_dist * 0.5) : vec2(0.0));
	
	vec2 plane_pos = (biased_grid_uv * 2.0 - 1.0) * coverage_radius;
	vec3 world_pos_flat = vec4(MODEL_MATRIX * vec4(vec3(plane_pos.x, 0.0, plane_pos.y), 1.0)).xyz;
	
	world_pos_flat.xz += player_pos.xz;

	// 1. FFT Sampling
	vec2 fft_uv = world_pos_flat.xz / texture_scale;
	vec4 fft_data = texture(displacement_map, fft_uv);
	// Current FFT only stores height in the R (x) channel
	vec3 fft_disp = vec3(0.0, fft_data.x * height_scale, 0.0);
	
	// 2. SWE Sampling
	vec2 swe_local = (world_pos_flat.xz - swe_area.xy) / swe_area.zw;
	float swe_h = 0.0;
	float swe_f = 0.0;
	if (swe_local.x >= 0.0 && swe_local.x <= 1.0 && swe_local.y >= 0.0 && swe_local.y <= 1.0) {
		vec4 swe_samp = texture(swe_simulation_map, swe_local);
		swe_h = swe_samp.r * swe_height_scale;
		swe_f = swe_samp.a;
	}
	v_swe_h = swe_h;
	v_swe_foam = swe_f;
	
	// Final Position
	vec3 final_pos = world_pos_flat + vec3(fft_disp.x, fft_disp.y + swe_h, fft_disp.z);
	v_height = fft_disp.y + swe_h;
	
	// Vertex position relative to instance origin
	// We want to move the sphere mesh to the perturbed position
	// MODEL_MATRIX[3] contains our grid_uv. We need the local mesh vertex position.
	// But in spatial shaders, VERTEX is already in local space.
	// We want to transform it to the world_pos_flat + displacement.
	
	// Instance storage position (the u,0,v helper)
	vec3 storage_pos = MODEL_MATRIX[3].xyz;
	
	// In MultiMesh, the model matrix is usually identity + instance transform.
	// Here we just want to replace the vertex with its displaced world position
	// relative to where Godot *thinks* the instance is.
	
	VERTEX = (final_pos - storage_pos) + (VERTEX * sphere_radius);
	v_world_pos = final_pos; // Simplification
}

void fragment() {
	// 1. LOD Based Coloring
	// High density (center) = Bright Blue, Low density (edge) = Deep Navy
	vec3 high_det_color = vec3(0.1, 0.5, 0.9);
	vec3 low_det_color = vec3(0.02, 0.05, 0.15);
	vec3 base_color = mix(high_det_color, low_det_color, smoothstep(0.0, 1.0, v_biased_dist));
	
	// 2. FFT Height Foam
	vec3 foam_color = vec3(0.8, 0.9, 1.0);
	float fft_foam = clamp(v_height * 0.4 - 0.2, 0.0, 1.0);
	
	// 3. SWE Ripple Visualization (Emissive & Glow)
	// Make ripples glow bright cyan/white
	float swe_abs = abs(v_swe_h);
	float swe_glow_mask = smoothstep(0.05, 0.5, swe_abs * 5.0 + v_swe_foam);
	vec3 swe_color = mix(vec3(0.0, 0.8, 1.0), vec3(1.0, 1.0, 1.0), v_swe_foam);
	vec3 swe_glow = swe_color * swe_glow_mask * 5.0; // High multiplier for "WOW" effect
	
	// 4. Fake SSS (Fresnel)
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);
	vec3 sss_color = vec3(0.0, 0.6, 0.7) * fresnel * 0.5;
	
	// Mix final color
	// Mix final color
	vec3 final_color = base_color;
	final_color = mix(final_color, foam_color, fft_foam);
	
	if (ripple_debug_mode && swe_abs > 0.01) {
		// Highlight ripples in bright Magenta for debugging
		final_color = vec3(1.0, 0.0, 1.0);
	} else {
		final_color = mix(final_color, swe_color, swe_glow_mask * 0.5);
		final_color += swe_glow; 
	}
	
	final_color += sss_color;
	
	ALBEDO = final_color;
	EMISSION = swe_glow * 1.5; 
	METALLIC = 0.2;
	ROUGHNESS = 0.1;
}
