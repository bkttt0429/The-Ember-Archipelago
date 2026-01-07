/*
	Pixel Water Shader by: Taillight Games - contact@taillight.games
	MIT Lisence
*/

shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_always, ambient_light_disabled, diffuse_burley;

// this must be set every frame in code for it to sync with the WaterManager
// if you don't need the time to agree with your code, just replace instances of this with TIME
// this must be set every frame in code for it to sync with the WaterManager
// if you don't need the time to agree with your code, just replace instances of this with TIME
uniform float sync_time; 

// --- Advanced Settings ---
uniform float contact_foam_depth = 0.5; // Distance from shore to show foam
uniform float contact_foam_power = 2.0;
uniform sampler2D contact_shape_noise : filter_linear_mipmap; // Reuse existing noise for shape 
uniform sampler2D ripple_map : filter_linear_mipmap;
uniform float ripple_map_size = 50.0; 

varying vec3 triplanar_pos;
varying vec3 power_normal;
varying vec3 world_normal;
varying vec3 object_normal;
varying float v_height;
varying mat4 camera_mix;


uniform float wave_speed = 0.05; // the speed of the vertex waves
uniform float caustic_speed = 0.01; // speed that the caustics noise texture is moved

uniform float edge_fade_power = 2.0; // controls the contrast on the opacity fading when objects are on the surface

uniform float transmittence = 0.04; // how much light transmits through the water
uniform float h_dist_trans_weight = 3.0; // how much does the horizontal distance from the position affect its depth
uniform vec3 transmit_color : source_color; // a color correction applied to the screen texture coming from under the water

uniform float depth_fade : hint_range(0.0, 0.5, 0.01) = 0.3; // the power of the depth fade
uniform float depth_fade_distance : hint_range(0.0, 100.0, 0.1) = 5.0; // the downward distance of the depth fade

uniform vec3 surface_albedo : source_color; // surface color on the top of the plane, in most areas this is overrriden by other colors, it will usually only be visible in shallow water
uniform vec4 surface_bottom : source_color; // the color of the underside of the water

uniform float opacity : hint_range(0.0, 5.0, 0.01) = 0.4; // general opacity amount
uniform float opacity_floor = 0.1; // opacity minimum
uniform float opacity_ceiling = 0.8; // opacity maximum

uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.4;

uniform float height_scale = 1; // the scale of the waves in units
uniform float amplitude1 = 2; // the relative scale of vertex_noise_big
uniform float amplitude2 = 0.5; // the relative scale of vertex_noise_big2

uniform sampler2D vertex_noise_big : repeat_enable;
uniform sampler2D vertex_noise_big2 : repeat_enable;

uniform int v_noise_tile : hint_range(0, 300, 1) = 200; // tiling of the vertex_noise_texture in units

varying flat vec3 norm;

// 2 normal textures that move at different angles to eachother to create an effect
uniform sampler2D normal_noise : hint_normal, filter_linear_mipmap;
uniform sampler2D normal_noise2 : hint_normal, filter_linear_mipmap;

uniform float normal_noise_size = 5.12;
uniform float normal_noise_speed = 0.05;
uniform float v_normal_scale = 1; 
uniform int normal_map_w = 256; 

// --- Gerstner Wave Parameters ---
group_uniforms Gerstner_Waves;
uniform vec4 wave_a = vec4(1.0, 0.0, 0.15, 10.0); // xy: Direction, z: Steepness, w: Wavelength
uniform vec4 wave_b = vec4(0.0, 1.0, 0.15, 20.0); 
uniform vec4 wave_c = vec4(0.7, 0.7, 0.1, 5.0); 
uniform vec4 wave_d = vec4(-0.5, 0.5, 0.08, 3.0); // New Wave D
uniform vec4 wave_e = vec4(0.2, -0.8, 0.05, 1.5); // New Wave E 

// Hybrid Noise for Ripples
uniform float ripple_height_scale = 0.1;




uniform float wobble_power = 0.01;
uniform sampler2D under_wobble_noise;

varying vec3 npw;

