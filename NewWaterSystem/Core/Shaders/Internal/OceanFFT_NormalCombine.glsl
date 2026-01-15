#version 450

// Detail Normal Combiner - Step 7 Optimization
// Bends two normal maps with time-offset dual-sampling anti-tiling logic
// into a single Master Normal Map for the fragment shader.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D normal_map1;
layout(set = 0, binding = 1) uniform sampler2D normal_map2;
layout(set = 0, binding = 2, rgba8) uniform writeonly image2D output_texture;

layout(push_constant) uniform Params {
    float time;
    float normal_speed;
    float normal_tile;
    int resolution;
} params;

// RNM Normal Blending helper
vec3 blend_normals_rnm(vec3 n1, vec3 n2) {
    n1 = n1 * 2.0 - vec3(1.0, 1.0, 0.0);
    n2 = n2 * vec3(-2.0, -2.0, 2.0) + vec3(1.0, 1.0, -1.0);
    return n1 * dot(n1, n2) / n1.z - n2;
}

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    if (uv.x >= params.resolution || uv.y >= params.resolution) return;

    // Use normalized coordinates for sampling
    vec2 coord = vec2(uv) / float(params.resolution);
    
    // Reproduce the anti-tiling logic from the fragment shader
    // We use coord as a base instead of v_world_pos.xz
    vec2 normal_uv1 = coord * 1.0; 
    vec2 normal_uv2 = coord.yx * 1.1 + vec2(params.time * 0.05, -params.time * 0.03);
    
    vec3 n1_a = texture(normal_map1, normal_uv1 + params.time * params.normal_speed).rgb * 2.0 - 1.0;
    vec3 n1_b = texture(normal_map1, normal_uv2 - params.time * params.normal_speed * 0.7).rgb * 2.0 - 1.0;
    vec3 n1_sample = normalize(n1_a + n1_b);
    
    vec3 n2_a = texture(normal_map2, normal_uv1 * 1.2 - params.time * params.normal_speed * 1.5).rgb * 2.0 - 1.0;
    vec3 n2_b = texture(normal_map2, normal_uv2 * 0.9 + params.time * params.normal_speed * 0.8).rgb * 2.0 - 1.0;
    vec3 n2_sample = normalize(n2_a + n2_b);
    
    vec3 detail_normal = normalize(n1_sample + n2_sample);
    
    // Store in [0, 1] range
    imageStore(output_texture, uv, vec4(detail_normal * 0.5 + 0.5, 1.0));
}
