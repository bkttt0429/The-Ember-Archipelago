shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage, depth_draw_always;

// Varying for Jacobian (Foam)
varying float v_jacobian;

uniform float peak_sharpness : hint_range(0.1, 4.0) = 1.0;
uniform float sss_strength : hint_range(0.0, 5.0) = 0.5;
uniform vec4 sss_color : source_color = vec4(0.0, 0.6, 0.5, 1.0);

// Inline WaterWaves.gdshaderinc logic for self-containment
// Redundant PI removed

uniform float horizontal_displacement_scale : hint_range(0.0, 1.0) = 0.8;
uniform float lod_scale = 1.0;  // Moved early: needed by get_layer_lod_fade()

vec3 gerstner_wave(vec3 pos, float time, vec2 dir, float length, float steepness, float speed, inout vec3 tangent, inout vec3 binormal, inout float jacobian_det) {
    float k = 2.0 * PI / length;
    float c = sqrt(9.81 / k) * speed;
    vec2 d = normalize(dir);
    float f = k * (dot(d, pos.xz) - c * time);
    float a = steepness / k;

    // Nonlinear peak contraction (Trochoidal approximation)
    float h = sin(f);
    float dh_df = cos(f);
    if (peak_sharpness != 1.0) {
        float s = h * 0.5 + 0.5;
        // ✅ Decoupled: Visual height uses pow() for sharpness
        h = pow(max(s, 0.001), peak_sharpness) * 2.0 - 1.0;
        
        // ✅ Tangent: Always use smooth derivative (ignore peak_sharpness pow)
        // This prevents "explosions" where the normal flips instantly between vertices
        dh_df = cos(f); 
    }

    tangent += vec3(
        -d.x * d.x * (steepness * sin(f)),
        d.x * (steepness * dh_df),
        -d.x * d.y * (steepness * sin(f))
    );
    binormal += vec3(
        -d.x * d.y * (steepness * sin(f)),
        d.y * (steepness * dh_df),
        -d.y * d.y * (steepness * sin(f))
    );
    
    // Jacobian Determinant contribution: J *= (1 - k * A * cos(f))
    // k * A = steepness (approximately)
    // This value represents the determinant of the transformation. < 0 means folding.
    jacobian_det *= (1.0 - steepness * cos(f));

    return vec3(
        d.x * (a * cos(f)) * horizontal_displacement_scale,
        a * h,
        d.y * (a * cos(f)) * horizontal_displacement_scale
    );
}

// LOD layer fade: returns 0.0-1.0 energy multiplier for each wave layer based on distance
// Layers 0-3 = low freq (always full), Layers 4-5 = mid (fade 50-120m), Layers 6-7 = high (fade 25-70m)
float get_layer_lod_fade(int layer_index, float cam_dist) {
    if (layer_index < 4) return 1.0;  // Low-frequency layers always active
    if (layer_index < 6) {
        // Mid-frequency: fade out between 50-120m
        return 1.0 - smoothstep(50.0 * lod_scale, 120.0 * lod_scale, cam_dist);
    }
    // High-frequency: fade out between 25-70m
    return 1.0 - smoothstep(25.0 * lod_scale, 70.0 * lod_scale, cam_dist);
}

vec3 get_waves_displacement(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, inout vec3 tangent, inout vec3 binormal, int iterations, inout float jacobian_det, float cam_dist) {
    vec3 disp = vec3(0.0);
    
    // 8-Layer Wave Data (Multipliers)
    float wave_data[32] = float[](
        1.0, 1.0, 1.0, 0.0,
        1.3, 0.7, 0.8, 1.1,
        0.6, 0.9, 1.5, 2.4,
        0.3, 1.2, 2.1, -0.6,
        2.1, 0.4, 0.6, 4.3,
        0.8, 0.8, 1.3, -1.2,
        0.45, 1.0, 1.9, 5.2,
        1.7, 0.3, 0.5, 0.7
    );

    // ✅ 修正：先計算總能量，再套用能量守恆縮放
    float total_relative_steepness = 0.0;
    for (int i = 0; i < 8; i++) total_relative_steepness += wave_data[i * 4 + 1];
    
    // ✅ 能量守恆：用 sqrt 而非直接乘法
    float global_energy_scale = sqrt(wave_steepness);
    
    float steepness_norm = 1.0;
    if (global_energy_scale * total_relative_steepness * wind_strength > 0.75) {
        steepness_norm = 0.75 / (global_energy_scale * total_relative_steepness * wind_strength);
    }

    float base_angle = atan(wind_dir.y, wind_dir.x);
    
    // ✅ Safety Clamp for Chaos (Prevent Moiré patterns)
    float safe_chaos = min(wave_chaos, 0.3);

    for (int i = 0; i < iterations; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx] * wave_length;
        
        // ✅ LOD fade: smoothly reduce high-freq layer energy at distance
        float lod_fade = get_layer_lod_fade(i, cam_dist);
        float w_steep = wave_data[idx+1] * global_energy_scale * wind_strength * steepness_norm * lod_fade;
        
        // Skip fully faded layers
        if (lod_fade < 0.001) continue;
        
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * safe_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        disp += gerstner_wave(pos, t, d, w_len, w_steep, w_speed, tangent, binormal, jacobian_det);
    }
    
    // Fix: Ensure noise is also suppressed when wind is 0
    if (wind_strength > 0.001) {
        float noise = sin(pos.x * 2.0 + t) * cos(pos.z * 2.0 - t * 0.5) * 0.2;
        disp.y += noise * wind_strength * safe_chaos;
    }
    
    return disp;
}

vec3 get_gerstner_normal_analytical(vec3 pos, float t, float wind_strength, vec2 wind_dir, float wave_length, float wave_steepness, float wave_chaos, float cam_dist) {
    vec3 normal = vec3(0.0, 1.0, 0.0);
    
    float wave_data[32] = float[](
        1.0, 1.0, 1.0, 0.0,
        1.3, 0.7, 0.8, 1.1,
        0.6, 0.9, 1.5, 2.4,
        0.3, 1.2, 2.1, -0.6,
        2.1, 0.4, 0.6, 4.3,
        0.8, 0.8, 1.3, -1.2,
        0.45, 1.0, 1.9, 5.2,
        1.7, 0.3, 0.5, 0.7
    );

    float total_relative_steepness = 0.0;
    for (int i = 0; i < 8; i++) total_relative_steepness += wave_data[i * 4 + 1];
    
    // ✅ 能量守恆縮放
    float global_energy_scale = sqrt(wave_steepness);
    
    float steepness_norm = 1.0;
    if (global_energy_scale * total_relative_steepness * wind_strength > 0.75) {
        steepness_norm = 0.75 / (global_energy_scale * total_relative_steepness * wind_strength);
    }

    float base_angle = atan(wind_dir.y, wind_dir.x);
    
    // ✅ Safety Clamp for Chaos (Analytical)
    float safe_chaos = min(wave_chaos, 0.3);

    for (int i = 0; i < 8; i++) {
        int idx = i * 4;
        float w_len = wave_data[idx] * wave_length;
        
        // ✅ LOD fade: smoothly reduce high-freq layer contribution at distance
        float lod_fade = get_layer_lod_fade(i, cam_dist);
        float w_steep = wave_data[idx+1] * global_energy_scale * wind_strength * steepness_norm * lod_fade;
        
        // Skip fully faded layers for performance
        if (lod_fade < 0.001) continue;
        
        float w_speed = wave_data[idx+2];
        float w_angle = base_angle + wave_data[idx+3] * safe_chaos;
        
        vec2 d = vec2(cos(w_angle), sin(w_angle));
        float k = 2.0 * PI / w_len;
        float c = sqrt(9.81 / k) * w_speed;
        float f = k * (dot(d, pos.xz) - c * t);
        
        // Derivative of height w.r.t. phase (always smooth cos)
        float dh_df = cos(f);
        
        // ✅ Standard Gerstner Analytic Normal with LOD fade applied
        normal.x -= d.x * w_steep * dh_df;
        normal.y -= w_steep * dh_df;
        normal.z -= d.y * w_steep * dh_df;
    }
    
    // ✅ Standard normalization
    return normalize(normal);
}
// End of inlined logic

uniform sampler2D swe_texture : hint_default_black, filter_linear, repeat_disable; 
uniform sampler2D fft_texture : hint_default_black, filter_linear, repeat_enable;
uniform sampler2D weather_influence : hint_default_black, filter_linear, repeat_disable;
uniform float swe_strength = 2.0;
uniform float swe_fill_mode = 0.0;       // ★ 0=normal ocean, 1=fill mode (discard where no SWE)
uniform float swe_fill_threshold = 0.02; // ★ minimum swe_h to be visible in fill mode
uniform vec2 sea_size = vec2(40.0, 40.0);
uniform vec3 manager_world_pos = vec3(0.0);
uniform vec2 swe_world_origin = vec2(0.0); // ★ Toroidal SWE Origin
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.5);
uniform float wave_steepness = 0.2;
uniform float wave_length = 10.0;
uniform float wave_chaos = 0.5; 
uniform float wave_height_multiplier = 1.0;  // Direct height control (1.0 = normal) 

uniform vec4 color_deep : source_color = vec4(0.05, 0.18, 0.4, 1.0); 
uniform vec4 color_shallow : source_color = vec4(0.0, 0.73, 0.99, 1.0);  
uniform vec4 color_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float absorption_coeff = 0.3;
uniform float refraction_strength = 0.05;
uniform float dispersion_strength : hint_range(0.0, 0.05) = 0.008;  // ★ 色散強度 (HPWater style)

// ★ HPWater-Style Volumetric Absorption
uniform vec3 absorption_rgb = vec3(0.46, 0.09, 0.03);           // 每波長吸收係數 (紅光最容易被吸收)
uniform vec3 scattering_rgb = vec3(0.02, 0.07, 0.12);           // 每波長散射係數 (藍光散射最多)
uniform float scattering_phase_g : hint_range(0.0, 0.99) = 0.75; // Mie 前向散射不對稱 (0=各向同性, ~1=極前向)
uniform float refraction_blur_density : hint_range(0.0, 3.0) = 0.6; // 深水折射模糊強度

uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.25;
uniform float specular : hint_range(0.0, 1.0) = 0.6;
uniform bool storm_mode = false;
uniform float fresnel_strength : hint_range(0.0, 2.0) = 0.5;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.4;
uniform float foam_shore_spread = 0.5;
uniform float foam_shore_strength = 1.0;
uniform float foam_crest_spread = 0.2;
uniform float foam_crest_strength = 1.5;
uniform float foam_wake_strength = 1.5;
uniform float foam_jacobian_bias : hint_range(0.0, 1.0) = 0.3;

// Caustics
uniform sampler2D caustics_texture : hint_default_black, repeat_enable;
uniform float caustics_strength : hint_range(0.0, 5.0) = 1.0;
uniform float caustics_scale = 0.5;
uniform float caustics_speed = 0.1;

// ★ 氣候/光照系統 (Climate & Lighting)
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 sky_color : source_color = vec3(0.5, 0.7, 1.0);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.8, 0.9);
uniform float sun_intensity : hint_range(0.0, 3.0) = 1.0;
uniform vec3 sun_direction = vec3(0.3, -0.8, 0.5);
// ★ 深度分層顏色 (Depth Zones)
uniform vec4 color_shore : source_color = vec4(0.0, 0.85, 0.85, 1.0);  // 涺灘青綠
uniform vec4 color_mid : source_color = vec4(0.05, 0.4, 0.7, 1.0);     // 中深藍
uniform float depth_zone_mid : hint_range(0.5, 5.0) = 1.5;  // 淺→中過渡深度
uniform float depth_zone_deep : hint_range(2.0, 15.0) = 5.0; // 中→深過渡深度

uniform bool debug_show_markers = false;
uniform bool show_wireframe = false;

uniform sampler2D foam_noise : repeat_enable, hint_default_white; 
uniform sampler2D foam_detail : repeat_enable, hint_default_white;
uniform sampler2D foam_sparkle : repeat_enable, hint_default_white;
uniform sampler2D foam_normal : hint_normal, repeat_enable;
uniform sampler2D normal_map1 : hint_normal, repeat_enable;
uniform sampler2D normal_map2 : hint_normal, repeat_enable;
uniform sampler2D envelope_tex : hint_default_white, filter_linear, repeat_disable;

uniform float normal_scale : hint_range(0.0, 2.0) = 0.7;
uniform float normal_speed : hint_range(0.0, 0.5) = 0.1;
uniform vec4 rogue_wave_data = vec4(0.0, 0.0, 0.0, 1.0); // x,y: pos, z: height, w: width


// === Volumetric & Particle Foam ===
uniform sampler2D foam_particle_texture : hint_default_black;
uniform sampler2D spray_particle_texture : hint_default_black;
uniform float water_transparency : hint_range(0.0, 1.0) = 0.8;
uniform vec3 water_scatter_color : source_color = vec3(0.1, 0.6, 0.8);
uniform float physics_time = 0.0;
uniform float render_alpha = 0.0;

uniform float fft_scale = 1.0;
uniform float normal_tile = 10.0;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture;
uniform sampler2D flow_map : hint_default_black, filter_linear, repeat_enable;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;
uniform float flow_strength : hint_range(0.0, 1.0) = 0.5;

// === Analytic Player Interaction Ripples ===
uniform int ar_count = 0;
// x,y: world_pos.x,z; z: start_time; w: intensity
uniform vec4 ar_data[64];
uniform float ar_lifetime = 3.0;
uniform float ar_speed = 2.0;
uniform float ar_freq = 15.0;
uniform float ar_decay = 2.0;
uniform float ripple_normal_strength = 2.0;
uniform float ripple_height_scale = 0.5;

// ★ 局部高解析度漣漪（256×256 ping-pong 波動方程）
uniform sampler2D local_ripple_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec2 local_ripple_center = vec2(0.0);  // 世界 XZ 中心
uniform float local_ripple_size = 10.0;         // 覆蓋範圍 (m)
uniform float local_ripple_strength = 1.5;      // 法線強度

// === Kelvin Wake System ===
// 凱爾文尾流：物體移動時在水面產生的 V 型色散波
// wake_sources: xy=世界位置, zw=速度方向(xz)
// wake_params: x=速度大小, y=start_time, z=strength, w=船體尺度
uniform int kelvin_wake_count = 0;
uniform vec4 kelvin_wake_pos[8];    // xy=當前位置, zw=前一位置
uniform vec4 kelvin_wake_vel[8];    // xy=速度xz, z=speed, w=strength
const float GRAVITY = 9.81;


uniform float edge_scale : hint_range(0.0, 5.0) = 0.5;
uniform float far_fade_start : hint_range(0.0, 500.0) = 150.0;
uniform float far_fade_max : hint_range(0.0, 1000.0) = 300.0;
// === Debug Normal Visualization ===
// 0 = Off, 1 = Final Normal RGB, 2 = Analytical Normal Only, 3 = Vertex Normal Only, 4 = Difference Heatmap
uniform int debug_normal_mode : hint_range(0, 5) = 0;



// ... (Existing uniforms)
varying vec2 v_swe_uv;
varying vec3 v_wave_normal;
varying vec3 v_world_pos;
varying float v_edge_damp;
varying float v_cam_dist;  // Camera distance for fragment LOD
varying float v_swe_h;     // ★ SWE height for fill-mode discard matching

// === 新增 Uniforms for Breaking Waves ===
uniform int breaking_wave_count = 0;
uniform vec4 breaking_wave_data[3];  // xyz=pos+height, w=width
uniform vec4 breaking_wave_params[3];  // x=curl, y=base_t, z=dir_x, w=dir_y
// envelope_tex already defined at line 236

// === Kelvin Wake 計算（19.47° V 型尾流）===
float kelvin_wake_height(vec2 world_xz) {
    float total_h = 0.0;
    for (int w = 0; w < kelvin_wake_count; w++) {
        vec2 boat_pos = kelvin_wake_pos[w].xy;
        vec2 vel_dir = kelvin_wake_vel[w].xy;
        float speed = kelvin_wake_vel[w].z;
        float strength = kelvin_wake_vel[w].w;
        
        if (speed < 0.5) continue;
        
        vec2 move_dir = normalize(vel_dir);
        vec2 to_pixel = world_xz - boat_pos;
        
        // 轉換到船體座標系
        // x_along = 沿運動方向（正=前方，負=後方）
        // x_across = 垂直運動方向
        float x_along = dot(to_pixel, move_dir);
        float x_across = abs(dot(to_pixel, vec2(-move_dir.y, move_dir.x)));
        
        // 只有後方才有尾流
        if (x_along > -0.5) continue;
        float behind = -x_along; // 後方距離（正值）
        
        // ★ 尾流長度限制：根據速度動態調整最大長度（速度越快尾流越長但有上限）
        float max_wake_len = clamp(speed * 1.5, 4.0, 12.0);
        if (behind > max_wake_len) continue;
        
        // ★ 尾部漸隱：尾流末端平滑消失（不是硬截斷）
        float length_fade = smoothstep(max_wake_len, max_wake_len * 0.5, behind);
        
        // ★ 凱爾文角 = arcsin(1/3) ≈ 19.47°
        // V 型包絡：x_across / behind ≈ tan(19.47°) ≈ 0.354
        float kelvin_ratio = x_across / max(behind, 0.1);
        float kelvin_envelope = smoothstep(0.42, 0.28, kelvin_ratio); // V 型邊界
        if (kelvin_envelope < 0.01) continue;
        
        // ★ 中心線平滑（消除暗線偽影）
        float center_fade = smoothstep(0.0, 0.08, kelvin_ratio);
        
        // 距離衰減（沿後方距離衰減）
        float dist_decay = 1.0 / max(sqrt(behind), 1.0);
        
        // ★ 橫波（Transverse waves）— 垂直於運動方向的波紋
        float transverse_k = 6.283 * speed / max(GRAVITY, 0.1);
        float transverse = sin(behind * transverse_k * 0.3) * 0.7;
        
        // ★ 散波（Divergent waves）— 沿 V 型臂的波紋
        float dist = length(to_pixel);
        float divergent_phase = dist * transverse_k * 0.5 - behind * transverse_k * 0.15;
        float divergent = sin(divergent_phase) * 0.5;
        
        // 合成：V 邊界附近以散波為主，中間以橫波為主
        float wave = mix(transverse, divergent, smoothstep(0.15, 0.35, kelvin_ratio));
        
        total_h += wave * strength * dist_decay * kelvin_envelope * center_fade * length_fade * 0.4;
    }
    return clamp(total_h, -0.8, 0.8);
}

vec3 kelvin_wake_normal(vec2 world_xz) {
    float eps = 0.4;
    float h_c = kelvin_wake_height(world_xz);
    float h_r = kelvin_wake_height(world_xz + vec2(eps, 0.0));
    float h_u = kelvin_wake_height(world_xz + vec2(0.0, eps));
    return normalize(vec3((h_c - h_r) / eps, 1.0, (h_c - h_u) / eps));
}


// 1D Envelope Sampling for Rogue Wave
float sample_envelope(float dist, float width) {
    float u = clamp((dist / width) * 0.5 + 0.5, 0.0, 1.0);
    float val = texture(envelope_tex, vec2(u, 0.0)).r;
    
    // ✅ Procedural Safety: Force fade to 0.0 at the edges 
    // This handles texture sampling artifacts or non-zero edge pixels
    float dist_norm = abs(dist / width);
    float window = smoothstep(1.0, 0.9, dist_norm);
    
    return val * window;
}