uniform vec3 sky_color : source_color;

varying vec4 v_color;

group_uniforms foam;

uniform vec3 foam_color : source_color;

uniform sampler2D foam : repeat_enable;

// for proper use, set this to a SubViewport that only draws where it 
uniform sampler2D foam_mask : filter_nearest_mipmap; 

uniform float foam_mask_size; // MUST be set to the size of the orthographic foam mask camera's size
uniform vec2 foam_mask_offset = vec2(0, 0); // used to adjust for errors in the foam lineup

uniform float foam_wobble = 0.01;

uniform sampler2D foam_wobble_noise : filter_linear_mipmap;
uniform float foam_wobble_size = 10.0;
varying float foam_power;

group_uniforms v_color;

// to fake tramsittence, waves can have a different color as they get higher
uniform vec3 high_color : source_color;
uniform vec3 low_color : source_color;

varying vec3 wave_color;

uniform float wave_color_range = 2.0; // controls the power of the wave colors

uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D depth_texture : hint_depth_texture;

vec2 round_to_pixel(vec2 i, int width)
{

	float denom = 1.0 / float(width);
	float _x = i.x + abs(mod(i.x, denom) - denom);
	float _y = i.y + abs(mod(i.y , denom) - denom);
	return vec2(_x, _y);
}

float round_to_pixel_f(float i, int width)
{

	float denom = 1.0 / float(width);
	float _x = i + abs(mod(i, denom) - denom);
	return _x;
}

float remap(float in_low, float in_high, float out_low, float out_high, float value)
{
	return out_low + (value - in_low) * (out_high - out_low) / (in_high - in_low);
}


// global uv
vec2 g_uv(vec2 uv, float speed, bool flipped, vec3 n) {

	vec2 _xy;
	_xy.x = uv.x;
	_xy.y = uv.y;

	float t_s = TIME * speed;

	if(!flipped)
	{
		_xy.x += t_s;
		_xy.y += t_s;
	} else {
		_xy.x -= t_s;
		_xy.y -= 0.0;
	}

	return _xy;

}	

vec2 g_v(vec2 v, vec3 n, bool flipped)
{

	float f_v_n_t = float(v_noise_tile);

	v.x = mod(v.x, f_v_n_t);
	v.y = mod(v.y, f_v_n_t);

	vec2 _mapped = vec2(remap(0, f_v_n_t, 0, 1, v.x), remap(0, f_v_n_t, 0, 1, v.y));

	_mapped += n.xz;
	if(flipped)
	{
		_mapped.y -= (TIME) * wave_speed;
	} else {
		_mapped.x += (TIME) * wave_speed;
	}

	_mapped.x = mod(_mapped.x, 1);

	return _mapped;

}

vec2 rotate(vec2 n, float angle) {
	float _ar = radians(angle);
	float _x = n.x * (cos(_ar) - sin(_ar));
	float _y = n.y * (sin(_ar) - cos(_ar));
	return vec2(_x, _y);
}



vec3 gerstner_wave(vec4 wave_params, vec3 p, inout vec3 tangent, inout vec3 binormal) {
	float steepness = wave_params.z;
	float wavelength = wave_params.w;
	
	float k = 2.0 * 3.14159 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(wave_params.xy);
	
	float f = k * (dot(d, p.xz) - c * sync_time * wave_speed); // using wave_speed as a global multiplier
	float a = steepness / k; // Amplitude
	
	float cos_f = cos(f);
	float sin_f = sin(f);
	
	// Displacement
	float d_x = d.x * (a * cos_f);
	float d_z = d.y * (a * cos_f);
	float d_y = a * sin_f;
	
	// Derivatives (for Normal calc if we wanted analytic, but we use finite difference for hybrid simplicity)
	// Leaving tangent/binormal calcs for future if needed, currently returning displacement
	
	return vec3(d_x, d_y, d_z);
}

