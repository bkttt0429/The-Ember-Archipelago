shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_toon, specular_toon;

// 🎨 STYLIZED LOW-POLY OCEAN SHADER
// Based on PlanarOceanTest_Hybrid structure
// Optimized for cartoon/stylized visuals with hard edges and vibrant colors

// ====== GRID & LOD ======
uniform float grid_resolution = 64.0;
uniform vec3 player_pos = vec3(0.0);

instance uniform float level_coverage = 64.0;
instance uniform float level_index = 0.0;
uniform float radial_bias : hint_range(0.1, 5.0) = 2.0;
uniform float base_spacing = 1.0;

// ====== WAVE SYSTEMS ======
// SWE (Local Ripples)
uniform sampler2D swe_simulation_map : filter_linear;
uniform vec4 swe_area;
uniform float swe_height_scale = 1.0;

// FFT (Global Waves)
uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 128.0;
uniform float height_scale = 1.0;
uniform float wave_height_scale = 2.0;

// ====== STYLIZED COLORS ======
uniform vec3 color_deep : source_color = vec3(0.02, 0.15, 0.35);
uniform vec3 color_mid : source_color = vec3(0.1, 0.45, 0.65);
uniform vec3 color_shallow : source_color = vec3(0.3, 0.7, 0.85);
uniform vec3 color_foam : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3 color_ripple_glow : source_color = vec3(0.2, 0.9, 0.95);

// ====== SHADING PARAMS ======
uniform int shade_bands : hint_range(2, 5) = 3;
uniform float foam_threshold = 0.3;
uniform float crest_sharpness = 0.8;
uniform float edge_foam_width = 0.5;
uniform float ripple_glow_intensity = 3.0;

// ====== TEXTURE INPUTS ======
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

// ====== DEBUG ======
uniform bool debug_lod = false;
uniform bool debug_wireframe = false;

// ====== VARYINGS ======
varying vec3 v_world_pos;
varying vec3 v_view_pos;
varying float v_total_h;
varying float v_ripple_h;
varying float v_wave_h;
varying float v_level;
varying vec2 v_grid_uv;