float sample_breaking_spray_mist(vec2 world_xz, out float spray_core) {
	float mist = 0.0;
	spray_core = 0.0;
	for (int i = 0; i < breaking_wave_count; i++) {
		vec2 center = vec2(breaking_wave_data[i].x, breaking_wave_data[i].z);
		float height = breaking_wave_data[i].y;
		float width = max(breaking_wave_data[i].w, 0.001);
		float curl = max(breaking_wave_params[i].x, 0.0);
		float base_t = clamp(breaking_wave_params[i].y, 0.0, 1.0);
		vec2 dir = breaking_wave_params[i].zw;
		if (length(dir) < 0.001) {
			dir = normalize(wind_dir);
		} else {
			dir = normalize(dir);
		}
		vec2 tangent_dir = vec2(-dir.y, dir.x);
		vec2 to_wave = world_xz - center;
		float along = dot(to_wave, dir);
		float across = dot(to_wave, tangent_dir);

		float crest_band = exp(-pow(across / max(width * 0.28, 0.001), 2.0));
		float lip_zone = smoothstep(-width * 0.15, width * 0.08, along) * (1.0 - smoothstep(width * 0.2, width * 0.75, along));
		float fall_zone = smoothstep(0.42, 0.92, base_t);
		float height_gain = clamp(height / 6.0, 0.35, 2.0);
		float wave_mist = crest_band * lip_zone * fall_zone * max(curl, 0.2) * height_gain;
		mist += wave_mist;
		spray_core = max(spray_core, crest_band * smoothstep(-width * 0.05, width * 0.12, along) * fall_zone);
	}
	return clamp(mist, 0.0, 1.0);
}