// Hybrid Wave Function: Gerstner Posisitons + Noise Height
vec3 get_displacement(vec3 p) {
	vec3 final_p = p;
	vec3 displacement = vec3(0.0);
	
	// Tangent/Binormal accumulation (unused for now, keeping simple)
	vec3 t = vec3(1,0,0);
	vec3 b = vec3(0,0,1);
	
	displacement += gerstner_wave(wave_a, p, t, b);
	displacement += gerstner_wave(wave_b, p, t, b);
	displacement += gerstner_wave(wave_c, p, t, b);
	displacement += gerstner_wave(wave_d, p, t, b);
	displacement += gerstner_wave(wave_e, p, t, b);
	
	return displacement;
}

// Keep the old noise wave function for surface texture/ripples ONLY
float sample_ripple_noise(vec2 uv) {
	float h = 0.0;
	// Use the existing noise textures but simpler
	h += texture(vertex_noise_big, uv * 0.1 + vec2(sync_time * 0.02, 0.0)).r;
	return h * ripple_height_scale;
}

void vertex() {

	npw = NODE_POSITION_WORLD;
	
	// 1. Calculate Gerstner Displacement
	vec3 disp = get_displacement(NODE_POSITION_WORLD + VERTEX);
	
	// 2. Add Ripples (Hybrid)
	float ripples = sample_ripple_noise(NODE_POSITION_WORLD.xz);
	
	// 3. Add Dynamic Ripples (Simulation)
	// Map World Pos to 0-1 UV
	vec2 ripple_uv = (NODE_POSITION_WORLD.xz + vec2(ripple_map_size/2.0)) / ripple_map_size;
	// Clamp to avoid edge artifacts if outside range
	float dynamic_ripple = texture(ripple_map, ripple_uv).r;
	
	// Domain Warping for Irregularity
	vec2 warp = vec2(
		sin(NODE_POSITION_WORLD.z * 0.1 + sync_time * 0.1),
		cos(NODE_POSITION_WORLD.x * 0.1 + sync_time * 0.1)
	) * 4.0; // Increased warp strength for more winding waves
	
	// Recalculate displacement with warp
	vec3 disp_warped = get_displacement(NODE_POSITION_WORLD + VERTEX + vec3(warp.x, 0, warp.y));
	
	// Combine
	vec3 final_disp = disp_warped;
	// Boost dynamic ripple influence (x2.0)
	final_disp.y += ripples + dynamic_ripple * 2.0;

	VERTEX += final_disp;
	// Pass dynamic ripple to fragment for valid "foam/highlight" if needed
	v_height = final_disp.y; 
	
	// Calculate Normals (Finite Difference method remains robust for hybrid waves)
	vec2 e = vec2(0.1, 0.0);
	vec3 p_center = NODE_POSITION_WORLD + VERTEX; // Already displaced? No, finite diff needs base pos
	// Note: For correct normal recalculation on displaced mesh without analytic normals, 
	// we need to sample the wave function at offset positions.
	
	vec3 p_calc = NODE_POSITION_WORLD + (VERTEX - disp); // Back to base
	
	vec3 d_c = get_displacement(p_calc);
	vec3 d_r = get_displacement(p_calc + vec3(e.x, 0, 0));
	vec3 d_f = get_displacement(p_calc + vec3(0, 0, e.x));
	
	// Add ripples to these samples too
	d_c.y += sample_ripple_noise(p_calc.xz) + texture(ripple_map, (p_calc.xz + vec2(ripple_map_size/2.0))/ripple_map_size).r;
	d_r.y += sample_ripple_noise(p_calc.xz + e.xy) + texture(ripple_map, (p_calc.xz + e.xy + vec2(ripple_map_size/2.0))/ripple_map_size).r;
	d_f.y += sample_ripple_noise(p_calc.xz + e.yx) + texture(ripple_map, (p_calc.xz + e.yx + vec2(ripple_map_size/2.0))/ripple_map_size).r;

	vec3 p_right = (p_calc + vec3(e.x, 0, 0)) + d_r;
	vec3 p_forward = (p_calc + vec3(0, 0, e.x)) + d_f;
	vec3 p_current = p_calc + d_c;
	
	vec3 t = p_right - p_current;
	vec3 b = p_forward - p_current;
	
	NORMAL = normalize(cross(b, t));

	float wave_color_mix = remap(-wave_color_range, wave_color_range, 0.0, 1.0, disp.y);




	triplanar_pos = VERTEX.xyz * vec3(1.0, 0, 1.0);

	v_color = COLOR.rgba;

	camera_mix = INV_VIEW_MATRIX;
}

