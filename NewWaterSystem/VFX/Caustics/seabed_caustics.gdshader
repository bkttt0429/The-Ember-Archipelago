shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// === 海底材質 — HPWater 風格焦散投射 ===
// - Beer-Lambert 吸收衰減
// - 色散偏移 (Chromatic Dispersion)
// - Mipmap 深度模糊
// - ★ 水面法線→焦散聯動 (SWE texture driven)

uniform vec4 sand_color : source_color = vec4(0.76, 0.7, 0.5, 1.0);
uniform float water_surface_y : hint_range(-10.0, 10.0) = 0.0;
uniform float caustic_intensity : hint_range(0.0, 3.0) = 1.2;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.4;
uniform vec3 water_extinction : source_color = vec3(0.4, 0.2, 0.08);
uniform float chromatic_dispersion : hint_range(0.0, 0.5) = 0.08;
uniform float depth_blur_rate : hint_range(0.0, 1.0) = 0.3;

// ★ 水面波動紋理（SWE 模擬輸出或局部漣漪）
// R = 水位高度, G/B = 速度場
uniform sampler2D swe_texture : hint_default_black, filter_linear, repeat_enable;
uniform vec2 swe_world_origin = vec2(0.0);  // SWE 中心世界座標
uniform float sea_size = 128.0;             // SWE 覆蓋尺寸 (m)
// 水面法線對焦散的偏移強度
uniform float wave_refract_strength : hint_range(0.0, 2.0) = 0.5;
// 光線方向（正規化，從天空指向地面）
uniform vec3 light_direction = vec3(0.3, -0.8, 0.2);

// === Seascape 焦散函數 ===
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

// ★ 從 SWE 高度圖計算水面法線（中心差分，與 HPWater FluidSample 一致）
vec3 sample_water_normal(vec2 world_xz) {
    vec2 uv = (world_xz - swe_world_origin) / sea_size + 0.5;
    // 紋理像素尺寸
    vec2 texel = vec2(1.0) / vec2(textureSize(swe_texture, 0));
    
    // 中心差分（HPWater: hLeft-hRight, hDown-hUp）
    float h_l = texture(swe_texture, uv + vec2(-texel.x, 0.0)).r;
    float h_r = texture(swe_texture, uv + vec2(texel.x, 0.0)).r;
    float h_u = texture(swe_texture, uv + vec2(0.0, -texel.y)).r;
    float h_d = texture(swe_texture, uv + vec2(0.0, texel.y)).r;
    
    // 世界空間梯度
    float world_texel = sea_size / float(textureSize(swe_texture, 0).x);
    float dx = (h_l - h_r) / (world_texel * 2.0);
    float dz = (h_u - h_d) / (world_texel * 2.0);
    
    return normalize(vec3(dx, 1.0, dz));
}

void fragment() {
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float depth = max(water_surface_y - world_pos.y, 0.0);
    
    // ★ 水面低於地面 → 沒有水 → 顯示乾燥地面，無焦散
    if (depth <= 0.01) {
        ALBEDO = sand_color.rgb;
        ROUGHNESS = 0.9;
        METALLIC = 0.0;
    } else {
    // === Beer-Lambert 吸收 ===
    vec3 transmittance = exp(-water_extinction * depth);
    
    // === 深度模糊 ===
    float blur_factor = 1.0 / (1.0 + depth * depth_blur_rate);
    
    // === ★ 水面法線→焦散 UV 偏移 (HPWater CausticCompute 核心) ===
    // 從 SWE 高度圖讀取水面法線
    vec3 water_normal = sample_water_normal(world_pos.xz);
    
    // Snell's law 折射 (HPWater: eta = 1/1.33)
    vec3 light_dir = normalize(light_direction);
    const float eta = 1.0 / 1.33;
    vec3 refracted_actual = refract(light_dir, water_normal, eta);
    vec3 refracted_flat = refract(light_dir, vec3(0.0, 1.0, 0.0), eta);
    
    // 只取法線擾動的差異→投影到海底平面的 UV 偏移
    vec3 refract_delta = refracted_actual - refracted_flat;
    vec2 wave_offset = refract_delta.xz * depth * wave_refract_strength;
    
    // === 組合 UV ===
    vec2 uv = world_pos.xz + wave_offset;
    float t = TIME * caustic_speed;
    
    // === 級聯焦散 (3 層) × 深度模糊 ===
    float large  = water_caustic(uv * 0.3 * blur_factor, t * 0.3);
    float medium = water_caustic(uv * 0.7 * blur_factor, t * 0.5 + 1.7);
    float small_c = water_caustic(uv * 1.4 * blur_factor, t * 0.8 + 3.2);
    
    float detail_fade = exp(-depth * 0.5);
    float cascade = large * 0.35 + medium * 0.45 * (0.3 + 0.7 * detail_fade) + small_c * 0.2 * detail_fade;
    
    // === 色散 (HPWater: eta ± offset per channel) ===
    vec2 disp_dir = normalize(uv + 0.001) * chromatic_dispersion * blur_factor;
    float caust_r = water_caustic((uv + disp_dir) * 0.7 * blur_factor, t * 0.5 + 1.7);
    float caust_g = medium;
    float caust_b = water_caustic((uv - disp_dir) * 0.7 * blur_factor, t * 0.5 + 1.7);
    
    vec3 caustic_rgb = vec3(
        caust_r * 0.45 + large * 0.35 + small_c * 0.2 * detail_fade,
        caust_g * 0.45 + large * 0.35 + small_c * 0.2 * detail_fade,
        caust_b * 0.45 + large * 0.35 + small_c * 0.2 * detail_fade
    );
    
    // === 深度衰減 + 吸收 ===
    float depth_fade = smoothstep(8.0, 0.2, depth);
    caustic_rgb *= depth_fade * caustic_intensity * transmittance;
    
    // === 基底色深度著色 ===
    vec3 base = sand_color.rgb * transmittance;
    vec3 scatter = vec3(0.03, 0.12, 0.22) * (1.0 - transmittance.b);
    base += scatter;
    
    // === 焦散帶淡藍色調 ===
    ALBEDO = base + caustic_rgb * vec3(0.7, 0.85, 1.0);
    ROUGHNESS = 0.85;
    METALLIC = 0.0;
    } // end else (depth > 0.01)
}
