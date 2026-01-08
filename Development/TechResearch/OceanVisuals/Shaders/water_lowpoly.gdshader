shader_type spatial;
render_mode cull_back, depth_draw_opaque; 

// Parameter for the FFT displacement texture
// Parameter for the FFT displacement texture
uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 64.0; // Scale of the texture mapping in world units
uniform float height_scale = 1.0; // Vertical scale of the waves
uniform float choppiness : hint_range(0.0, 2.0) = 0.15; // Horizontal displacement scale (keep low to avoid self-intersection)
uniform vec4 albedo : source_color = vec4(0.0, 0.4, 0.8, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

// Foam parameters
uniform sampler2D depth_texture : hint_depth_texture;
uniform vec4 foam_color : source_color = vec4(1.0);
uniform float foam_threshold : hint_range(0.0, 2.0) = 0.5;

// SSS & Lighting
uniform vec4 sss_color : source_color = vec4(0.0, 0.4, 0.5, 1.0);
uniform float sss_strength : hint_range(0.0, 1.0) = 0.5;


// SWE Blending
uniform sampler2D swe_simulation_map : filter_linear; // R: Height, G: Vertical Vel
uniform vec4 swe_area; // xy: min_pos (world), zw: size (world)
uniform float swe_color_strength : hint_range(0.0, 1.0) = 0.0;

// Debug Visualization
uniform bool debug_show_swe_area = false;
uniform bool debug_show_blend = false;

// ✅ LOD Precision Helpers
// instance uniform float grid_subdivisions = 32.0; // Removed as we use global grid now

varying float v_swe_h;
varying float v_swe_foam;
varying float v_in_swe_area; // Changed from bool to float because boolean varyings are not supported

	// ========================================
	// 🌊 Direct Sampling for Smooth Waves 🌊
	// ========================================
	
	// 1. Get world position
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	
	// 2. Sample Texture Directly
	// CPU script (OceanClipmap.gd) handles mesh-snapping to prevent swimming geometry.
	// We do NOT snap UVs here, because snapping UVs creates the "Staircase/Terrace" artifact.
	// We want smooth waves even on low-poly geometry.
	vec2 sample_uv = fract(world_pos.xz / texture_scale);
	vec4 displacement_sample = textureLod(displacement_map, sample_uv, 0.0);
	
	// ✅ Safety clamp to prevent exploding geometry
	vec3 displacement = clamp(displacement_sample.xyz, vec3(-10.0), vec3(10.0));

	// ========================================
	// SWE Simulation Logic
	// ========================================
	// swe_area: xy = min_pos (world), zw = size (world)
	vec2 swe_min = swe_area.xy;
	vec2 swe_size = swe_area.zw;
	vec2 swe_max = swe_min + swe_size;

	float margin = 0.05; // 5% margin for edge blending
	bool in_swe_area = (world_pos.x >= swe_min.x - margin * swe_size.x) && 
					   (world_pos.x <= swe_max.x + margin * swe_size.x) &&
					   (world_pos.z >= swe_min.y - margin * swe_size.y) && 
					   (world_pos.z <= swe_max.y + margin * swe_size.y);

	float swe_h = 0.0;
	float swe_foam = 0.0;

	if (in_swe_area) {
		// Calculate UV (clamp to valid range to avoid sampling errors)
		vec2 swe_uv = (world_pos.xz - swe_min) / swe_size;
		swe_uv = clamp(swe_uv, 0.0, 1.0);
		
		vec4 swe_val = textureLod(swe_simulation_map, swe_uv, 0.0);
		// Raw float height in RED channel
		float h_raw = swe_val.r;
		float f_raw = swe_val.a;
		
		// Edge Fading: Smooth blend at edges to avoid hard boundaries
		// Calculate distance from center (0.5, 0.5) normalized to [0, 0.5]
		vec2 center_dist = abs(swe_uv - 0.5);
		float max_dist = max(center_dist.x, center_dist.y);
		
		// Fade out in the outermost 10% (0.4 to 0.5) to ensure 0 at boundary
		// Changing smoothstep range to ensure it fully reaches 0 before the edge
		// ✅ 3. 擴大淡出範圍並使用平方曲線，使 SWE 邊界更柔和
		float fade_linear = 1.0 - smoothstep(0.3, 0.48, max_dist);
		float fade = fade_linear * fade_linear;
		
		swe_h = h_raw * fade;
		swe_foam = f_raw * fade;
	}

	v_swe_h = swe_h;
	v_swe_foam = swe_foam;
	v_in_swe_area = in_swe_area ? 1.0 : 0.0;

	// ✅ 4. Restore SWE Height
	float swe_h_safe = clamp(swe_h, -5.0, 5.0);

	// ✅ 5. Apply Final Displacement: FFT + SWE
	VERTEX.y += displacement.x * height_scale + swe_h_safe;
	// Keep X/Z zero for now to ensure 100% stability
}

void fragment() {
    // Debug Visualization
    if (debug_show_swe_area) {
        // Show SWE area as red, other areas as blue
        bool in_area = v_in_swe_area > 0.5;
        ALBEDO = in_area ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
        ROUGHNESS = 0.2;
        SPECULAR = 0.5;
    } else if (debug_show_blend) {
        // Show blend weight as color intensity
        // Calculate fade value from SWE height
        float blend_weight = v_swe_h > 0.0 ? 1.0 : 0.0;
        ALBEDO = vec3(blend_weight, blend_weight, blend_weight);
        ROUGHNESS = 0.2;
        SPECULAR = 0.5;
    } else {
    
    // 1. Dynamic Flat Shading
    // derivatives of the view-space position
    vec3 ddx = dFdx(VERTEX);
    vec3 ddy = dFdy(VERTEX);
    
    // Calculate face normal using cross product of derivatives
    vec3 face_normal = cross(ddx, ddy);
    float len = length(face_normal);
    
    // Safety check: avoid division by zero and NaN values
    // If the normal is too small, fall back to UP vector
    if (len < 0.0001) {
        face_normal = vec3(0.0, 1.0, 0.0);
    } else {
        face_normal = normalize(face_normal);
    }
    
    // Apply the flat normal
    NORMAL = face_normal;

    // 2. Stylized Foam (Depth-based)
    float depth = texture(depth_texture, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = -view.z;
    
    float object_depth = VERTEX.z; 
    float depth_diff = linear_depth - (-VERTEX.z);
    
    // Step function for hard-edge low poly foam
    // Slightly offset to avoid flickering on perfectly flat surfaces
    float foam_mask = step(depth_diff, foam_threshold + 0.02);
    
    // Dynamic SWE Foam
    float swe_foam_amount = v_swe_foam;
    float swe_foam_mask = step(0.1, swe_foam_amount);
    float total_foam = max(foam_mask, swe_foam_mask);
    
    // Mixing Base Color
    vec3 final_color = mix(albedo.rgb, foam_color.rgb, total_foam);
    
    // 3. Fake Subsurface Scattering (SSS)
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0);
    vec3 sss = sss_color.rgb * fresnel * sss_strength;
    final_color += sss * (1.0 - total_foam);

    ALBEDO = final_color;
    ROUGHNESS = roughness;
    SPECULAR = specular;
    }
}
