#version 450

// Phillips Spectrum Initializer
// Generates h0(k) and h0_conj(-k) for FFT Ocean

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform writeonly image2D h0_texture;

layout(push_constant) uniform Params {
    int resolution;
    float sea_size;
    float wind_strength;
    vec2 wind_dir;
    float time;
} params;

const float PI = 3.14159265359;
const float G = 9.81;

// Simple hash for randomness
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec2 gauss_rand(vec2 uv) {
    float r1 = max(hash(uv + vec2(0.123, 0.456)), 0.0001);
    float r2 = hash(uv + vec2(0.789, 0.012));
    float m = sqrt(-2.0 * log(r1));
    return vec2(m * cos(2.0 * PI * r2), m * sin(2.0 * PI * r2));
}

float phillips(vec2 k, float wind_speed, vec2 wind_dir_norm) {
    float k_len = length(k);
    if (k_len < 0.0001) return 0.0;
    
    float k2 = k_len * k_len;
    float k4 = k2 * k2;
    
    float L = (wind_speed * wind_speed) / G;
    float L2 = L * L;
    
    float k_dot_w = dot(normalize(k), wind_dir_norm);
    float k_dot_w2 = k_dot_w * k_dot_w;
    
    float ph = exp(-1.0 / (k2 * L2)) / k4 * k_dot_w2;
    
    // Damp waves moving against the wind
    if (k_dot_w < 0.0) ph *= 0.1;
    
    return ph;
}

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    if (uv.x >= params.resolution || uv.y >= params.resolution) return;
    
    vec2 k = (vec2(uv) - float(params.resolution) * 0.5) * (2.0 * PI / params.sea_size);
    
    float p = phillips(k, params.wind_strength, normalize(params.wind_dir));
    float p_inv = phillips(-k, params.wind_strength, normalize(params.wind_dir));
    
    vec2 noise = gauss_rand(vec2(uv) / float(params.resolution));
    
    float h0_re = noise.x * sqrt(p * 0.5);
    float h0_im = noise.y * sqrt(p * 0.5);
    
    float h0_inv_re = noise.x * sqrt(p_inv * 0.5);
    float h0_inv_im = -noise.y * sqrt(p_inv * 0.5);
    
    imageStore(h0_texture, uv, vec4(h0_re, h0_im, h0_inv_re, h0_inv_im));
}