void fragment() {

	// render the top
	ROUGHNESS = roughness;
	vec3 _albedo;
	vec3 deep;

	vec2 wobble_uv = (texture(under_wobble_noise, g_uv(UV, caustic_speed, false, NODE_POSITION_WORLD) * 10.0).xy * wobble_power);
	wobble_uv -= wobble_power * 0.86;

	vec3 under = texture(screen_texture, SCREEN_UV + wobble_uv).rgb;

	// from: https://www.reddit.com/r/godot/comments/jpreaw/comment/gblb1ou/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
	float depth3 = texture(depth_texture, SCREEN_UV + wobble_uv).x;
	vec3 ndc3 = vec3(SCREEN_UV + wobble_uv, depth3) * 2.0 - 1.0;
	vec4 world3 = camera_mix * INV_PROJECTION_MATRIX * vec4(ndc3, 1.0);
	vec3 world_position = world3.xyz / world3.w;

	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;

	float _dist = distance(world_position.y, vertex_y);
	// the horizontal distance to the location, used to fade as the camera gets farther away
	float _h_dist = distance(triplanar_pos, world_position);

	_dist += _h_dist * h_dist_trans_weight;

	// Changes the color of geometry behind it as the water gets deeper
	float depth_fade_blend = exp(-_dist / depth_fade_distance);

	depth_fade_blend = clamp(depth_fade_blend, 0.0, 1.0);

	// Makes the water more transparent as it gets more shallow
	float alpha_blend = -_dist * transmittence;
	//alpha_blend = pow(alpha_blend, transmittence_pow); // unused code to apply a pow() function, edge_fade_power serves this purpose
	alpha_blend = clamp(1.0 - exp(alpha_blend), 0.7, 1.0);

	deep = mix(wave_color, surface_albedo, depth_fade_blend);

	vec2 rounded_uv = round_to_pixel((triplanar_pos.xz * (1.0 / normal_noise_size)) * 0.1, normal_map_w);

	vec3 n_map1 = texture(normal_noise, g_uv(rounded_uv, normal_noise_speed, false, NODE_POSITION_WORLD)).xyz;
	vec3 n_map2 = texture(normal_noise2, g_uv(rounded_uv, normal_noise_speed, true, NODE_POSITION_WORLD)).xyz;

	NORMAL_MAP = mix(n_map1, n_map2, 0.5);

	if(FRONT_FACING)
	{
		_albedo = mix(under, deep, alpha_blend);
		float _ALPHA = remap(0.0, opacity, opacity_floor, opacity_ceiling, pow(alpha_blend, edge_fade_power));
		_albedo = mix(under + transmit_color, _albedo, _ALPHA);
	} else {
		NORMAL = -NORMAL;
		NORMAL_MAP = mix(vec3(1.,1.,1.), vec3(0.,0.,0.), NORMAL_MAP);
		vec3 over = texture(screen_texture, SCREEN_UV + wobble_uv).rgb;
		_albedo = mix(over, surface_bottom.rgb, surface_bottom.a);

	}
	ALBEDO = _albedo;

	// --- Visual Improvement: Specular & Fresnel (Desire for "Wetness") ---
	// Fresnel: Make water reflective at angles
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(ALBEDO, sky_color + vec3(0.1), fresnel * 0.4);

	// --- Visual Improvement: Wave Crest Foam (Desire for "Motion") ---
	// Add white caps to top of waves, ensuring they are broken up by noise
	// Max potential height is approx (Amp1 + Amp2 - HeightScale*0.5) * HeightScale
	// With defaults: (2.0 + 0.2 - 0.5) * 1.0 = 1.7.
	// We want foam only at the very top (e.g., > 1.45).
	float crest_trigger = 1.35; 
	
	// Noise lookup for foam breakup
	float crest_noise = texture(foam, g_uv(rounded_uv * 1.2, normal_noise_speed * 1.5, true, NODE_POSITION_WORLD)).r;
	
	// Organic styled cutoff
	// If (Height + Noise) > Threshold -> Foam.
	// Using smoothstep with a small range instead of step for a slightly softer, less "MSPaint" edge
	float foam_val = v_height + crest_noise * 0.5; // Increased noise influence
	
	// Sharper step for anime/stylized look
	float foam_mix = step(crest_trigger, foam_val);
	
	// Add a subsurface scattering rim effect to the foam (simulated)
	// Foam is thicker in the middle (white) and thinner at edges (slightly blueish)
	vec3 foam_color_final = mix(high_color + vec3(0.1), vec3(0.95, 0.98, 1.0), foam_mix);
	
	// --- DEPTH CONTACT FOAM (Visual Layer 1) ---
	// Calculate linear depth difference
	float scene_depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;
	float linear_water_depth = VERTEX.z; // In view space? Wait, VERTEX is view space in fragment? NO.
	// In Godot Fragment shader, VERTEX is view space.
	
	float depth_diff = linear_scene_depth - vertex_y; // vertex_y calculated above is (INV_VIEW * vec4(VERTEX, 1.0)).y which is WORLD Y. 
	// Wait, standard depth read method:
	
	// Re-calculate robust depth diff
	float z_depth = scene_depth_raw; // Non-linear
	vec4 world_from_depth = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z_depth, 1.0);
	world_from_depth.xyz /= world_from_depth.w;
	
	// Difference in World Y
	float water_world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float shore_dist = world_from_depth.y - water_world_y;
	
	// Shore Foam Logic
	// If the ground is close to water surface (shore_dist small)
	if (shore_dist < contact_foam_depth && shore_dist > -0.1) {
		float foam_intensity = 1.0 - smoothstep(0.0, contact_foam_depth, shore_dist);
		
		// Breakup with noise
		float shore_noise = texture(vertex_noise_big, (world_position.xz + vec2(TIME * 0.05)) * 0.5).r;
		foam_intensity *= step(0.4, shore_noise + foam_intensity * 0.5);
		
		ALBEDO = mix(ALBEDO, foam_color, foam_intensity);
	}


	
	// --- RIPPLE HIGHLIGHT ---
	// Sampling ripple map again in fragment to add color tint to ripples
	vec2 r_uv = (NODE_POSITION_WORLD.xz + vec2(ripple_map_size/2.0)) / ripple_map_size;
	float rip_val = texture(ripple_map, r_uv).r;
	// If ripple is high/steep, lighten the color (fake crest)
	float rip_highlight = smoothstep(0.1, 0.3, abs(rip_val));
	ALBEDO = mix(ALBEDO, foam_color, rip_highlight * 0.5);

	ALBEDO = mix(ALBEDO, foam_color_final, foam_mix * 0.9);

	ALBEDO = mix(sky_color, ALBEDO, v_color.a);

	vec4 projected_coords = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0));

	world_normal = abs(INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;

	vec2 porj_pos = projected_coords.xz;

	vec2 porj_pos_w = (porj_pos - NODE_POSITION_WORLD.xz);

	float foam_m = 0.0;

	if (distance(vec2(NODE_POSITION_WORLD.x, NODE_POSITION_WORLD.z), porj_pos) < foam_mask_size / 2.0)
	{

		vec2 r_f_m = (porj_pos_w + vec2(foam_mask_size / 2.0) )  / foam_mask_size;
		r_f_m += foam_mask_offset / 100.0;
		foam_m = texture(foam_mask, (r_f_m)).r;
	}

	if (foam_m > 0.05)
	{
		// Distort UVs slightly for liquid feel
		vec2 wobble_uv2 = (texture(foam_wobble_noise, g_uv(rounded_uv / foam_wobble_size, caustic_speed, false, NODE_POSITION_WORLD)).xy) * foam_wobble;
		
		// Sample the separate Cellular Noise texture we set up
		vec4 f_sample = texture(foam, g_uv(rounded_uv + wobble_uv2, normal_noise_speed, true, NODE_POSITION_WORLD));
		
		// --- KEY FIX: Binary Bubble Cutoff ---
		// Instead of alpha blending (milky look), we use step() to create hard edges.
		// "foam_m" is the wake intensity (1.0 near boat). 
		// "f_sample.r" is the cellular noise pattern.
		// We subtract noise from the wake intensity to "break it up".
		
		float erosion = 0.6; // How much the bubbles eat away the solid shape
		float bubble_mask = step(erosion, (foam_m * 1.5) * f_sample.r); 
		
		// Only draw foam where bubbles exist
		ALBEDO = mix(ALBEDO, foam_color, bubble_mask);
	}

}



