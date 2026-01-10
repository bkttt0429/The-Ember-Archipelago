#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(rgba32f, binding = 1) uniform image2D output_image;
layout(rgba32f, binding = 2) uniform image2D input_image;

layout(push_constant) uniform PushConstants {
    int pass_mode; // 0 = Update Spectrum, 1 = Horizontal, 2 = Vertical
} pc;

layout(set = 0, binding = 0) uniform OceanParams {
    float time;
    float choppiness;
    float wind_speed;
    float wind_dir;
    int texture_size;
    float frequency_scale;
} params;

shared vec2 sm_data[256];

const float PI = 3.14159265359;

// Manual 8-bit reversal for 256-size FFT
uint reverse8(uint x) {
    x = ((x & 0x55u) << 1u) | ((x & 0xAAu) >> 1u);
    x = ((x & 0x33u) << 2u) | ((x & 0xCCu) >> 2u);
    x = ((x & 0x0Fu) << 4u) | ((x & 0xF0u) >> 4u);
    return x;
}

vec2 cmul(vec2 a, vec2 b) {
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main() {
    uint tid = gl_LocalInvocationID.x;
    uint gid = gl_WorkGroupID.y;
    
    // ------------------------------------------------------------------
    // PASS 0: UPDATE SPECTRUM h(k, t)
    // ------------------------------------------------------------------
    if (pc.pass_mode == 0) {
        ivec2 pos = ivec2(int(tid), int(gid));
        vec4 h0_val = imageLoad(input_image, pos);
        
        // k vector
        float kx = float(int(tid) <= 128 ? int(tid) : int(tid) - 256);
        float kz = float(int(gid) <= 128 ? int(gid) : int(gid) - 256);
        float k_len = sqrt(kx * kx + kz * kz);
        
        if (k_len < 0.0001) {
            imageStore(output_image, pos, vec4(0.0));
            return;
        }

        // Dispersion relation: w^2 = g * k
        float w = sqrt(9.81 * k_len) * params.frequency_scale;
        
        float t = params.time;
        float cos_wt = cos(w * t);
        float sin_wt = sin(w * t);
        
        // --- AAA STANDARD: PHILLIPS SPECTRUM IMPLEMENTATION ---
        
        // 1. Wind Direction Vector
        float wind_angle = params.wind_dir; // Assumes radians
        vec2 w_dir = vec2(cos(wind_angle), sin(wind_angle));
        
        // 2. Wave Vector k
        // Avoid division by zero at k=0
        if (k_len < 0.0001) k_len = 0.0001;
        vec2 k_vec = vec2(kx, kz);
        vec2 k_dir = normalize(k_vec);
        
        // 3. Phillips Spectrum Parameters
        float L = (params.wind_speed * params.wind_speed) / 9.81; // Largest possible wave for wind speed
        float L2 = L * L;
        
        float k2 = k_len * k_len;
        float k4 = k2 * k2;
        
        // 4. Directional Factor |k . w|^2
        float dot_k_w = dot(k_dir, w_dir);
        // Suppress waves moving against wind (optional, often looks better for steady ocean)
        // dot_k_w = max(dot_k_w, 0.0); 
        float dir_factor = dot_k_w * dot_k_w;
        
        // 5. Phillips Amplitude P(k)
        // P(k) = A * (exp(-1/(kL)^2) / k^4) * |k.w|^2
        float A = 20000.0; // Alignment constant matching previous magnitude
        float phillips = A * (exp(-1.0 / (k2 * L2)) / k4) * dir_factor;
        
        // Small waves damping (Suppress waves smaller than the grid spacing)
        // L2 * 0.001 is a heuristic; adjusting to be based on grid resolution is better.
        // Assuming params.texture_size matches the grid roughly.
        // l2 damping factor removes high-frequency noise (The "Small Triangles")
        float l2 = L2 * 0.0001; 
        phillips *= exp(-k2 * l2); 
        
        // 6. Final Amplitude (Sqrt because P(k) is variance)
        float amp = sqrt(phillips);
        
        // h(t) = h0 * exp(iwt)
        // h0_val is our Gaussian Noise (xi_r, xi_i)
        // We modulate the noise by the spectrum amplitude
        vec2 h0 = h0_val.xy * amp;
        
        vec2 h_t = vec2(
            h0.x * cos_wt - h0.y * sin_wt,
            h0.x * sin_wt + h0.y * cos_wt
        );
        
        imageStore(output_image, pos, vec4(h_t, 0.0, 1.0));
        return;
    }

    // 1. DATA LOAD (WITH BIT REVERSAL)
    uint rev_tid = reverse8(tid);
    
    ivec2 load_pos;
    if (pc.pass_mode == 1) {
        load_pos = ivec2(int(rev_tid), int(gid));
    } else {
        load_pos = ivec2(int(gid), int(rev_tid));
    }
    
    vec4 val = imageLoad(input_image, load_pos);
    sm_data[tid] = val.xy;
    
    // 2. FFT TRANSFORM
    for (int s = 1; s <= 8; s++) {
        int m = 1 << s;
        int m2 = m >> 1;
        
        barrier(); // Ensure all sm_data entries are available from previous stage
        
        int offset = int(tid) % m;
        bool is_lower = (offset >= m2);
        int pair_idx = is_lower ? (int(tid) - m2) : (int(tid) + m2);
        
        int k = offset % m2;
        float angle = 2.0 * PI * float(k) / float(m);
        vec2 w = vec2(cos(angle), sin(angle));
        
        vec2 my_val = sm_data[tid];
        vec2 pair_val = sm_data[pair_idx];
        
        vec2 u = is_lower ? pair_val : my_val;
        vec2 t = is_lower ? my_val : pair_val;
        
        vec2 wt = cmul(w, t);
        vec2 result = is_lower ? (u - wt) : (u + wt);
        
        barrier(); // Wait for all reads before overwriting
        sm_data[tid] = result;
    }
    
    barrier();
    
    // 3. STORE RESULT
    float norm = 1.0 / float(params.texture_size);
    vec2 normalized_val = sm_data[tid] * norm;
    
    ivec2 store_pos;
    vec4 final_color;
    
    if (pc.pass_mode == 1) {
        store_pos = ivec2(int(tid), int(gid));
        final_color = vec4(normalized_val, 0.0, 1.0);
    } else {
        store_pos = ivec2(int(gid), int(tid));
        float h = normalized_val.x;
        final_color = vec4(h, 0.0, 0.0, 1.0); // Store height in R channel
    }
    
    imageStore(output_image, store_pos, final_color);
}
