shader_type spatial;

// 渲染設定：雙面渲染(看到浪管內部)、取消背面剔除
render_mode cull_disabled, specular_schlick_ggx;

uniform float time_scale = 1.0;
uniform float wave_height = 2.0;
uniform float steepness = 0.8; // 0.0 ~ 1.0，越接近 1 越尖
uniform vec2 wave_direction = vec2(1.0, 0.5); // 波浪行進方向

// 模擬參數
uniform float breaking_threshold = 0.6; // 超過這個高度開始捲曲
uniform float curl_force = 1.5; // 捲曲的力度

// 貝茲曲線計算函數 (The Curl Logic)
// t: 0.0 到 1.0 的進程
vec3 cubic_bezier(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
    float u = 1.0 - t;
    float tt = t * t;
    float uu = u * u;
    float uuu = uu * u;
    float ttt = tt * t;
    
    // 標準三次貝茲公式
    vec3 p = uuu * p0; 
    p += 3.0 * uu * t * p1; 
    p += 3.0 * u * t * t * p2; 
    p += ttt * p3; 
    return p;
}

void vertex() {
    float time = TIME * time_scale;
    
    // 1. 基礎 Gerstner 波計算 (Base Wave)
    vec2 d = normalize(wave_direction);
    // 計算波的相位 (Phase)
    float f = dot(d, VERTEX.xz) - time; 
    
    // 預計算一些物理量
    float sin_f = sin(f);
    float cos_f = cos(f);
    
    // 基礎位移 (尚未捲曲)
    vec3 displacement = vec3(0.0);
    
    // --- 步驟 1: 淺化 (Shoaling) ---
    // 這裡我們簡單模擬：當波峰出現時(cos_f > 0)，高度非線性增加
    // Line 470: z_base *= shoaling_factor
    float shoaling_factor = 1.0;
    if (cos_f > 0.0) {
        shoaling_factor = 1.0 + (cos_f * 0.5); // 波峰處變高
    }
    float current_height = wave_height * shoaling_factor;
    
    // Gerstner 基礎公式
    displacement.x = (steepness * current_height * d.x * cos_f);
    displacement.z = (steepness * current_height * d.y * cos_f);
    displacement.y = current_height * sin_f;
    
    // --- 步驟 2: 前傾 (Asymmetry) ---
    // Line 478: 讓波峰 (High Y) 的 X/Z 位移比波谷更多
    // 這樣波浪正面會變陡，背面變緩
    float asymmetry_factor = max(0.0, displacement.y); // 只影響海平面以上
    vec2 forward_push = d * asymmetry_factor * 0.8; 
    displacement.x -= forward_push.x; // 減去是因為要往行進方向"推"
    displacement.z -= forward_push.y;

    // --- 步驟 3: 捲曲 (The Curl - Method 3) ---
    // Lines 495-515: 檢測是否達到破碎臨界點
    
    // 我們定義一個 "捲曲係數 t"，當波浪很高時觸發
    // 將 displacement.y 映射到 0~1 的範圍用作 t
    float t = smoothstep(breaking_threshold, wave_height * 1.5, displacement.y);
    
    if (t > 0.01) {
        // 定義貝茲曲線的四個控制點 (相對於原本的頂點位置)
        // 控制點調整：依照圖 1 紅色箭頭軌跡 (上 -> 前 -> 捲入)
        vec3 p0 = displacement;
        
        // P1: 強力抬升 (Lift) - 順著斜率向上衝
        vec3 p1 = displacement + vec3(0.0, 1.8, 0.0) * curl_force; 
        
        // P2: 向前抛射 (Throw) - 形成寬闊的浪唇頂部
        // d 是波浪前進方向
        vec3 p2 = displacement + vec3(d.x, 1.2, d.y) * curl_force * 1.2; 
        
        // P3: 向內捲回 (Tuck) - 指向浪管深處，形成 C 字
        // 降低高度 (y = -1.5) 並往回縮一點 (d * 0.4 而非 1.0)
        vec3 p3 = displacement + vec3(d.x * 0.5, -2.0, d.y * 0.5) * curl_force; 
        
        // 混合原始形狀與捲曲形狀
        displacement = mix(displacement, cubic_bezier(p0, p1, p2, p3, t), t * t);
    }

    // 最終應用位移
    VERTEX += displacement;
    
    // --- 難點：法線修復 ---
    // 因為我們劇烈改變了頂點位置，預設法線會錯誤。
    // 在真實專案中，你需要透過 d(Vertex)/dx 和 d(Vertex)/dz 重新計算 Binormal 和 Tangent。
    // 這裡做一個簡單的 hack：
    NORMAL = normalize(vec3(-displacement.x, 1.0, -displacement.z)); 
}

void fragment() {
    // 簡單的上色，方便觀察
    ALBEDO = vec3(0.0, 0.3, 0.5); // 深藍色
    ROUGHNESS = 0.1;
    
    // 根據高度加一點泡沫色
    if (VERTEX.y > wave_height * 0.8) {
        ALBEDO = mix(ALBEDO, vec3(0.9), 0.7); // 浪尖變白
    }
}