vec3 get_rogue_wave_displacement(vec3 pos, float t, vec3 tangent_in, vec3 binormal_in, inout vec3 tangent, inout vec3 binormal) {
    if (rogue_wave_data.z <= 0.01) return vec3(0.0);
    
    vec2 center = rogue_wave_data.xy;
    float height = rogue_wave_data.z;
    float width = rogue_wave_data.w;
    
    // Project position onto wave direction (assumed simplistic directional for now, or radial?)
    // Making it directional based on wind to match "rogue wave" usually following sea state
    vec2 wave_dir = normalize(wind_dir); 
    
    // Calculate distance along the wave direction relative to the center
    // This makes it a "wall of water" or "long crest"
    float dist_long = dot(pos.xz - center, wave_dir);
    
    // Check lateral distance to limit width? Or infinite wall? Let's limit it.
    float dist_lat = dot(pos.xz - center, vec2(-wave_dir.y, wave_dir.x));
    
    // Combine for a local shape
    if (abs(dist_long) > width || abs(dist_lat) > width * 2.0) return vec3(0.0);
    
    float envelope = sample_envelope(dist_long, width);
    // Lateral falloff
    envelope *= smoothstep(width * 2.0, width, abs(dist_lat));
    
    float disp_y = envelope * height;
    
    // Analytical Normal modification (Corrected gradient calculation)
    // d(Height)/d(Long) for tangent
    
    // ========== 修正：使用更小的 delta 和安全限制 ==========
    float delta = width * 0.01; // ✅ 改為寬度的 1%
    float env_d = sample_envelope(dist_long + delta, width);
    float slope = (env_d - envelope) / delta * height;
    
    // ✅ 限制斜率，防止垂直或倒置
    slope = clamp(slope, -2.0, 2.0); // 限制在 ±2 的安全範圍
    
    // ✅ 平滑的法線，而非突變
    vec3 wave_n = normalize(vec3(-slope * wave_dir.x, 1.0, -slope * wave_dir.y));
    
    // ✅ 只在波峰附近修改切線（避免波谷產生扭曲）
    if (envelope > 0.3) {
        tangent += wave_n * envelope * 0.3;
    }
    // ======================================================
    
    return vec3(0.0, disp_y, 0.0);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_pos;
	
	// ★ Toroidal SWE UV Mapping
	v_swe_uv = (world_pos.xz - swe_world_origin) / sea_size + 0.5;
	if (swe_fill_mode < 0.5) {
		v_swe_uv = fract(v_swe_uv); // Automatically wrap to [0, 1] continuously
	}
	
	float cam_dist = length(world_pos - manager_world_pos); // Or CAMERA_POSITION_WORLD if available
	
	// === 新增：破碎波浪捲曲 ===
	for (int i = 0; i < breaking_wave_count; i++) {
		vec3 wave_center = breaking_wave_data[i].xyz;
		float wave_width = breaking_wave_data[i].w; // Ensure wave_width is float
		float curl_strength = breaking_wave_params[i].x;
		float break_point = breaking_wave_params[i].y;
		
		// 計算到波浪中心的距離
		vec2 to_wave = world_pos.xz - wave_center.xz;
		float dist_along = dot(to_wave, normalize(wind_dir));  // 沿波浪方向
		float dist_across = length(to_wave - dist_along * normalize(wind_dir));
		
		// 只影響波浪寬度範圍內
		if (abs(dist_across) > wave_width) continue;
		
		// 橫向衰減
		float lateral_fade = smoothstep(wave_width, wave_width * 0.5, abs(dist_across));
		
		// 縱向形態（Sech 包絡）
		float u = clamp(dist_along / wave_width * 0.5 + 0.5, 0.0, 1.0);
		float envelope = texture(envelope_tex, vec2(u, 0.0)).r;
		
		// === 關鍵：水平位移創造 "捲曲" ===
		// 在波峰前方（u > break_point）產生向前的位移
		float curl_zone = smoothstep(break_point - 0.2, break_point + 0.1, u);
		
		// 捲曲方向：沿著波浪前進方向，但向下彎曲
		vec3 curl_offset = vec3(
			normalize(wind_dir).x * curl_zone * curl_strength * 3.0,
			-curl_zone * curl_strength * 2.0,  // 向下彎曲
			normalize(wind_dir).y * curl_zone * curl_strength * 3.0
		);
		
		// 應用捲曲（疊加到現有位移）
		// FIX: Use += to accumulate
		VERTEX += curl_offset * envelope * lateral_fade * wave_center.y; 
	}

	// Sample SWE for displacement — 3×3 平滑避免網格偽影
	vec2 swe_ts = 1.0 / vec2(textureSize(swe_texture, 0));
	vec2 swe_ts2 = swe_ts * 2.0;  // 2 像素步幅
	float swe_h = (
		texture(swe_texture, v_swe_uv).r * 4.0 +
		texture(swe_texture, v_swe_uv + vec2(swe_ts2.x, 0.0)).r +
		texture(swe_texture, v_swe_uv - vec2(swe_ts2.x, 0.0)).r +
		texture(swe_texture, v_swe_uv + vec2(0.0, swe_ts2.y)).r +
		texture(swe_texture, v_swe_uv - vec2(0.0, swe_ts2.y)).r
	) / 8.0;  // 加權平均（中心×4，四鄰各×1）
	float is_obstacle = texture(swe_texture, v_swe_uv).a;
		float wave_weight = 1.0 - is_obstacle;
		
		// Time Interpolation for smooth vertex movement
		float interpolated_time = physics_time + render_alpha * (1.0 / 60.0);
		
		// ✅ LOD Strategy: Always run 8 iterations, but per-layer fade handles energy
		// The get_layer_lod_fade() function smoothly fades high-freq layers at distance
		// instead of hard-stepping iterations (which caused aliasing pop-in)
		int iterations = 8;
		v_cam_dist = cam_dist;  // Pass to fragment for analytical normal LOD matching

		// Gerstner Waves
		vec3 tangent = vec3(1.0, 0.0, 0.0);
		vec3 binormal = vec3(0.0, 0.0, 1.0);
		vec3 wave_disp = vec3(0.0);

		// Jacobian accumulator (Determinant initialized to 1.0)
		float j_det = 1.0;

		// Calculate Distance Damping for smooth horizon
		float dist = length(world_pos - CAMERA_POSITION_WORLD);
		float wave_damp = 1.0 - smoothstep(far_fade_start, far_fade_max, dist);
		
		// World Space Edge Damping (Box Projection)
		vec2 dist_from_center = abs(world_pos.xz - manager_world_pos.xz);
		vec2 half_size = sea_size * 0.5;
		
		vec2 margin_general = half_size * 0.4;
		vec2 edge_t_gen = smoothstep(half_size - margin_general, half_size, dist_from_center);
		edge_t_gen = smoothstep(0.0, 1.0, edge_t_gen);
		
		vec2 margin_horizontal = half_size * 0.2;
		vec2 edge_t_hor = smoothstep(half_size - margin_horizontal, half_size, dist_from_center);
		edge_t_hor = smoothstep(0.0, 1.0, edge_t_hor);
		
		float edge_damp_gen = (1.0 - edge_t_gen.x) * (1.0 - edge_t_gen.y);
		float edge_damp_hor = (1.0 - edge_t_hor.x) * (1.0 - edge_t_hor.y);
		
		float final_damp = wave_damp * edge_damp_gen;
		float h_damp = edge_damp_hor;
		v_edge_damp = edge_damp_gen; // Pass to fragment for Alpha fade
		
		if (wind_strength > 0.001) {
			wave_disp = get_waves_displacement(world_pos, interpolated_time, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, tangent, binormal, iterations, j_det, cam_dist);
		}

		v_jacobian = 1.0 - j_det;
		
		vec3 rogue_disp = get_rogue_wave_displacement(world_pos, interpolated_time, tangent, binormal, tangent, binormal);
		wave_disp += rogue_disp;
		
		// ✅ Recalculate normal including Rogue Wave influence
		v_wave_normal = normalize(cross(binormal, tangent));
		
		wave_disp.xz *= h_damp;
		wave_disp.y *= final_damp;
		
		// Apply manual height multiplier
		wave_disp.y *= wave_height_multiplier;
		
		// === Breaking Wave Logic Removed ===

		
		// 🔥 Global Sea Level Floor
		
		VERTEX.xyz += wave_disp; 
		VERTEX.y += swe_h * swe_strength * wave_weight * final_damp;
		v_swe_h = swe_h;  // ★ Pass to fragment for fill-mode discard
		
		vec2 fft_uv = (world_pos.xz / sea_size) + 0.5;
		float fft_h = texture(fft_texture, fft_uv).b;
		VERTEX.y += fft_h * wind_strength * wave_weight * fft_scale * final_damp;
		
		// === Analytic Ripple Vertex Displacement ===
		// ★ 用低頻高斯凹陷代替高頻正弦——mesh 解析度 0.625m/vertex 無法表現 0.157m 正弦
		// 細環完全交給 fragment shader 的法線擾動（per-pixel 不受 mesh 限制）
		{
			float ar_vert_h = 0.0;
			for (int i = 0; i < ar_count; i++) {
				vec4 r = ar_data[i];
				float age = physics_time - r.z;
				if (age <= 0.0 || age > ar_lifetime) continue;
				
				vec2 off = world_pos.xz - r.xy;
				float dist = length(off);
				float radius = age * ar_speed;
				
				// ★ 低頻高斯凹陷：只在波前附近產生平滑的高度變化
				// 不用 sin()，用 Gaussian bump 讓 mesh 能乾淨表示
				float wave_dist = dist - radius;
				float gauss = exp(-wave_dist * wave_dist * 0.5);  // 寬 ~1.4m 的高斯
				// 波前微微隆起，波前內部微微凹陷
				float h = gauss * (wave_dist > 0.0 ? 1.0 : -0.3);
				
				float spatial_decay = exp(-dist * ar_decay * 0.15);
				float time_decay = (1.0 - age / ar_lifetime);
				time_decay *= time_decay;
				ar_vert_h += h * r.w * spatial_decay * time_decay;
			}
			VERTEX.y += ar_vert_h * ripple_height_scale * final_damp * 0.3;
		}

		// === Kelvin Wake Vertex Displacement ===
		if (kelvin_wake_count > 0) {
			float kw_h = kelvin_wake_height(world_pos.xz);
			VERTEX.y += kw_h * final_damp;
		}
		
		v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 blend_normals(vec3 n1, vec3 n2) {
    return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
}

// ★ 物理 Schlick Fresnel（水面 IOR=1.33）
// R0 = ((1.33-1.0)/(1.33+1.0))^2 ≈ 0.02
// 正面看 → 2% 反射（幾乎透明）
// 掠角看 → 接近 100% 反射（鏡面）
float schlick_fresnel(vec3 view_dir, vec3 normal_dir) {
    const float R0 = 0.02;
    float cos_theta = max(dot(view_dir, normal_dir), 0.0);
    return R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
}

// ★ Seascape 焦散（保留 mod 確保 GPU 浮點穩定）
float water_caustic(vec2 uv, float t) {
    vec2 p = mod(uv * 6.2831, 6.2831) - 250.0;
    vec2 i = p;
    float c = 1.0;
    float inten = 0.005;
    for (int n = 0; n < 5; n++) {
        float ft = t * (1.0 - 3.5 / float(n + 1));
        i = p + vec2(
            cos(ft - i.x) + sin(ft + i.y),
            sin(ft - i.y) + cos(ft + i.x)
        );
        c += 1.0 / length(vec2(
            p.x / (sin(i.x + ft) / inten),
            p.y / (cos(i.y + ft) / inten)
        ));
    }
    c /= 5.0;
    c = 1.17 - pow(abs(c), 1.4);
    return pow(abs(c), 8.0);
}

void fragment() {
	// ★ Read SWE texture globally once
	vec4 swe_frag = texture(swe_texture, v_swe_uv);
	vec2 swe_velocity = swe_frag.gb; // X and Z water velocity from SWE physics
	float swe_h_frag = swe_frag.r;
	
	// ★ SWE Fill Mode: discard obstacles and dry cells (per-fragment for clean edges)
	if (swe_fill_mode > 0.5) {
		if (v_swe_uv.x < 0.0 || v_swe_uv.x > 1.0 || v_swe_uv.y < 0.0 || v_swe_uv.y > 1.0) {
			discard;
		}
		if (swe_h_frag < swe_fill_threshold || swe_frag.a > 0.3) {
			discard;
		}
	}
	// 1. Depth & Water Color - Using Linear Z Difference for robust Depth Fade
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos_raw = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos_raw.xyz /= view_pos_raw.w;
	
	// Use View-Space Z for depth comparison (Standard Graph method)
	float geometry_z = -view_pos_raw.z;
	float surface_z = -VERTEX.z;
	float water_depth_raw = max(geometry_z - surface_z, 0.0);
	// ★ 限制有效深度：沒有地形的區域不會變全黑
	float water_depth = min(water_depth_raw, 10.0);
	
	// === HPWater-Style Volumetric Absorption ===
	
	// 1. 分離吸收 + 散射 → 消光係數
	vec3 vol_absorption = absorption_rgb * absorption_coeff;
	vec3 vol_scattering = scattering_rgb * absorption_coeff;
	vec3 extinction_coeff = vol_absorption + vol_scattering;
	
	// 2. Beer-Lambert 透射率
	vec3 transmittance = exp(-extinction_coeff * water_depth);
	
	// 3. 散射反照率 = 被散射的比例 (vs 被吸收變熱)
	vec3 scatter_albedo = vol_scattering / max(extinction_coeff, vec3(0.0001));
	
	// 4. 消光的光量
	vec3 extinguished = vec3(1.0) - transmittance;
	
	// 5. Henyey-Greenstein 相位函數 (Mie 前向散射)
	float cos_theta = dot(VIEW, normalize(sun_direction)); // VIEW 向相機，sun_direction 向下
	float g2 = scattering_phase_g * scattering_phase_g;
	float hg_phase = (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * scattering_phase_g * cos_theta, 0.0001), 1.5);
	// Rayleigh (5%) + Mie (95%)
	float rayleigh_phase = (1.0 + cos_theta * cos_theta) * 0.0596;  // 3/(16π)
	float phase = rayleigh_phase * 0.05 + hg_phase * 0.95;
	
	// 6. 直射光散射色 = 消光 × 反照率 × 相位 × 太陽色
	vec3 direct_scatter = extinguished * scatter_albedo * phase * sun_color * sun_intensity * 0.3;
	
	// 7. 深度分區的環境散射色（保留藝術控制）
	float shore_blend = smoothstep(0.0, depth_zone_mid, water_depth);
	float deep_blend = smoothstep(depth_zone_mid, depth_zone_deep, water_depth);
	vec3 ambient_scatter = mix(
		mix(color_shore.rgb, color_mid.rgb, shore_blend),
		color_deep.rgb,
		deep_blend
	);
	
	// 8. 最終散射色 = 直射光散射 + 環境散射 (吸收部分)
	vec3 scatter_color = direct_scatter + ambient_scatter * extinguished * (vec3(1.0) - scatter_albedo);
	
	// 波浪波峰 SSS（透光度）
	float wave_thickness = max(0.0, v_world_pos.y - manager_world_pos.y);
	vec3 peak_scattered_light = water_scatter_color * exp(-wave_thickness * 1.5) * smoothstep(0.0, 1.0, wave_thickness);
	
	// ... (Rest of logic needs careful integration)
	
	// 2. Sample Weather Influence
	vec4 weather_data = texture(weather_influence, v_swe_uv);
	float weather_danger = weather_data.a;
	scatter_color = mix(scatter_color, scatter_color * 0.4, clamp(weather_danger * 2.0, 0.0, 1.0));

	// ... (Normal Reconstruction - 寬步幅 Sobel 消除 SWE 網格偽影)
    vec2 ts = 1.0 / vec2(textureSize(swe_texture, 0));
    
    // ★ 2 像素步幅的 3×3 Sobel（覆蓋 5×5 範圍，9 次取樣）
    // 比 1 像素步幅多模糊 4 倍，有效消除菱形干涉紋
    vec2 ts2 = ts * 2.0;  // 2 像素間距
    float h_tl = texture(swe_texture, v_swe_uv + vec2(-ts2.x, -ts2.y)).r;
    float h_tc = texture(swe_texture, v_swe_uv + vec2(0.0, -ts2.y)).r;
    float h_tr = texture(swe_texture, v_swe_uv + vec2(ts2.x, -ts2.y)).r;
    float h_ml = texture(swe_texture, v_swe_uv + vec2(-ts2.x, 0.0)).r;
    float h_mr = texture(swe_texture, v_swe_uv + vec2(ts2.x, 0.0)).r;
    float h_bl = texture(swe_texture, v_swe_uv + vec2(-ts2.x, ts2.y)).r;
    float h_bc = texture(swe_texture, v_swe_uv + vec2(0.0, ts2.y)).r;
    float h_br = texture(swe_texture, v_swe_uv + vec2(ts2.x, ts2.y)).r;
    
    // Sobel X/Y（寬步幅 = 更平滑的梯度）
    float sobel_x = (h_tr + 2.0 * h_mr + h_br) - (h_tl + 2.0 * h_ml + h_bl);
    float sobel_y = (h_bl + 2.0 * h_bc + h_br) - (h_tl + 2.0 * h_tc + h_tr);
    
    vec3 ripple_n_offset = vec3(-sobel_x, 0.0, -sobel_y) * swe_strength * 0.25;
	
	// Weather Normal Reconstruction
	float w_r = texture(weather_influence, v_swe_uv + vec2(ts.x, 0.0)).r;
	float w_l = texture(weather_influence, v_swe_uv - vec2(ts.x, 0.0)).r;
	float w_d = texture(weather_influence, v_swe_uv + vec2(0.0, ts.y)).r;
	float w_u = texture(weather_influence, v_swe_uv - vec2(0.0, ts.y)).r;
	vec3 weather_n_offset = vec3(w_l - w_r, 0.0, w_u - w_d) * 2.0;

	// Normal System
	vec3 base_normal = v_wave_normal;
	
	// ✅ Always compute analytic normal (wind_strength naturally attenuates when calm)
	{
		float interpolated_time = physics_time + render_alpha * (1.0 / 60.0);
		vec3 analytical_n = get_gerstner_normal_analytical(v_world_pos, interpolated_time, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
		
		// Blend weight: stronger analytic contribution at wave peaks, softer in troughs
		float wave_height_factor = clamp(v_world_pos.y / max(wave_length * 0.2, 0.5), 0.0, 1.0);
		float smooth_transition = smoothstep(0.0, 0.6, wave_height_factor);
		float mix_weight = mix(0.4, 0.8, smooth_transition);
		mix_weight *= v_edge_damp * wind_strength;  // Natural fade when calm
		
		base_normal = normalize(mix(base_normal, analytical_n, clamp(mix_weight, 0.0, 1.0)));
	}

	vec3 controlled_ripple = ripple_n_offset * clamp(swe_strength * 0.5, 0.0, 1.5);
	vec3 controlled_weather = weather_n_offset * clamp(weather_danger * 1.5, 0.0, 2.0);
	
	// === Analytic Ripple Normal Perturbation ===
	vec3 gpu_ripple_normal = vec3(0.0);
	float ripple_height_val = 0.5;  // ★ 儲存漣漪高度供 wake foam 使用 (<0.5: 波谷)
	float ripple_fade_val = 1.0;
	{
		float ar_h = 0.0;
		vec3 ar_norm_offset = vec3(0.0);
		
		for (int i = 0; i < ar_count; i++) {
			vec4 r = ar_data[i];
			float age = physics_time - r.z;
			if (age <= 0.0 || age > ar_lifetime) continue;
			
			vec2 off = v_world_pos.xz - r.xy;
			float dist = length(off);
			float radius = age * ar_speed;
			
			// ★ 改良：更寬的包絡 + 1/√r 衰減 → 柔和透明環
			float phase = (dist - radius) * ar_freq;
			float envelope = exp(-phase * phase * 0.08);  // 0.03→0.08 更寬更柔
			float wave_val = sin(phase) * envelope;
			
			// ★ 真實水波 1/√r 振幅衰減（能量守恆）
			float r_decay = 1.0 / (1.0 + sqrt(max(dist, 0.0)) * 0.8);
			float time_decay = (1.0 - age / ar_lifetime);
			time_decay *= time_decay;
			
			float combined_decay = r_decay * time_decay;
			float h = wave_val * r.w * combined_decay;
			ar_h += h;
			
			// ★ 柔化法線：slope 除以 (dist+1) 避免近處太銳利
			if (dist > 0.01) {
				vec2 dir = off / dist;
				float slope = cos(phase) * ar_freq * envelope * r.w * combined_decay;
				// ★ 距離衰減：近處法線也不能太銳利
				slope /= (1.0 + dist * 0.3);
				ar_norm_offset.x += dir.x * slope * ripple_normal_strength * 0.15;
				ar_norm_offset.z += dir.y * slope * ripple_normal_strength * 0.15;
			}
		}
		
		gpu_ripple_normal = ar_norm_offset;
		
		// 映射 ripple height 供泡沫使用
		ripple_height_val = 0.5 - ar_h * 0.8; 
		
		// ★ 柔和焦散（只在高梯度時觸發，永遠乾淨）
		float caustic_raw = length(ar_norm_offset) * 2.0;
		float caustic_bright = clamp(pow(max(caustic_raw, 0.0), 2.0), 0.0, 0.25);
		gpu_ripple_normal.y = caustic_bright;
	}
	
	// === Kelvin Wake Normal ===
	vec3 kelvin_normal_offset = vec3(0.0);
	if (kelvin_wake_count > 0) {
		vec3 kw_n = kelvin_wake_normal(v_world_pos.xz);
		kelvin_normal_offset = (kw_n - vec3(0.0, 1.0, 0.0)) * 1.5;
	}
	
	// === Local High-Res Ripple Normal (256×256 波動方程) ===
	// ★ 改良：2 像素步幅 3×3 Sobel（與 SWE 同寬步幅消除鋸齒環）
	vec3 local_ripple_normal = vec3(0.0);
	{
		vec2 lr_uv = (v_world_pos.xz - local_ripple_center) / local_ripple_size + 0.5;
		// 只在覆蓋範圍內取樣
		if (lr_uv.x > 0.04 && lr_uv.x < 0.96 && lr_uv.y > 0.04 && lr_uv.y < 0.96) {
			vec2 lr_texel = 1.0 / vec2(textureSize(local_ripple_tex, 0));
			// ★ 2 像素步幅 3×3 Sobel（覆蓋 5×5 範圍 = 更平滑）
			vec2 lr_t2 = lr_texel * 2.0;
			float lr_tl = texture(local_ripple_tex, lr_uv + vec2(-lr_t2.x, -lr_t2.y)).r;
			float lr_tc = texture(local_ripple_tex, lr_uv + vec2(0.0, -lr_t2.y)).r;
			float lr_tr = texture(local_ripple_tex, lr_uv + vec2(lr_t2.x, -lr_t2.y)).r;
			float lr_ml = texture(local_ripple_tex, lr_uv + vec2(-lr_t2.x, 0.0)).r;
			float lr_mr = texture(local_ripple_tex, lr_uv + vec2(lr_t2.x, 0.0)).r;
			float lr_bl = texture(local_ripple_tex, lr_uv + vec2(-lr_t2.x, lr_t2.y)).r;
			float lr_bc = texture(local_ripple_tex, lr_uv + vec2(0.0, lr_t2.y)).r;
			float lr_br = texture(local_ripple_tex, lr_uv + vec2(lr_t2.x, lr_t2.y)).r;
			
			// Sobel X/Y（寬步幅 = 更平滑梯度，無鋸齒環）
			float lr_sx = (lr_tl + 2.0 * lr_ml + lr_bl) - (lr_tr + 2.0 * lr_mr + lr_br);
			float lr_sy = (lr_tl + 2.0 * lr_tc + lr_tr) - (lr_bl + 2.0 * lr_bc + lr_br);
			
			// ★ 邊緣漸出：離中心越遠強度越低（自然消散）
			vec2 lr_from_center = lr_uv - 0.5;
			float lr_dist = length(lr_from_center) * 2.0;
			float lr_fade = smoothstep(1.0, 0.6, lr_dist);
			
			local_ripple_normal.x = lr_sx * local_ripple_strength * lr_fade;
			local_ripple_normal.z = lr_sy * local_ripple_strength * lr_fade;
		}
	}
	
	vec3 normal = normalize(base_normal + controlled_ripple + controlled_weather + gpu_ripple_normal + kelvin_normal_offset + local_ripple_normal);

	
	// Detail Normals (Keeping existing dual sampling logic simplified for brevity in this replacement, assume mostly unchanged)
	// ... (Skipping full detail normal re-implementation for brevity, assuming standard mix)
	// For implementing the new foam logic, we focus on the Foam section below.
	
	// ... (Detail Normal Logic) ...
	// To minimize code replacement risk, I will re-implement the detail normal logic as it was, to ensure it works.
	
	vec3 detail_normal;
    // Flow Map & SWE Velocity Advection Logic
    	vec2 flow_uv = v_world_pos.xz / sea_size + 0.5;
    	// Combine manual flow map with SWE physical velocity
    	vec2 flow_vector = (texture(flow_map, flow_uv).rg * 2.0 - 1.0) * flow_strength;
    	
    	// Add SWE velocity scaled by swe_strength, with some scaling suitable for normal panning
    	flow_vector += swe_velocity * 0.1 * swe_strength;
    	
    	if (length(flow_vector) > 0.005) {
    		// Faster flow speed based on vector magnitude
    		float dynamic_flow_speed = flow_speed + length(flow_vector) * 0.5;
    		float flow_phase0 = fract(TIME * dynamic_flow_speed);
    		float flow_phase1 = fract(TIME * dynamic_flow_speed + 0.5);
    		float flow_lerp = abs(0.5 - flow_phase0) / 0.5;
    		
    		vec2 flow_uv1 = v_world_pos.xz * normal_tile * 0.1 - flow_vector * flow_phase0;
    		vec2 flow_uv2 = v_world_pos.xz * normal_tile * 0.1 - flow_vector * flow_phase1;
    		
    		vec3 f_n1 = texture(normal_map1, flow_uv1).rgb * 2.0 - 1.0;
    		vec3 f_n2 = texture(normal_map1, flow_uv2).rgb * 2.0 - 1.0;
    		
    		detail_normal = normalize(mix(f_n1, f_n2, flow_lerp));
    	} else {
    		vec2 normal_uv1 = v_world_pos.xz * normal_tile * 0.1;
    		vec2 normal_uv2 = v_world_pos.zx * normal_tile * 0.11 + vec2(TIME * 0.05, -TIME * 0.03); 
    		
    		vec3 n1_a = texture(normal_map1, normal_uv1 + TIME * normal_speed).rgb * 2.0 - 1.0;
    		vec3 n1_b = texture(normal_map1, normal_uv2 - TIME * normal_speed * 0.7).rgb * 2.0 - 1.0;
    		vec3 n1_sample = normalize(n1_a + n1_b);
    		n1_sample.xy *= normal_scale; 
    		
    		vec3 n2_a = texture(normal_map2, normal_uv1 * 1.2 - TIME * normal_speed * 1.5).rgb * 2.0 - 1.0;
    		vec3 n2_b = texture(normal_map2, normal_uv2 * 0.9 + TIME * normal_speed * 0.8).rgb * 2.0 - 1.0;
    		vec3 n2_sample = normalize(n2_a + n2_b);
    		n2_sample.xy *= normal_scale; 
    		detail_normal = normalize(vec3(n1_sample.xy + n2_sample.xy, 1.0)); 
    	}
	
	float detail_fade = smoothstep(0.3, 1.5, abs(v_world_pos.y)); 
	float detail_strength = normal_scale * 0.2 * (1.0 - detail_fade); 
	if (storm_mode) detail_strength *= 0.5;
	detail_normal = mix(vec3(0.0, 0.0, 1.0), detail_normal, detail_strength);
	normal = normalize(blend_normals(normal, detail_normal));
	
	// FFT Normal Injection
	vec2 fft_grad = texture(fft_texture, (v_world_pos.xz / sea_size) + 0.5).rg;
	vec3 fft_normal = normalize(vec3(-fft_grad.x, 1.0, -fft_grad.y));
	float fft_ramp = smoothstep(0.0, 10.0, TIME);
	float fft_norm_strength = wind_strength * fft_scale * 0.5 * fft_ramp;
	normal = normalize(mix(normal, blend_normals(normal, fft_normal), fft_norm_strength));
	
	// ★★★ Wake 區域：增加水面粗糙感 ★★★
	// 不做複雜流動紋理，只在高動量區域加強既有 detail normal 的強度
	{
		float wake_momentum = length(texture(swe_texture, v_swe_uv).gb);
		float wake_roughness_boost = smoothstep(0.1, 0.5, wake_momentum);
		// 在尾流區域加強既有法線細節（等效於讓水面看起來更「碎」更粗糙）
		if (wake_roughness_boost > 0.001) {
			vec2 wake_uv1 = v_world_pos.xz * 0.6 + TIME * vec2(0.08, -0.04);
			vec2 wake_uv2 = v_world_pos.zx * 0.9 - TIME * vec2(0.05, 0.07);
			vec3 wn1 = texture(normal_map1, wake_uv1).rgb * 2.0 - 1.0;
			vec3 wn2 = texture(normal_map2, wake_uv2).rgb * 2.0 - 1.0;
			vec3 wake_detail = normalize(vec3(wn1.xy + wn2.xy, 1.0));
			// Z-up → Y-up
			vec3 wake_world_n = vec3(wake_detail.x, wake_detail.z, wake_detail.y);
			normal = normalize(normal + wake_world_n * wake_roughness_boost * 0.3);
		}
	}
	
	NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	
	// Initialize color variable
	vec3 color = vec3(0.0); // final color computation is done later
	
	// === 改進：泡沫粒子疊加 ===
    float particle_foam = texture(foam_particle_texture, v_swe_uv).a;
	float spray_tex = texture(spray_particle_texture, v_swe_uv).a;
	float spray_core = 0.0;
	float spray_mist = sample_breaking_spray_mist(v_world_pos.xz, spray_core);
	spray_mist = clamp(max(spray_mist, spray_tex), 0.0, 1.0);
	spray_core = clamp(max(spray_core, spray_tex * 0.9), 0.0, 1.0);
    
    // === 改進：泡沫材質 (3 層混合) ===
    vec2 foam_uv_fine = v_world_pos.xz * 2.0 + TIME * 0.1;
    vec2 foam_uv_coarse = v_world_pos.xz * 0.5 - TIME * 0.05;
    
    float foam_detail_1 = texture(foam_noise, foam_uv_fine).r;
    float foam_detail_2 = texture(foam_noise, foam_uv_coarse * 1.3).r;
    float foam_sparkle_value = pow(texture(foam_noise, foam_uv_fine * 3.0).r, 4.0);
    
    // 計算一般波浪泡沫 (Jacobian)
    float foam_jacob_signal = smoothstep(foam_jacobian_bias, foam_jacobian_bias + 0.2, v_jacobian);
    float steepness_signal = max(v_jacobian - foam_jacobian_bias, 0.0);
    float wave_energy = steepness_signal * wind_strength; 
    
    // ★ wake_signal is intentionally EXCLUDED from crest_foam:
    // Using abs(swe_h) here creates circular halos around any SWE disturbanc.
    // SWE-based foam is handled by physical gradient below in the wake_foam block.
    float weather_energy = clamp(weather_danger * 2.0, 0.0, 1.0);
    float energetic_signal = foam_jacob_signal * 1.0 + wave_energy * 0.5 + weather_energy;
    float crest_foam = 0.0;
	// Jacobian crest foam 已關閉
	//if (wind_strength > 0.1 || storm_mode) {
	//	crest_foam = smoothstep(0.4, 0.7, energetic_signal);
	//}
	
	// ★★★ B4: 尾流泡沫 ★★★
	float wake_foam = 0.0;
	{
		// ★ Analytic Ripple Foam（只在高梯度時觸發，永遠乾淨）
		float ripple_gradient = length(gpu_ripple_normal.xz);
		float gradient_foam = smoothstep(4.0, 8.0, ripple_gradient) * 0.2;
		wake_foam = gradient_foam * ripple_fade_val;
		
		// ★ SWE 泡沫：分兩軌
		{
			vec2 ts = 1.0 / vec2(textureSize(swe_texture, 0));
			
			// 取四鄰高度與速度
			float swe_h_r = texture(swe_texture, v_swe_uv + vec2(ts.x, 0.0)).r;
			float swe_h_l = texture(swe_texture, v_swe_uv - vec2(ts.x, 0.0)).r;
			float swe_h_u = texture(swe_texture, v_swe_uv + vec2(0.0, ts.y)).r;
			float swe_h_d = texture(swe_texture, v_swe_uv - vec2(0.0, ts.y)).r;
			vec2 vel_r = texture(swe_texture, v_swe_uv + vec2(ts.x, 0.0)).gb;
			vec2 vel_l = texture(swe_texture, v_swe_uv - vec2(ts.x, 0.0)).gb;
			vec2 vel_u = texture(swe_texture, v_swe_uv + vec2(0.0, ts.y)).gb;
			vec2 vel_d = texture(swe_texture, v_swe_uv - vec2(0.0, ts.y)).gb;
			float phys_dx = ts.x * sea_size.x;
			float phys_dy = ts.y * sea_size.y;
			
			// === 軌道 A：碰撞點泡沫（完全不需風力）===
			// 速度散度：負值 = 流入 = 兩股水流正面碰撞
			float div_x = (vel_r.x - vel_l.x) / (2.0 * phys_dx);
			float div_y = (vel_u.y - vel_d.y) / (2.0 * phys_dy);
			float divergence = div_x + div_y;
			float convergence_foam = smoothstep(-0.5, -3.0, divergence) * 0.8;
			
			// Laplacian 凹陷（碰撞壓力的水面凹痕）
			float laplacian = (swe_h_r + swe_h_l + swe_h_u + swe_h_d - 4.0 * swe_h_frag);
			float curvature_foam = smoothstep(-0.1, -0.5, laplacian) * 0.4;
			
			// 碰撞泡沫直接寫入
			float collision_foam = max(convergence_foam, curvature_foam);
			wake_foam = max(wake_foam, collision_foam * foam_wake_strength);
			
			// === 軌道 B：一般流動泡沫（需要風力，無風靜水不要）===
			if (wind_strength > 0.3) {
				float swe_dx = (swe_h_r - swe_h_l) / (2.0 * phys_dx);
				float swe_dy = (swe_h_u - swe_h_d) / (2.0 * phys_dy);
				float swe_slope = length(vec2(swe_dx, swe_dy));
				float swe_foam_edge = smoothstep(0.6, 2.0, swe_slope) * 0.5;
				
				float swe_momentum = length(swe_velocity);
				float momentum_foam = smoothstep(0.8, 2.0, swe_momentum) * 0.4;
				float dot_flow_time = TIME * 2.0;
				vec2 advected_uv = v_world_pos.xz * 1.5 - swe_velocity * dot_flow_time;
				float debris_noise = pow(texture(foam_noise, advected_uv).r, 6.0);
				float debris_mask = smoothstep(0.3, 1.0, swe_momentum) * debris_noise * clamp(swe_h_frag * 0.5 + 0.5, 0.0, 1.0);
				momentum_foam = max(momentum_foam, debris_mask * 1.5);
				
				float swe_crest_foam = smoothstep(0.4, 1.0, swe_h_frag) * 0.3;
				swe_crest_foam *= smoothstep(0.2, 0.5, swe_slope);
				
				float wind_gate = smoothstep(0.3, 1.0, wind_strength);
				float wind_foam = max(max(swe_foam_edge, momentum_foam), swe_crest_foam);
				wake_foam = max(wake_foam, wind_foam * foam_wake_strength * wind_gate);
			}
		}
	}
	
	// 合併泡沫源（wake_foam 分開處理，不走硬邊 detail 管道）
    float non_wake_foam = clamp(
        crest_foam +
        particle_foam * 2.0,
        0.0, 1.0
    );
    
    // 硬邊細節（只用在浪頂/粒子泡沫）
    float foam_detail_mix = foam_detail_1 * 0.6 + foam_detail_2 * 0.4;
    foam_detail_mix = smoothstep(0.35, 0.65, foam_detail_mix);
    foam_detail_mix += foam_sparkle_value * 0.15 * step(0.5, foam_detail_mix);
    
    float foam_final_mask = non_wake_foam * foam_detail_mix;
    foam_final_mask = smoothstep(0.15, 0.7, foam_final_mask) * non_wake_foam;
    foam_final_mask = clamp(foam_final_mask + spray_core * 0.35, 0.0, 1.0);
    
    // ★ wake_foam 用柔和的細節通道（寬 smoothstep，不產生硬邊）
    float wake_detail = foam_detail_1 * 0.5 + foam_detail_2 * 0.5;
    wake_detail = smoothstep(0.2, 0.8, wake_detail);  // 寬範圍 = 柔和邊緣
    float wake_foam_final = wake_foam * mix(0.6, 1.0, wake_detail);
    foam_final_mask = max(foam_final_mask, wake_foam_final);
    
    // =============================================
    // === 四層泡沫系統 (4-Layer Foam Architecture) ===
    // =============================================
    
    // ★ Layer 1: 岸邊泡沫（Depth Foam + Noise 破邊 + 脈動動畫）
    float shore_dist = water_depth / edge_scale;
    float shore_foam_raw = 1.0 - clamp(shore_dist, 0.0, 1.0);
    
    // 動態閾值：noise 讓邊緣凹凸不平（不是直線白邊）
    float shore_noise_main = foam_detail_1 * 0.6 + foam_detail_2 * 0.4;
    // UV 跟隨 Gerstner 水平位移（泡沫隨波浪漂動）
    vec2 foam_uv_warped = v_world_pos.xz * 0.3 + TIME * vec2(0.02, 0.015);
    float warped_noise = texture(foam_noise, foam_uv_warped).r;
    float dynamic_threshold = edge_scale * (0.5 + warped_noise * 0.8);
    float shore_foam = (1.0 - smoothstep(0.0, dynamic_threshold, water_depth));
    
    // 細節噪波破掉實心感（小泡泡紋理）
    vec2 detail_uv = v_world_pos.xz * 1.2 - TIME * vec2(0.01, 0.008);
    float detail_break = texture(foam_detail, detail_uv).r;
    shore_foam *= smoothstep(0.25, 0.65, detail_break);
    
    // 脈動消散動畫（泡沫會呼吸式閃爍）
    float foam_pulse = sin(TIME * 0.5 + warped_noise * 6.283) * 0.5 + 0.5;
    shore_foam *= mix(0.7, 1.0, foam_pulse);
    shore_foam *= 0.9;
    
    foam_final_mask = max(foam_final_mask, shore_foam);
    
    // ★ Layer 2: 浪頂白沫（Slope Foam — 法線角度偵測）
    float slope = 1.0 - normal.y; // 0=平坦, 1=垂直
    float slope_foam = smoothstep(0.35, 0.55, slope);
    // 配合 Gerstner 振幅：浪高的地方才有白沫
    slope_foam *= smoothstep(0.2, 0.6, steepness_signal);
    // noise 破掉塑膠感
    slope_foam *= (0.7 + 0.3 * shore_noise_main);
    // 只有有風時才有浪頂泡沫
    slope_foam *= smoothstep(0.05, 0.3, wind_strength);
    
    foam_final_mask = max(foam_final_mask, slope_foam);
    
    // ★ Layer 3: 漂浮泡沫（Voronoi 細胞邊緣 = 泡泡壁）
    // 用兩層不同頻率的 Voronoi 模擬大小泡泡
    vec2 voronoi_uv = v_world_pos.xz * 0.8 + vec2(TIME * 0.03, TIME * 0.02);
    
    // Voronoi 近似：用多層 noise 模擬細胞邊緣
    float v1_a = texture(foam_noise, voronoi_uv * 0.5).r;
    float v1_b = texture(foam_detail, voronoi_uv * 0.5 + vec2(0.37, 0.73)).r;
    float cell_dist_1 = abs(v1_a - v1_b); // 兩層差值 ≈ 細胞邊緣
    float bubble_edge_1 = 1.0 - smoothstep(0.0, 0.12, cell_dist_1); // 大泡泡壁
    
    float v2_a = texture(foam_noise, voronoi_uv * 1.8 + vec2(0.61)).r;
    float v2_b = texture(foam_detail, voronoi_uv * 1.8 + vec2(0.13, 0.47)).r;
    float cell_dist_2 = abs(v2_a - v2_b);
    float bubble_edge_2 = 1.0 - smoothstep(0.0, 0.06, cell_dist_2); // 小泡泡壁
    
    float bubble_foam = bubble_edge_1 * 0.6 + bubble_edge_2 * 0.4;
    // ★ 只在岸邊和浪頂才出現漂浮泡泡（不在漣漪/尾流區域！）
    float foam_for_bubbles = max(shore_foam, crest_foam);
    bubble_foam *= smoothstep(0.3, 0.6, foam_for_bubbles);
    
    // Layer 3 用加法疊加，但強度降低避免蜘蛛網
    foam_final_mask = clamp(foam_final_mask + bubble_foam * 0.15, 0.0, 1.0);
    
    // ★ 泡沫著色（帶環境光感的微色調）
    // 真實泡沫帶微藍（天空反射）+ 微黃（陽光散射）
    vec3 foam_color_tint = mix(
        vec3(0.88, 0.93, 0.98),  // 基礎淺藍白（天空）
        vec3(1.0, 0.98, 0.95),   // 暖白高光（陽光）
        foam_sparkle_value * 0.7
    );
    // 岸邊泡沫略帶沙色
    vec3 shore_foam_color = mix(foam_color_tint, vec3(0.95, 0.93, 0.88), 0.2);
    foam_color_tint = mix(foam_color_tint, shore_foam_color, step(0.3, shore_foam));
    
    // ==========================================
    // === HPWater 風格折射 (Snell's Law Refraction) ===
    // ==========================================
    // 參考 HPWater: 用 Snell's law 計算真實折射方向，
    // 減去平面折射只保留法線擾動的部分

	// 視角方向（世界空間）
	vec3 view_ws = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	// 空氣→水 折射率 (HPWater: eta = 1.0/1.33)
	const float eta = 1.0 / 1.33;
	
	// 實際法線折射 vs 平面法線折射
	vec3 refracted_actual = refract(-view_ws, normal, eta);
	vec3 refracted_flat = refract(-view_ws, vec3(0.0, 1.0, 0.0), eta);
	
	// 只取法線擾動導致的差異（HPWater 核心技巧）
	vec3 refract_delta = refracted_actual - refracted_flat;
	
	// 投影到屏幕 UV 偏移 (深度越深折射越明顯，但限制防穿幫)
	float ref_depth_scale = clamp(water_depth, 0.0, 3.0) * refraction_strength;
	vec2 ref_offset = refract_delta.xz * ref_depth_scale;
	
	// 邊界安全：靠近螢幕邊緣減弱折射防穿幫 (HPWater: safeBound)
	float bound_x = min(SCREEN_UV.x, 1.0 - SCREEN_UV.x) * 6.0;
	float bound_y = min(SCREEN_UV.y, 1.0 - SCREEN_UV.y) * 6.0;
	ref_offset *= clamp(sqrt(clamp(bound_x * bound_y, 0.0, 1.0)), 0.0, 1.0);
	
	// ★ HPWater 風格色散：每個波長用不同折射率 (Snell's Law per-wavelength)
	float eta_r = 1.0 / (1.333 - dispersion_strength);
	float eta_b = 1.0 / (1.333 + dispersion_strength);
	vec3 refract_r = refract(-view_ws, normal, eta_r);
	vec3 refract_b = refract(-view_ws, normal, eta_b);
	vec2 ref_offset_r = (refract_r - refracted_flat).xz * ref_depth_scale;
	vec2 ref_offset_b = (refract_b - refracted_flat).xz * ref_depth_scale;
	float safe_bound = clamp(sqrt(clamp(bound_x * bound_y, 0.0, 1.0)), 0.0, 1.0);
	ref_offset_r *= safe_bound;
	ref_offset_b *= safe_bound;
	
	// ★ 深水折射模糊：模擬前向散射導致的失焦 (HPWater: CalculateHPWaterMipLevel)
	float blur_lod = log2(1.0 + water_depth * refraction_blur_density);
	blur_lod = clamp(blur_lod, 0.0, 4.0);
	
	vec3 ref_color;
	ref_color.r = textureLod(screen_texture, SCREEN_UV + ref_offset_r, blur_lod).r;
	ref_color.g = textureLod(screen_texture, SCREEN_UV + ref_offset, blur_lod).g;
	ref_color.b = textureLod(screen_texture, SCREEN_UV + ref_offset_b, blur_lod).b;
	
	// ★ 焦散增強折射畫面（淺水亮斑）
	{
		vec2 caust_uv = v_world_pos.xz * 0.4;
		float t = TIME * 0.5;
		float c1 = water_caustic(caust_uv, t);
		float c2 = water_caustic(caust_uv, t * 0.7 + 1.3);
		float caustic_val = min(c1, c2);
		
		// Beer-Lambert 深度衰減 + 風力遮蔽
		float depth_mask = exp(-water_depth * 0.5);
		float wind_mask = 1.0 - smoothstep(0.3, 1.5, wind_strength);
		caustic_val *= caustics_strength * depth_mask * wind_mask;
		
		// ★ 焦散色散：RGB 通道用略微不同的 UV 採樣焦散圖案
		float caust_disp = dispersion_strength * 8.0;  // 焦散色散更明顯
		vec2 caust_normal_offset = normal.xz * caust_disp;
		float c_r = water_caustic(caust_uv - caust_normal_offset, t);
		float c_b = water_caustic(caust_uv + caust_normal_offset, t);
		vec3 caustic_rgb = vec3(
			min(c_r, c2),
			caustic_val / max(caustics_strength * depth_mask * wind_mask, 0.001),
			min(c_b, c2)
		) * caustics_strength * depth_mask * wind_mask;
		
		ref_color *= (vec3(1.0) + caustic_rgb * 1.5);
	}

	// ★ 核心物理算法：
	// 最終水色 = (水體本身散射光) + (背景光 * 透射率)
	// water_transparency 參數用來當作人工控制的透明度上限乘數
	vec3 effective_transmittance = transmittance * water_transparency;
	
	// 泡沫會遮擋透明度 (泡沫越濃，透過去的背景光越少)
	effective_transmittance *= (1.0 - foam_final_mask * 0.9);

	// 混合背景與水體
	vec3 water_base_color = mix(scatter_color, ref_color, effective_transmittance);
	
	// 加上波峰透光 (SSS)
	water_base_color += peak_scattered_light * 0.8 * (1.0 - foam_final_mask);
	
	// 天空 Fresnel 反射疊加
	// ★ Schlick Fresnel 反射（使用氣候顏色）
	float sf = schlick_fresnel(VIEW, NORMAL);
	// 天空反射色：垂直看=天頂色，掛角看=地平色
	vec3 reflect_sky = mix(horizon_color, sky_color, max(NORMAL.y, 0.0));
	// 太陽高光：反射方向接近太陽時加亮
	vec3 reflect_dir = reflect(-VIEW, NORMAL);
	vec3 sun_dir_norm = normalize(-sun_direction);
	float sun_spec = pow(max(dot(reflect_dir, sun_dir_norm), 0.0), 256.0) * sun_intensity;
	reflect_sky += sun_color * sun_spec * 2.0;
	// 水面反射
	color = mix(water_base_color, reflect_sky, sf * reflection_strength);
	vec3 spray_tint = mix(color_shallow.rgb, color_foam.rgb, 0.65);
	color = mix(color, spray_tint, spray_mist * 0.22);
	
	// 將泡沫繪製在最上層
	color = mix(color, foam_color_tint, foam_final_mask);
	
	// ★★ P4: 泡沫法線擾動 — 讓泡沫有氣泡凹凸質感
	if (foam_final_mask > 0.1) {
		vec3 foam_n = texture(foam_normal, v_world_pos.xz * 1.5 + TIME * 0.03).rgb * 2.0 - 1.0;
		foam_n.xy *= 0.5;  // 減弱擾動避免太誇張
		normal = normalize(mix(normal, blend_normals(normal, foam_n), foam_final_mask * 0.4));
		// 重新計算 NORMAL 和 fresnel
		NORMAL = (VIEW_MATRIX * vec4(normal, 0.0)).xyz;
	}

	// (ALBEDO 在下方 PBR 區段設定)
	
	// 漣漪焦散（僅微弱表面高光）
	float ripple_activity = clamp(length(gpu_ripple_normal.xz) * 0.5, 0.0, 1.0);
	float ripple_caustic = max(gpu_ripple_normal.y, 0.0) * (1.0 - ripple_activity);
	color += vec3(ripple_caustic * 0.15, ripple_caustic * 0.2, ripple_caustic * 0.25);
    
    // === 透明度最終混合 (Alpha) ===
    // 為了讓深度緩衝區(Depth Buffer)背後的物件正確渲染，ALPHA也需要設定
    // 只要有任何透光或水體存在，我們就將 ALPHA 設高，但留一點空間給極淺水
    ALPHA = mix(
        smoothstep(0.0, edge_scale, water_depth) * mix(0.8, 1.0, water_transparency),
        1.0,
        foam_final_mask
    );
    ALPHA *= smoothstep(0.0, 0.2, v_edge_damp);
	ALPHA = clamp(ALPHA + spray_mist * 0.08, 0.0, 1.0);
    
    // === PBR: 參考 shader 的反射策略 ===
    // METALLIC=1, ROUGHNESS=0 → Godot PBR 引擎做完美鏡面反射
    // ALBEDO × fresnel → 掠角反射強，正面看透明
    // 折射的水底景象放在 EMISSION（不受 PBR 反射影響）
    
    float fres = schlick_fresnel(VIEW, NORMAL);
    
    // 水面反射色 = 已算好的水面色 × fresnel
    vec3 water_reflect_albedo = color * fres;
    
    // 泡沫區域：回歸漫反射（白色不透明）
    // ★ 降低泡沫亮度：泡沫是霧化的氣泡，不應過亮
    vec3 foam_albedo_dimmed = foam_color_tint * 0.65;   // 35% 減亮，避免 PBR 過曝
    ALBEDO = mix(water_reflect_albedo, foam_albedo_dimmed, foam_final_mask);
    ROUGHNESS = mix(0.02, 1.0, foam_final_mask);        // 水面近乎鏡面，泡沫完全粗糙
    METALLIC = mix(1.0, 0.0, foam_final_mask);           // 泡沫漫反射（無金屬性）
    SPECULAR = 0.0;                                       // 不加額外高光
    
    // 折射景象放進 EMISSION（透過 Fresnel 反向控制：正面看多，掠角看少）
    vec3 refracted_emission = water_base_color * (1.0 - fres);
    
    // SSS（次表面散射）
    vec3 sss_emission = vec3(0.0);
    if (wind_strength > 0.01) {
        float crest_highlight = pow(steepness_signal, 8.0) * fresnel_strength;
        sss_emission += vec3(1.0) * crest_highlight * 0.3 * (1.0 - foam_final_mask);
    }
    float sss_mask = pow(steepness_signal, 4.0);
    float sss_view_mask = pow(clamp(dot(VIEW, -NORMAL), 0.0, 1.0), 3.0);
    sss_emission += sss_color.rgb * sss_strength * sss_mask * (0.2 + 0.8 * sss_view_mask) * (1.0 - foam_final_mask);
	sss_emission += spray_tint * spray_mist * (0.08 + sf * 0.12) * (1.0 - foam_final_mask);
    
    // 漣漪波峰 SSS
    float ripple_crest_mask = smoothstep(0.45, 0.35, ripple_height_val) * ripple_fade_val;
    float ripple_sss_view = pow(max(dot(VIEW, -NORMAL), 0.0), 4.0);
    float fresnel_suppress = 1.0 - ripple_activity;
    sss_emission += sss_color.rgb * ripple_crest_mask * ripple_sss_view * sss_strength * 0.5 * fresnel_suppress;
    
    EMISSION = refracted_emission + sss_emission;
    // 泡沫區域不要折射 EMISSION
    EMISSION *= (1.0 - foam_final_mask);
    EMISSION = min(EMISSION, vec3(1.5));
	
	// === Debug Normal Visualization (Amplified XZ Deviation) ===
	if (debug_normal_mode > 0) {
		vec3 debug_color = vec3(0.0);
		
		// Helper: Convert normal's XZ tilt to visible color
		// Amplifies the horizontal component 5x so subtle tilts become obvious
		// Color wheel: Red=+X, Green=+Z, Cyan=-X, Magenta=-Z
		// Brightness = tilt amount, Dark center = perfectly vertical
		
		if (debug_normal_mode == 1) {
			// Mode 1: Final blended normal — XZ tilt amplified
			vec2 tilt = normal.xz * 5.0;  // 5x amplification
			float tilt_amount = clamp(length(tilt), 0.0, 1.0);
			debug_color = vec3(
				tilt.x * 0.5 + 0.5,          // Red = X direction
				tilt.y * 0.5 + 0.5,          // Green = Z direction
				1.0 - tilt_amount             // Blue = flatness (bright=flat)
			);
		}
		else if (debug_normal_mode == 2) {
			// Mode 2: Pure analytical Gerstner normal — XZ tilt amplified
			float interp_t = physics_time + render_alpha * (1.0 / 60.0);
			vec3 ana_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
			vec2 tilt = ana_n.xz * 5.0;
			float tilt_amount = clamp(length(tilt), 0.0, 1.0);
			debug_color = vec3(
				tilt.x * 0.5 + 0.5,
				tilt.y * 0.5 + 0.5,
				1.0 - tilt_amount
			);
		}
		else if (debug_normal_mode == 3) {
			// Mode 3: Vertex normal — XZ tilt amplified
			vec2 tilt = v_wave_normal.xz * 5.0;
			float tilt_amount = clamp(length(tilt), 0.0, 1.0);
			debug_color = vec3(
				tilt.x * 0.5 + 0.5,
				tilt.y * 0.5 + 0.5,
				1.0 - tilt_amount
			);
		}
		else if (debug_normal_mode == 4) {
			// Mode 4: Difference heatmap — 10x more sensitive
			float interp_t = physics_time + render_alpha * (1.0 / 60.0);
			vec3 ana_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
			float diff = length(ana_n - v_wave_normal) * 5.0;  // Amplify difference
			// More sensitive gradient: Blue(0) → Cyan(0.1) → Green(0.2) → Yellow(0.5) → Red(1.0)
			debug_color.r = smoothstep(0.05, 0.3, diff);
			debug_color.g = smoothstep(0.0, 0.05, diff) * (1.0 - smoothstep(0.5, 1.0, diff));
			debug_color.b = 1.0 - smoothstep(0.0, 0.1, diff);
		}
		else if (debug_normal_mode == 5) {
			// Mode 5: Split-screen A/B comparison
			// LEFT  = With LOD fade (what player sees)
			// RIGHT = Full 8 layers (no LOD fade, reference)
			float interp_t = physics_time + render_alpha * (1.0 / 60.0);
			
			// LOD-faded normal (uses cam_dist for fade)
			vec3 lod_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, v_cam_dist);
			
			// Full-detail normal (cam_dist=0 means no fade applied)
			vec3 full_n = get_gerstner_normal_analytical(v_world_pos, interp_t, wind_strength, wind_dir, wave_length, wave_steepness, wave_chaos, 0.0);
			
			// Split screen using SCREEN_UV.x
			vec2 screen_uv = SCREEN_UV;
			bool is_left = screen_uv.x < 0.5;
			
			// Show normal-mapped grayscale (tilt intensity = detail level)
			vec3 chosen_n = is_left ? lod_n : full_n;
			float detail = length(chosen_n.xz) * 4.0;
			
			// Grayscale with slight color tint: left=blue tint, right=green tint
			if (is_left) {
				debug_color = vec3(0.2, 0.4, 0.8) * (0.3 + detail);  // Blue tint
			} else {
				debug_color = vec3(0.2, 0.8, 0.3) * (0.3 + detail);  // Green tint
			}
			
			// Red divider line (2px wide)
			if (abs(screen_uv.x - 0.5) < 0.003) {
				debug_color = vec3(1.0, 0.0, 0.0);
			}
		}
		
		ALBEDO = debug_color;
		EMISSION = debug_color * 0.5;  // Brighter emission so it's clearly visible
		ALPHA = 1.0;
		METALLIC = 0.0;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);  // Flat normal so lighting doesn't interfere
	}
}