void vertex() {
	v_level = level_index;
	
	// 1. DATA-LESS GRID GENERATION
	int res = int(grid_resolution);
	int x_id = VERTEX_ID % res;
	int z_id = VERTEX_ID / res;
	
	v_grid_uv = vec2(float(x_id), float(z_id)) / float(res - 1);
	vec2 center_uv = v_grid_uv * 2.0 - 1.0;
	
	// Radial bias for better density distribution
	vec2 biased_uv = vec2(
		sign(center_uv.x) * pow(abs(center_uv.x), radial_bias),
		sign(center_uv.y) * pow(abs(center_uv.y), radial_bias)
	);
	
	// 2. VERTEX SNAPPING (Critical for stylized look!)
	float level_scale = pow(2.0, level_index);
	float snap_size = base_spacing * level_scale;
	
	vec2 plane_pos_2d = biased_uv * level_coverage;
	
	// Snap player position to prevent swimming geometry
	vec2 snapped_player = floor(player_pos.xz / snap_size) * snap_size;
	
	// Geomorphing for smooth LOD transitions
	float morph = max(abs(biased_uv.x), abs(biased_uv.y));
	morph = smoothstep(0.85, 0.95, morph);
	
	vec2 p0 = floor(plane_pos_2d / snap_size + 0.5) * snap_size;
	vec2 p1 = floor(plane_pos_2d / (snap_size * 2.0) + 0.5) * (snap_size * 2.0);
	plane_pos_2d = mix(p0, p1, morph);
	
	v_world_pos = vec3(plane_pos_2d.x + snapped_player.x, 0.0, plane_pos_2d.y + snapped_player.y);
	
	// 3. WAVE DISPLACEMENT
	float h_swe = 0.0;
	float h_fft = 0.0;
	
	// SWE (only for near levels to save performance)
	if (level_index < 2.5) {
		vec2 swe_uv = (v_world_pos.xz - swe_area.xy) / swe_area.zw;
		if (swe_uv.x >= 0.0 && swe_uv.x <= 1.0 && swe_uv.y >= 0.0 && swe_uv.y <= 1.0) {
			h_swe = textureLod(swe_simulation_map, swe_uv, 0.0).r * swe_height_scale;
		}
	}
	
	// FFT - IMPORTANT: Snap UV coordinates to match vertex grid!
	vec2 fft_uv = v_world_pos.xz / texture_scale;
	h_fft = textureLod(displacement_map, fft_uv, 0.0).r * height_scale;
	
	v_ripple_h = h_swe;
	v_wave_h = h_fft;
	
	// Sharp crest formula (no softening - we want angular peaks!)
	float combined_h = h_swe + h_fft;
	v_total_h = combined_h * wave_height_scale;
	
	// Apply crest sharpness (makes peaks pointier)
	if (v_total_h > 0.0) {
		v_total_h = pow(v_total_h, crest_sharpness);
	}
	
	v_world_pos.y += v_total_h;
	
	VERTEX = (inverse(MODEL_MATRIX) * vec4(v_world_pos, 1.0)).xyz;
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. FLAT SHADING (Essential for low-poly look!)
	vec3 face_normal = normalize(cross(dFdy(v_view_pos), dFdx(v_view_pos)));
	
	// 2. POSTERIZED LIGHTING (Toon shading with hard bands)
	vec3 light_dir = normalize(vec3(0.5, 0.8, 0.3));
	float ndotl = dot(face_normal, light_dir) * 0.5 + 0.5;
	
	// Create discrete lighting bands
	float shade = floor(ndotl * float(shade_bands)) / float(shade_bands);
	shade = clamp(shade, 0.3, 1.0); // Prevent pure black
	
	// 3. DEPTH-BASED COLOR BANDING
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_depth = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_depth.xyz /= view_pos_depth.w;
	
	float water_depth = max(length(view_pos_depth.xyz) - length(v_view_pos), 0.0);
	
	// Posterize depth into distinct color bands
	float depth_band = floor(water_depth * 2.0) / 2.0;
	float depth_factor = clamp(depth_band / 3.0, 0.0, 1.0);
	
	// 3-tier color system
	vec3 base_color;
	if (depth_factor < 0.33) {
		base_color = color_shallow;
	} else if (depth_factor < 0.66) {
		base_color = color_mid;
	} else {
		base_color = color_deep;
	}
	
	// 4. FOAM ON WAVE CRESTS
	float foam_mask = step(foam_threshold, v_total_h / wave_height_scale);
	base_color = mix(base_color, color_foam, foam_mask);
	
	// 5. EDGE FOAM (Shore interaction)
	float edge_foam = smoothstep(edge_foam_width, 0.0, water_depth);
	edge_foam = step(0.3, edge_foam); // Hard edge
	base_color = mix(base_color, color_foam, edge_foam);
	
	// 6. RIPPLE GLOW (SWE visualization)
	float ripple_intensity = abs(v_ripple_h) * 10.0;
	ripple_intensity = step(0.1, ripple_intensity); // Binary on/off
	
	vec3 ripple_emission = color_ripple_glow * ripple_intensity * ripple_glow_intensity;
	
	// 7. DEBUG MODES
	if (debug_lod) {
		vec3 lod_colors[6] = {
			vec3(1.0, 0.2, 0.2), vec3(0.2, 1.0, 0.2), vec3(0.2, 0.2, 1.0),
			vec3(1.0, 1.0, 0.2), vec3(1.0, 0.2, 1.0), vec3(0.2, 1.0, 1.0)
		};
		base_color = mix(base_color, lod_colors[int(v_level) % 6], 0.5);
	}
	
	if (debug_wireframe) {
		vec2 grid = fract(v_grid_uv * (grid_resolution - 1.0));
		float edge = 0.05;
		float wire = step(edge, grid.x) * step(edge, grid.y);
		base_color = mix(vec3(0.0, 1.0, 1.0), base_color, wire);
	}
	
	// 8. FINAL OUTPUT
	vec3 final_color = base_color * shade;
	
	ALBEDO = final_color;
	EMISSION = ripple_emission;
	NORMAL = face_normal;
	
	ROUGHNESS = 0.3;
	SPECULAR = 0.7;
	METALLIC = 0.1;
	
	// Hard-edge specular highlight
	vec3 half_vec = normalize(VIEW + light_dir);
	float spec = pow(max(dot(face_normal, half_vec), 0.0), 64.0);
	spec = step(0.5, spec); // Binary specular
	EMISSION += vec3(1.0, 1.0, 0.9) * spec * 2.0;
}
