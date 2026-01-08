shader_type spatial;
render_mode cull_back, depth_draw_opaque; // Removed depth_test_enabled which may be invalid or covered by default

// Parameter for the FFT displacement texture
uniform sampler2D displacement_map : repeat_enable, filter_linear;
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

varying float v_swe_h;
varying float v_swe_foam;

void vertex() {
    // 1. FFT Displacement
    vec4 displacement = texture(displacement_map, UV);
    
    // 2. SWE Interaction Blending
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // Convert World Pos -> SWE UV
    // uv = (pos - min) / size
    vec2 swe_uv = (world_pos.xz - swe_area.xy) / swe_area.zw;
    
    float swe_h = 0.0;
    float swe_foam = 0.0;
    
    // Check bounds with margin
    if (swe_uv.x > 0.0 && swe_uv.x < 1.0 && swe_uv.y > 0.0 && swe_uv.y < 1.0) {
        vec4 swe_val = texture(swe_simulation_map, swe_uv);
        float h_raw = swe_val.r;
        float f_raw = swe_val.a;
        
        // Edge Fading (Soft blend at edges of simulation area)
        float d_x = abs(swe_uv.x - 0.5);
        float d_y = abs(swe_uv.y - 0.5);
        float max_d = max(d_x, d_y);
        
        // Fade out starting at 0.45 (90% from center), fully zero at 0.5
        float fade = 1.0 - smoothstep(0.45, 0.5, max_d);
        
        swe_h = h_raw * fade;
        swe_foam = f_raw * fade;
    }
    
    v_swe_h = swe_h;
    v_swe_foam = swe_foam;

    // Apply displacements

    // Apply displacements
    VERTEX.y += displacement.y + swe_h;
    VERTEX.x += displacement.x;
    VERTEX.z += displacement.z;
}

void fragment() {
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
    // NORMAL_MAP not needed as we are using geometry normals
    
    // 2. Stylized Foam (Depth-based)
    float depth = texture(depth_texture, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = -view.z;
    
    float object_depth = VERTEX.z; // In View space, z is negative depth
    // Difference between water surface and object behind it
    // Note: VERTEX.z is negative in Godot's view space
    float depth_diff = linear_depth - (-VERTEX.z);
    
    // Step function for hard-edge low poly foam
    float foam_mask = step(depth_diff, foam_threshold);
    
    // Add Dynamic SWE Foam
    // v_swe_foam is intensity (0..1). We can threshold it or just add it.
    // Let's threshold it for consistency with low-poly style.
    float swe_foam_amount = v_swe_foam;
    float swe_foam_mask = step(0.1, swe_foam_amount);
    
    // Combine Masks
    float total_foam = max(foam_mask, swe_foam_mask);
    
    // Mixing Base Color
    vec3 final_color = mix(albedo.rgb, foam_color.rgb, total_foam);
    
    // 3. Fake Subsurface Scattering (SSS)
    // Simple gradient based on height or normal facing up
    // Light passing through waves: approximate with view direction and normal
    float fresnel = sqrt(max(0.0, 1.0 - dot(NORMAL, VIEW)));
    vec3 sss = sss_color.rgb * fresnel * sss_strength;
    
    // Add SSS only to non-foam areas
    final_color += sss * (1.0 - total_foam);
    
    // Ensure color values are valid (prevent NaN/Inf)
    final_color = clamp(final_color, vec3(0.0), vec3(10.0));

    ALBEDO = final_color;
    ROUGHNESS = roughness;
    SPECULAR = specular;
}
