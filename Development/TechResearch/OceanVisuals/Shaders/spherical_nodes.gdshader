shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// 🌊 Optimized Spherical Ocean Shader (Phase 3 & 4)
// Data-less Grid | Flat Shading | Vertex Snapping | Beer's Law | SSR

uniform float planet_radius = 500.0;
uniform vec3 player_pos = vec3(0.0, 500.0, 0.0);
uniform float grid_resolution = 127.0;

// LOD & Snapping
instance uniform float level_coverage = 64.0;
instance uniform float level_index = 0.0;
uniform float radial_bias : hint_range(0.1, 5.0) = 2.0;
uniform float skirt_depth = 5.0;
uniform float base_spacing = 1.0;

// Integration with GpuLocalOcean (SWE)
uniform sampler2D swe_simulation_map : filter_linear;
uniform vec4 swe_area; // xy: min_pos, zw: size

// Integration with GpuOcean (FFT)
uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 128.0;
uniform float wave_height_scale = 2.0;

// Visuals
uniform vec3 color_deep : source_color = vec3(0.01, 0.05, 0.15);
uniform vec3 color_shallow : source_color = vec3(0.05, 0.4, 0.6);
uniform vec3 color_ripple : source_color = vec3(0.1, 1.0, 0.8);
uniform float refraction_strength = 0.05;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

varying float v_ripple_h;
varying float v_total_h;
varying vec3 v_normal;
varying vec3 v_view_pos;
varying float v_depth_fade;

void vertex() {
	// 1. Generate Grid UV
	int res = int(grid_resolution);
	int x_id = VERTEX_ID % res;
	int z_id = VERTEX_ID / res;
	bool is_skirt = (x_id == 0 || x_id == res - 1 || z_id == 0 || z_id == res - 1);
	
	vec2 grid_uv = vec2(float(x_id), float(z_id)) / float(res - 1);
	vec2 center_uv = grid_uv * 2.0 - 1.0;
	
	// Apply Radial Bias
	vec2 biased_uv = vec2(
		sign(center_uv.x) * pow(abs(center_uv.x), radial_bias),
		sign(center_uv.y) * pow(abs(center_uv.y), radial_bias)
	);
	
	// 2. Vertex Snapping & Geomorphing
	// Calculate the world-space snap size for this level
	float level_scale = pow(2.0, level_index);
	float snap_size = base_spacing * level_scale;
	
	// Snap target position to the global spacing (simulated)
	// This helps vertices stay in place as camera moves
	vec3 P_up = normalize(player_pos);
	vec3 P_right = normalize(cross(vec3(0.0, 1.0, 0.0), P_up));
	if (length(P_right) < 0.01) P_right = normalize(cross(vec3(0.0, 0.0, 1.0), P_up));
	vec3 P_fwd = normalize(cross(P_up, P_right));
	
	vec2 plane_pos_2d = biased_uv * level_coverage;
	
	// Geomorphing: Smoothly transition to the next LOD level near the edges
	// Detect if we are in the "morph zone" (outer 10% of the coverage)
	float morph = max(abs(biased_uv.x), abs(biased_uv.y));
	morph = smoothstep(0.85, 0.95, morph);
	
	// In the morph zone, we snap to double the snap_size (simulating the next LOD level)
	vec2 snapped_pos = floor(plane_pos_2d / snap_size + 0.5) * snap_size;
	vec2 morphed_pos = floor(plane_pos_2d / (snap_size * 2.0) + 0.5) * (snap_size * 2.0);
	plane_pos_2d = mix(snapped_pos, morphed_pos, morph);
	
	vec3 plane_pos_3d = player_pos + (P_right * plane_pos_2d.x) + (P_fwd * plane_pos_2d.y);
	
	// 4. Project to Sphere Surface
	vec3 sphere_normal = normalize(plane_pos_3d);
	float actual_radius = planet_radius;
	if (is_skirt) actual_radius -= skirt_depth;
	
	vec3 surface_pos = sphere_normal * actual_radius;
	
	// 5. Waves
	float h_swe = 0.0;
	float h_fft = 0.0;
	
	if (level_index < 2.5) {
		if (abs(swe_area.z) > 0.001) {
			vec2 swe_uv = (surface_pos.xz - swe_area.xy) / swe_area.zw;
			if (swe_uv.x >= 0.0 && swe_uv.x <= 1.0 && swe_uv.y >= 0.0 && swe_uv.y <= 1.0) {
				h_swe = textureLod(swe_simulation_map, swe_uv, 0.0).r;
			}
		}
	}
	
	if (texture_scale > 0.1) {
		vec2 fft_uv = surface_pos.xz / texture_scale;
		h_fft = textureLod(displacement_map, fft_uv, 0.0).r;
	}
	
	v_ripple_h = h_swe;
	v_total_h = (h_swe + h_fft) * wave_height_scale;
	
	if (!is_skirt) {
		surface_pos += sphere_normal * v_total_h;
	}

	VERTEX = surface_pos;
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. Dynamic Flat Shading
	vec3 ddx = dFdx(VERTEX);
	vec3 ddy = dFdy(VERTEX);
	vec3 face_normal = normalize(cross(ddx, ddy));
	
	// 2. Beer's Law Implementation (Actual Depth)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_depth = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_depth.xyz /= view_pos_depth.w;
	
	float water_depth = length(view_pos_depth.xyz) - length(v_view_pos);
	water_depth = max(water_depth, 0.0);
	
	// Beer-Lambert Law: Intensity = I0 * exp(-absorption * depth)
	// Simplified as a transition
	float depth_fade = 1.0 - exp(-water_depth * 0.15);
	vec3 ocean_color = mix(color_shallow, color_deep, depth_fade);
	
	float ripple_intensity = clamp(abs(v_ripple_h) * 10.0, 0.0, 1.0);
	vec3 final_albedo = mix(ocean_color, color_ripple, ripple_intensity);
	
	// 3. Stylized Refraction (SSR lite)
	vec2 ref_offset = NORMAL.xy * refraction_strength;
	vec3 screen_ref = texture(screen_texture, SCREEN_UV + ref_offset).rgb;
	
	// Adjust transparency based on depth
	float alpha = clamp(0.5 + depth_fade * 0.5, 0.0, 1.0); 
	ALBEDO = mix(screen_ref, final_albedo, alpha);
	
	NORMAL = face_normal;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);
	EMISSION = color_ripple * ripple_intensity * 2.0 * (0.5 + 0.5 * fresnel);
	
	// Foam on Peaks
	float foam = smoothstep(0.4, 0.8, v_total_h / wave_height_scale);
	ALBEDO = mix(ALBEDO, vec3(0.9, 1.0, 1.0), foam * 0.5);
}
