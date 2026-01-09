shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// 🌊 Optimized Planar Low-Poly Water Shader
// Phase 1: Data-less Grid | Phase 2: Geomorphing | Phase 4: Beer's Law

uniform float grid_resolution = 64.0;
uniform vec3 player_pos = vec3(0.0);

// LOD & Snapping
instance uniform float level_coverage = 64.0;
instance uniform float level_index = 0.0;
uniform float radial_bias : hint_range(0.1, 5.0) = 2.0;
uniform float base_spacing = 1.0;

// Integration with GpuLocalOcean (SWE)
uniform sampler2D swe_simulation_map : filter_linear;
uniform vec4 swe_area; // xy: min, zw: size
uniform float swe_height_scale = 1.0;

// Integration with GpuOcean (FFT)
uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 128.0;
uniform float height_scale = 1.0;
uniform float wave_height_scale = 1.0;

// Visuals
uniform vec3 color_deep : source_color = vec3(0.0, 0.02, 0.08);
uniform vec3 color_shallow : source_color = vec3(0.02, 0.15, 0.25);
uniform vec3 color_ripple : source_color = vec3(0.1, 0.7, 0.5);
uniform float refraction_strength = 0.05;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

uniform bool debug_lod = false;
uniform bool debug_wireframe = false;
uniform bool debug_normals = false;
uniform bool test_wave = false;
uniform float test_wave_amplitude = 1.0;

varying float v_ripple_h;
varying float v_total_h;
varying vec3 v_view_pos;
varying float v_level;
varying vec2 v_grid_uv;
varying vec3 v_world_pos;
varying float v_time;

void vertex() {
	v_time = TIME;
	v_level = level_index;
	// 1. Generate Grid UV using VERTEX_ID (Phase 1)
	int res = int(grid_resolution);
	int x_id = VERTEX_ID % res;
	int z_id = VERTEX_ID / res;
	
	v_grid_uv = vec2(float(x_id), float(z_id)) / float(res - 1);
	vec2 center_uv = v_grid_uv * 2.0 - 1.0;
	
	// Apply Radial Bias
	vec2 biased_uv = vec2(
		sign(center_uv.x) * pow(abs(center_uv.x), radial_bias),
		sign(center_uv.y) * pow(abs(center_uv.y), radial_bias)
	);
	
	// 2. Vertex Snapping & Geomorphing (Phase 2)
	float level_scale = pow(2.0, level_index);
	float snap_size = base_spacing * level_scale;
	
	vec2 plane_pos_2d = biased_uv * level_coverage;
	
	// Snapping to prevent jitter
	vec2 snapped_player = floor(player_pos.xz / snap_size) * snap_size;
	
	// Morphing zone for smooth LOD transitions
	float morph = max(abs(biased_uv.x), abs(biased_uv.y));
	morph = smoothstep(0.85, 0.95, morph);
	
	vec2 p0 = floor(plane_pos_2d / snap_size + 0.5) * snap_size;
	vec2 p1 = floor(plane_pos_2d / (snap_size * 2.0) + 0.5) * (snap_size * 2.0);
	plane_pos_2d = mix(p0, p1, morph);
	
	v_world_pos = vec3(plane_pos_2d.x + snapped_player.x, 0.0, plane_pos_2d.y + snapped_player.y);
	
	// 3. Waves
	float h_swe = 0.0;
	float h_fft = 0.0;
	
	// Sample SWE (only for near levels)
	if (level_index < 2.5) {
		vec2 swe_uv = (v_world_pos.xz - swe_area.xy) / swe_area.zw;
		if (swe_uv.x >= 0.0 && swe_uv.x <= 1.0 && swe_uv.y >= 0.0 && swe_uv.y <= 1.0) {
			h_swe = textureLod(swe_simulation_map, swe_uv, 0.0).r * swe_height_scale;
		}
	}
	
	// Sample FFT
	vec2 fft_uv = v_world_pos.xz / texture_scale;
	h_fft = textureLod(displacement_map, fft_uv, 0.0).r * height_scale;
	
	// Test Wave Logic
	float h_test = 0.0;
	if (test_wave) {
		h_test = sin(v_world_pos.x * 0.5 + TIME * 2.0) * cos(v_world_pos.z * 0.5 + TIME * 1.5) * test_wave_amplitude;
	}
	
	v_ripple_h = h_swe;
	v_total_h = (h_swe + h_fft + h_test) * wave_height_scale;
	
	v_world_pos.y += v_total_h;

	VERTEX = (inverse(MODEL_MATRIX) * vec4(v_world_pos, 1.0)).xyz;
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. Dynamic Flat Shading
	vec3 face_normal = normalize(cross(dFdy(v_view_pos), dFdx(v_view_pos)));
	
	// 2. Beer's Law Depth
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_depth = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_depth.xyz /= view_pos_depth.w;
	
	float water_depth = length(view_pos_depth.xyz) - length(v_view_pos);
	water_depth = max(water_depth, 0.0);
	
	// Darken faster with depth
	float depth_fade = 1.0 - exp(-water_depth * 0.4);
	vec3 ocean_color = mix(color_shallow, color_deep, depth_fade);
	
	float ripple_intensity = clamp(abs(v_ripple_h) * 15.0, 0.0, 1.0);
	vec3 final_albedo = mix(ocean_color, color_ripple, ripple_intensity);
	
	// --- DEBUG MODES ---
	if (debug_normals) {
		ALBEDO = face_normal * 0.5 + 0.5;
	} else {
	
	if (debug_lod) {
		vec3 debug_colors[6] = {
			vec3(0.8, 0.1, 0.1), vec3(0.1, 0.8, 0.1), vec3(0.1, 0.1, 0.8),
			vec3(0.8, 0.8, 0.1), vec3(0.8, 0.1, 0.8), vec3(0.1, 0.8, 0.8)
		};
		final_albedo = mix(final_albedo, debug_colors[int(v_level)%6], 0.7);
	}
	
	// 3. Shading & Lighting (Crucial for Low-Poly visibility)
	NORMAL = face_normal;
	vec3 light_dir = normalize(vec3(0.5, 1.0, 0.2)); 
	float diff = max(dot(NORMAL, light_dir), 0.0);
	float shade = 0.25 + 0.75 * pow(diff, 2.0);
	final_albedo *= shade;
	
	if (debug_wireframe) {
		vec2 grid = fract(v_grid_uv * (grid_resolution - 1.0));
		float edge = 0.1 * (1.0 + v_level); 
		float wire = step(edge, grid.x) * step(edge, grid.y);
		final_albedo = mix(vec3(0.0, 1.0, 1.0), final_albedo, wire);
	}
	
	// 4. Final Color Output
	float alpha = clamp(0.95 + depth_fade * 0.05, 0.0, 1.0); 
	ALBEDO = final_albedo;
	ALPHA = alpha;
	
	ROUGHNESS = 0.1;
	SPECULAR = 0.8;
	
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), 4.0);
	EMISSION = color_ripple * ripple_intensity * 2.0 * fresnel;
	
	// Simple Specular Highlights
	vec3 half_v = normalize(VIEW + light_dir);
	float spec = pow(max(dot(NORMAL, half_v), 0.0), 32.0);
	EMISSION += vec3(0.8, 0.9, 1.0) * spec * shade;
	}
}
