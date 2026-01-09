shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// FFT Global Waves
uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 64.0;
uniform float height_scale = 1.0;
uniform float choppiness = 1.0;

// SWE Local Ripples
uniform sampler2D swe_simulation_map : filter_linear;
uniform vec4 swe_area; // xy: min_pos.xz, zw: grid_size.xz
uniform float swe_height_scale = 1.0;
uniform float swe_color_strength = 1.0;

varying vec3 v_world_pos;
varying vec2 v_fft_uv;
varying vec2 v_swe_uv;
varying float v_in_swe;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// Vertex Snapping: Align vertex with simulation grid to prevent blocky artifacts
	// base_grid_size / subdivisions usually matches the texel size in world units
	// Here we assume a generic snapping if grid info is missing, or we can just sample smoothly.
	// However, if the user sees "stairs", it's likely the sampling is not interpolated.
	
	v_world_pos = world_pos;
	
	// 1. FFT Sampling (Global World Space)
	v_fft_uv = world_pos.xz / texture_scale;
	vec4 fft_data = texture(displacement_map, v_fft_uv);
	
	// 2. SWE Sampling (Local Area)
	vec2 swe_local = (v_world_pos.xz - swe_area.xy) / swe_area.zw;
	v_swe_uv = swe_local;
	
	v_in_swe = 0.0;
	vec4 swe_data = vec4(0.0);
	if (swe_local.x >= 0.0 && swe_local.x <= 1.0 && swe_local.y >= 0.0 && swe_local.y <= 1.0) {
		swe_data = texture(swe_simulation_map, swe_local);
		v_in_swe = 1.0;
	}
	
	// Combine Displacements
	// FFT: .y is height, .xz is choppiness/horizontal displacement
	vec3 fft_disp = vec3(fft_data.x * choppiness, fft_data.y * height_scale, fft_data.z * choppiness);
	
	// SWE: .r is height
	float swe_h = swe_data.r * swe_height_scale;
	
	// Apply displacement to local vertex (relative to node origin)
	// Note: Clipmap uses vertex snapping in its own logic usually, 
	// but here we apply world-space displacement.
	VERTEX.y += fft_disp.y + swe_h;
	VERTEX.xz += fft_disp.xz;
}

void fragment() {
	// Simple Water Visuals
	vec3 base_color = vec3(0.05, 0.2, 0.4);
	vec3 deep_color = vec3(0.01, 0.05, 0.1);
	
	// Use SWE height for ripple coloring
	vec4 swe_data = texture(swe_simulation_map, v_swe_uv) * v_in_swe;
	float ripple = abs(swe_data.r);
	
	ALBEDO = mix(base_color, vec3(0.8, 0.9, 1.0), ripple * swe_color_strength);
	// ALBEDO = mix(ALBEDO, deep_color, 0.5);
	
	// Metallic / Roughness
	METALLIC = 0.1;
	ROUGHNESS = 0.05;
	SPECULAR = 0.5;
	
	// Normal generation (Procedural or from maps - keeping it simple for now)
	NORMAL = normalize(vec3(0.0, 1.0, 0.0));
	
	// Debug SWE Area
	if (v_in_swe > 0.5) {
		// ALBEDO = mix(ALBEDO, vec3(0.0, 1.0, 0.0), 0.1);
	}
}
