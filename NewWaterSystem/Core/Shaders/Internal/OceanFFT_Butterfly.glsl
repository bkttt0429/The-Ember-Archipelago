#version 450

// Radix-2 Butterfly FFT Pass
// Performs one stage of Cooley-Tukey FFT

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D tex_in;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D tex_out;

layout(push_constant) uniform Params {
    int stage;      // Current stage (0 to log2(N)-1)
    int direction;  // 0 for Horizontal, 1 for Vertical
} params;

const float PI = 3.14159265359;

vec2 complex_mul(vec2 a, vec2 b) {
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(tex_in);
    if (uv.x >= size.x || uv.y >= size.y) return;

    int n = (params.direction == 0) ? size.x : size.y;
    int idx = (params.direction == 0) ? uv.x : uv.y;
    
    int step = 1 << params.stage;
    int group_size = step << 1;
    int j = idx % step;
    int k = (idx / group_size) * group_size + j;
    
    // Twiddle factor
    float angle = -PI * float(j) / float(step);
    vec2 w = vec2(cos(angle), sin(angle));
    
    vec2 h_top, h_bottom;
    
    if (params.direction == 0) {
        h_top = imageLoad(tex_in, ivec2(k, uv.y)).xy;
        h_bottom = imageLoad(tex_in, ivec2(k + step, uv.y)).xy;
    } else {
        h_top = imageLoad(tex_in, ivec2(uv.x, k)).xy;
        h_bottom = imageLoad(tex_in, ivec2(uv.x, k + step)).xy;
    }
    
    vec2 res;
    if (idx % group_size < step) {
        res = h_top + complex_mul(w, h_bottom);
    } else {
        res = h_top - complex_mul(w, h_bottom);
    }
    
    imageStore(tex_out, uv, vec4(res, 0.0, 1.0));
}
