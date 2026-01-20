#ifndef WATER_WAVES_INC
#define WATER_WAVES_INC

vec3 gerstner_wave(vec3 pos, float time, vec2 dir, float length, float steepness, float speed, inout vec3 tangent, inout vec3 binormal) {
    float k = 2.0 * PI / length;
    float c = sqrt(9.81 / k) * speed;
    vec2 d = normalize(dir);
    float f = k * (dot(d, pos.xz) - c * time);
    float a = steepness / k;

    tangent += vec3(
        -d.x * d.x * (steepness * sin(f)),
        d.x * (steepness * cos(f)),
        -d.x * d.y * (steepness * sin(f))
    );
    binormal += vec3(
        -d.x * d.y * (steepness * sin(f)),
        d.y * (steepness * cos(f)),
        -d.y * d.y * (steepness * sin(f))
    );

    return vec3(
        d.x * (a * cos(f)),
        a * sin(f),
        d.y * (a * cos(f))
    );
}

vec3 get_waves_displacement(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, inout vec3 tangent, inout vec3 binormal) {
    vec3 disp = vec3(0.0);
    
    // 8-Layer Wave Data (Match CPU logic for sync)
    float wave_data[32] = float[](
        wave_length, wave_steepness, 1.0, 0.0,
        wave_length * 1.3, wave_steepness * 0.7, 0.8, 1.1,
        wave_length * 0.6, wave_steepness * 0.9, 1.5, 2.4,
        wave_length * 0.3, wave_steepness * 1.2, 2.1, -0.6,
        wave_length * 2.1, wave_steepness * 0.4, 0.6, 4.3,
        wave_length * 0.8, wave_steepness * 0.8, 1.3, -1.2,
        wave_length * 0.45, wave_steepness * 1.0, 1.9, 5.2,
        wave_length * 1.7, wave_steepness * 0.3, 0.5, 0.7
    );

    float base_angle = atan(wind_dir.y, wind_dir.x);

    for (int i = 0; i < 8; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx];
        float w_steep = wave_data[idx+1] * wind_strength;
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * wave_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        disp += gerstner_wave(pos, t, d, w_len, w_steep, w_speed, tangent, binormal);
    }
    
    // Extra micro-noise
    float noise = sin(pos.x * 2.0 + t) * cos(pos.z * 2.0 - t * 0.5) * 0.2;
    disp.y += noise * wind_strength * wave_chaos;
    
    return disp;
}

#endif
