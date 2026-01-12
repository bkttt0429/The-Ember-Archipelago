shader_type spatial;

// --- Uniforms ---
// These are updated every frame by GpuCollisionSimulation.gd
uniform sampler2D sim_texture;  // R=Height, G=VelX, B=VelY
uniform sampler2D conc_texture; // R=ConcA, G=ConcB
uniform float grid_size = 40.0;
uniform vec2 uv_offset = vec2(0.0);
uniform float wave_height_scale = 10.0;

// --- Colors ---
uniform vec3 color_a = vec3(1.0, 0.2, 0.1);    // Red species
uniform vec3 color_b = vec3(0.1, 0.4, 1.0);    // Blue species
uniform vec3 color_mixed = vec3(0.8, 0.1, 1.0);// Reaction product (Purple)
uniform vec3 color_bg = vec3(0.05, 0.08, 0.1); // Deep water/Background

varying float v_conc_a;
varying float v_conc_b;
varying float v_height;

void vertex() {
	// 1. Calculate UV based on world position and simulation window
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 uv = (world_pos.xz - uv_offset) / grid_size + 0.5;
	
	// 2. Clamp UV to avoid edge artifacts
	uv = clamp(uv, 0.0, 1.0);
	
	vec4 sim_data = texture(sim_texture, uv);
	vec4 conc_data = texture(conc_texture, uv);
	
	// 3. Extract Values
	// Sim: R=Height
	// Conc: R=Species A, G=Species B
	float h = sim_data.r;
	v_conc_a = conc_data.r; 
	v_conc_b = conc_data.g;
	v_height = h;

	// 4. Displace
	VERTEX.y += h * wave_height_scale;
}

void fragment() {
	float total_conc = v_conc_a + v_conc_b;
	vec3 final_color = color_bg;

	if (total_conc > 0.001) {
		// Normalize weights
		float wa = v_conc_a / total_conc;
		float wb = v_conc_b / total_conc;
		
		// 1. Linear mix of base colors
		vec3 base_mix = mix(color_a, color_b, wb);
		
		// 2. Reaction / Overlap logic
		float overlap = min(v_conc_a, v_conc_b) * 2.0; 
		overlap = clamp(overlap, 0.0, 1.0);
		
		// Interpolate towards the reaction color based on overlap
		// Fix: Use base_mix as the starting point instead of uninitialized final_color
		final_color = mix(base_mix, color_mixed, overlap);
		
		// 3. Intensity falloff
		float intensity = smoothstep(0.0, 0.2, total_conc);
		final_color = mix(color_bg, final_color, intensity);
	}
	
	// --- DEBUG SAFETY CHECK ---
	// If the texture read gives garbage (infinity/NaN), show Checkers/Magenta
	if (total_conc > 1000.0 || isnan(total_conc)) {
		ALBEDO = vec3(1.0, 0.0, 1.0); // Magenta Error
	} else {
		ALBEDO = final_color;
		EMISSION = final_color * (total_conc * 0.8 + 0.1);
	}
	
	ROUGHNESS = 0.2;
	METALLIC = 0.1;
	SPECULAR = 0.5;
}
