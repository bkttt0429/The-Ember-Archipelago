#version 450

// FFT Ocean Spectrum Time Evolution
// Calculates h(k, t) from h0(k)

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D h0_texture;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D ht_texture;

layout(push_constant) uniform Params {
    int resolution;
    float sea_size;
    float time;
} params;

const float G = 9.81;
const float PI = 3.14159265359;

vec2 complex_mul(vec2 a, vec2 b) {
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    if (uv.x >= params.resolution || uv.y >= params.resolution) return;
    
    vec2 k = (vec2(uv) - float(params.resolution) * 0.5) * (2.0 * PI / params.sea_size);
    float k_len = length(k);
    
    // Dispersion relation: w^2 = g*k
    float w = sqrt(G * k_len);
    
    vec4 h0_data = imageLoad(h0_texture, uv);
    vec2 h0 = h0_data.xy;
    vec2 h0_conj = h0_data.zw;
    
    float wt = w * params.time;
    float cos_wt = cos(wt);
    float sin_wt = sin(wt);
    
    // exp(i*w*t) = cos(wt) + i*sin(wt)
    // exp(-i*w*t) = cos(wt) - i*sin(wt)
    vec2 exp_iwt = vec2(cos_wt, sin_wt);
    vec2 exp_miwt = vec2(cos_wt, -sin_wt);
    
    vec2 h_k_t = complex_mul(h0, exp_iwt) + complex_mul(h0_conj, exp_miwt);
    
    // Output: R = real, G = imag, B = 0, A = 1
    imageStore(ht_texture, uv, vec4(h_k_t, 0.0, 1.0));
}