group_uniforms lighting;

// An optional mode used for my game where the lighting ignores the view angle
// Inaccurate to real life but looks kinda cool
uniform bool enable_fake_lighting = false; 

uniform float shine_strength : hint_range(0.0f, 1.0f) = 0.17f;
uniform float shine_shininess : hint_range(0.0f, 32.0f) = 18.0f;

uniform float shadow : hint_range(0.0, 1.0) = 0.72;
uniform float shadow_width : hint_range(0.001, 0.5) = 0.18;
uniform vec4 shadow_color: source_color = vec4(0.705);

uniform float _specular_smoothness : hint_range(0.0,0.5) = 0.199;
uniform float _specular_strength : hint_range(0.0,9.25) = 0.075;
uniform float _glossiness : hint_range(0.0,0.5) = 0.067;

// unused rim feature
//uniform float _rim_size : hint_range(0,1) = 0.5;
//uniform float _rim_smoothness : hint_range(0.0,0.5) = 0.01;

// light shader code from: https://godotshaders.com/shader/toon/ and https://godotshaders.com/shader/flexible-toon-shader-godot-4/
void light()
{
	vec3 H;

	if (enable_fake_lighting)
	{
		H = normalize(LIGHT);
	} else {
		H = normalize(VIEW + LIGHT);
	}
		float NdotH = dot(NORMAL, H);
		float specular_amount = max(pow(NdotH, shine_shininess * shine_shininess), 0.0f)
								* ATTENUATION;
	SPECULAR_LIGHT += shine_strength * specular_amount * LIGHT_COLOR;

	float NdotL = dot(NORMAL, LIGHT) * ATTENUATION;
	NdotL = smoothstep(shadow - shadow_width, shadow + shadow_width, NdotL);

	// specular
	float specular_intensity = pow(NdotH, 1.0 / _glossiness);
	vec3 specular = vec3(smoothstep(0.5 - _specular_smoothness, 0.5 + _specular_smoothness, specular_intensity));

	// rim related stuff, not used
	//float rimDot = 1.0 - dot(VIEW, NORMAL);
	//float rim_intensity = rimDot * NdotL;
	//vec3 rim = vec3(smoothstep(1.0 -_rim_size - _rim_smoothness, 1.0 -_rim_size + _rim_smoothness, rim_intensity));
	vec3 rim = vec3(1.0);
	float rimDot = 1.0 - NORMAL.z;

	DIFFUSE_LIGHT += ATTENUATION * mix(ALBEDO * shadow_color.rgb, (ALBEDO + (rim + specular) * _specular_strength) * LIGHT_COLOR.rgb * 0.33, NdotL + 0.33/* * (smoothstep(1.0 -_rim_size - _rim_smoothness, 1.0 -_rim_size + _rim_smoothness, rimDot))*/);
	DIFFUSE_LIGHT = mix(sky_color, DIFFUSE_LIGHT, v_color.r);
	SPECULAR_LIGHT = mix(vec3(0.0), SPECULAR_LIGHT, v_color.r);
	SPECULAR_LIGHT = mix(SPECULAR_LIGHT, vec3(0.0), foam_power);
	DIFFUSE_LIGHT = mix(DIFFUSE_LIGHT, foam_color, foam_power);

}
