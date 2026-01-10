shader_type spatial;
render_mode cull_back, depth_draw_opaque;

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
uniform vec3 color_deep : source_color = vec3(0.047, 0.114, 0.231);
uniform vec3 color_mid : source_color = vec3(0.122, 0.388, 0.502);
uniform vec3 color_shallow : source_color = vec3(0.337, 0.733, 0.792);
uniform vec3 color_foam : source_color = vec3(0.922, 0.961, 1.0);
uniform vec3 color_ripple_glow : source_color = vec3(0.4, 0.98, 0.85);

// ====== SHADING PARAMS ======
uniform int shade_bands : hint_range(2, 5) = 3;
uniform float foam_threshold = 0.3;
uniform float crest_sharpness = 0.8;
uniform float edge_foam_width = 0.5;
uniform float ripple_glow_intensity = 3.0;

// ====== TEXTURE INPUTS ======
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

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
	if (level_index < 2.5 && abs(swe_area.z) > 0.001) {
		vec2 swe_uv = (v_world_pos.xz - swe_area.xy) / swe_area.zw;
		if (swe_uv.x >= 0.0 && swe_uv.x <= 1.0 && swe_uv.y >= 0.0 && swe_uv.y <= 1.0) {
			h_swe = textureLod(swe_simulation_map, swe_uv, 0.0).r * swe_height_scale;
		}
	}
	
	// FFT - IMPORTANT: Snap UV coordinates to match vertex grid!
	vec2 fft_uv = floor(v_world_pos.xz / snap_size) * snap_size / texture_scale;
	h_fft = textureLod(displacement_map, fft_uv, 0.0).r * height_scale;
	
	v_ripple_h = h_swe;
	v_wave_h = h_fft;
	
	// Sharp crest formula (no softening - we want angular peaks!)
	float combined_h = h_swe + h_fft;
	v_total_h = combined_h * wave_height_scale;
	
	// Apply crest sharpness (makes peaks pointier)
	if (crest_sharpness > 0.01) {
		v_total_h = sign(v_total_h) * pow(abs(v_total_h), crest_sharpness);
	}
	
	v_world_pos.y += v_total_h;
	
	VERTEX = (inverse(MODEL_MATRIX) * vec4(v_world_pos, 1.0)).xyz;
	v_view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 1. FLAT SHADING (World Space consistent)
	// Calculate normals using VERTEX (which is world space position in Godot spatial fragments)
	vec3 ddx = dFdx(VERTEX);
	vec3 ddy = dFdy(VERTEX);
	vec3 face_normal = normalize(cross(ddx, ddy));
	
	// 2. STYLIZED LIGHTING
	vec3 light_dir = normalize(vec3(0.5, 1.0, 0.3));
	float ndotl = dot(face_normal, light_dir) * 0.5 + 0.5;
	
	// Create discrete lighting bands
	float shade = floor(ndotl * float(shade_bands)) / float(shade_bands);
	shade = max(shade, 0.4); // Minimum ambient for better visibility
	
	// 3. DEPTH & COLOR CALCULATION
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_depth = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_depth.xyz /= view_pos_depth.w;
	
	float water_depth = max(length(view_pos_depth.xyz) - length(v_view_pos), 0.0);
	
	// Factors for color mixing
	float depth_factor = clamp(water_depth / 5.0, 0.0, 1.0);
	float wave_factor = (v_total_h / wave_height_scale) * 0.5 + 0.5;
	
	// Mix color based on depth and waves
	float color_mix = mix(wave_factor, depth_factor, min(depth_factor, 0.5));
	
	// 3-tier posterized color system
	vec3 base_color;
	if (color_mix > 0.66) {
		base_color = color_deep;
	} else if (color_mix > 0.33) {
		base_color = color_mid;
	} else {
		base_color = color_shallow;
	}
	
	// 4. FOAM & SHORELINE
	float wave_foam = step(foam_threshold, v_total_h / wave_height_scale);
	
	// Interaction Foam (From SWE ripples)
	float interaction_foam = step(0.15, abs(v_ripple_h) * 2.0);
	
	// Wave-to-Object Splash (Simulated via proximity + wave height)
	float object_proximity = 1.0 - clamp(water_depth / 1.5, 0.0, 1.0);
	float wave_splash = step(0.5, v_total_h / wave_height_scale) * object_proximity;
	
	float combined_foam = max(max(wave_foam, interaction_foam), wave_splash);
	base_color = mix(base_color, color_foam, combined_foam);
	
	// Edge foam (Shoreline)
	if (depth_raw < 0.999) {
		float edge_foam = smoothstep(edge_foam_width, 0.0, water_depth);
		base_color = mix(base_color, color_foam, edge_foam * 0.8);
	}
	
	// 5. RIPPLE GLOW & EMISSION
	float ripple_intensity = abs(v_ripple_h) * 15.0;
	ripple_intensity = smoothstep(0.1, 1.0, ripple_intensity); 
	vec3 ripple_emission = color_ripple_glow * ripple_intensity * ripple_glow_intensity;
	
	// Add interaction foam emission (makes it pop)
	ripple_emission += color_foam * interaction_foam * 0.5;
	ripple_emission += color_foam * wave_splash * 1.5;
	
	// 6. DEBUG MODES
	if (debug_lod) {
		vec3 lod_colors[6] = {
			vec3(1.0, 0.2, 0.2), vec3(0.2, 1.0, 0.2), vec3(0.2, 0.2, 1.0),
			vec3(1.0, 1.0, 0.2), vec3(1.0, 0.2, 1.0), vec3(0.2, 1.0, 1.0)
		};
		base_color = mix(base_color, lod_colors[int(v_level) % 6], 0.3);
	}
	
	if (debug_wireframe) {
		vec2 grid = fract(v_grid_uv * (grid_resolution - 1.0));
		float edge = 0.05 * (1.0 + v_level);
		float wire = step(edge, grid.x) * step(edge, grid.y);
		base_color = mix(vec3(0.0, 1.0, 1.0), base_color, wire);
	}
	
	// 7. FINAL OUTPUT
	ALBEDO = base_color * shade;
	EMISSION = ripple_emission;
	
	// Hard-edge Specular
	vec3 view_dir = normalize(-v_view_pos);
	vec3 half_vec = normalize(view_dir + light_dir);
	float spec = pow(max(dot(face_normal, half_vec), 0.0), 48.0);
	float spec_mask = step(0.7, spec);
	EMISSION += color_foam * spec_mask * 1.5;
	
	NORMAL = face_normal;
}
