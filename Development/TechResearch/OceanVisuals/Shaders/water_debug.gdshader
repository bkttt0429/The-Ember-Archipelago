shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D displacement_map : repeat_enable, filter_linear;
uniform float texture_scale = 50.0;
uniform vec4 swe_area; // xy: min, zw: size

varying vec2 v_uv;
varying vec3 v_world_pos;
varying float v_disp_y;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_uv = v_world_pos.xz / texture_scale;
    
    vec4 disp = texture(displacement_map, v_uv);
    v_disp_y = disp.y;
    
    // Minimal displacement to keep water visible but flat-ish
    VERTEX.y += disp.y * 1.0; 
}

void fragment() {
    // MODE 1: Visualize UVs
    // ALBEDO = vec3(fract(v_uv.x), fract(v_uv.y), 0.0);
    
    // MODE 2: Visualize Displacement value range
    // If disp.y is > 0.5 (grey), it will be bright.
    // If it's truly centered at 0 (black), it will be black.
    // Ideally waves should be around 0.5 if stored in 0..1 texture, or 0.0 if float texture.
    
    ALBEDO = vec3(v_disp_y); 
    
    // Visualize 0.0 as Blue, 0.5 as Grey, 1.0 as White
    if (v_disp_y < 0.0) ALBEDO = vec3(1.0, 0.0, 0.0); // Red = Negative! (Good if float texture)
    
    // Outline SWE Area
    bool in_swe = (v_world_pos.x >= swe_area.x && v_world_pos.x <= swe_area.x + swe_area.z &&
                   v_world_pos.z >= swe_area.y && v_world_pos.z <= swe_area.y + swe_area.w);
                   
    if (in_swe) {
        ALBEDO = mix(ALBEDO, vec3(0.0, 1.0, 0.0), 0.5); // Green tint in SWE area
    }
}
