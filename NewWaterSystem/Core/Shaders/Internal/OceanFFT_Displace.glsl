#version 450

// FFT Ocean Displacement Generator
// Converts FFT output (complex values) to displacement and normal maps

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D fft_texture;
layout(set = 0, binding = 1, rgba32f) uniform writeonly image2D displacement_texture;

layout(push_constant) uniform Params {
    int resolution;
    float sea_size;
} params;

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    if (uv.x >= params.resolution || uv.y >= params.resolution) return;
    
    // Current pixel height
    float h = imageLoad(fft_texture, uv).x;
    h /= float(params.resolution * params.resolution);
    if (((uv.x + uv.y) % 2) != 0) h = -h;

    // Neighbor pixels for Gradient (Finite Difference)
    ivec2 uv_r = (uv + ivec2(1, 0)) % params.resolution;
    ivec2 uv_u = (uv + ivec2(0, 1)) % params.resolution;
    
    float h_r = imageLoad(fft_texture, uv_r).x;
    h_r /= float(params.resolution * params.resolution);
    if (((uv_r.x + uv_r.y) % 2) != 0) h_r = -h_r;
    
    float h_u = imageLoad(fft_texture, uv_u).x;
    h_u /= float(params.resolution * params.resolution);
    if (((uv_u.x + uv_u.y) % 2) != 0) h_u = -h_u;
    
    float texel_size = params.sea_size / float(params.resolution);
    float dhdx = (h_r - h) / texel_size;
    float dhdy = (h_u - h) / texel_size;
    
    // RG = Gradient (Slope), B = Displacement Height
    imageStore(displacement_texture, uv, vec4(dhdx, dhdy, h, 1.0));
}
