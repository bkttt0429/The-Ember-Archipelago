# 星海餘燼 實作計畫 (Implementation Plan)

---

# 🌊 桶浪材質修復計畫 (Barrel Wave Material Fix - 2天速成方案)

**目標檔案**：`NewWaterSystem/Core/Shaders/Surface/barrel_wave.gdshader`

## 📋 修復檢查清單

- [x] Step 1：修復透明度（30分鐘）
- [x] Step 2：增強SSS次表面散射（1小時）
- [x] Step 3：修正法線流動（1小時）
- [x] Step 4：添加內部高光（30分鐘）
- [x] Step 5：泡沫分層（1小時）
- [x] Step 6：顏色深度梯度（30分鐘）
- [x] Step 7：非均勻曲面擾動（30分鐘）

---

## Step 1：修復透明度（30分鐘）

### 問題
水體過於透明，像玻璃而非真實的水。

### 需要新增的 Varying 變數（Vertex Shader）
```glsl
varying float v_water_thickness;
varying float v_edge_blend;
```

### 找到（Fragment）：
```glsl
ALPHA = (0.85 + foam_mask * 0.15) * alpha_mult;
```

### 改為：
```glsl
// 基於實際水體厚度的不透明度
float thickness_opacity = 0.45 + v_water_thickness * 0.15;  // 厚水更不透明
float edge_fade = smoothstep(0.0, 0.25, v_edge_blend);      // 邊緣柔和渐變

// 底部區域（arc < 0.5）增加不透明度
float depth_boost = smoothstep(0.5, 0.0, v_arc_position) * 0.2;

float base_alpha = (thickness_opacity + depth_boost) * edge_fade;
ALPHA = clamp(base_alpha + foam_mask * 0.15, 0.3, 0.98) * alpha_mult;  // 泡沫也能增加不透明度
```

---

## Step 2：增強SSS次表面散射（1小時）

### 問題
缺乏真實水體的透光感，陽光穿透效果不足。

### 找到：
```glsl
vec3 sss_contribution = sss_color.rgb * sss_strength * sss_mask * (0.2 + 0.8 * sss_view);
```

### 改為：
```glsl
// 1. 計算太陽方向（簡化版，假設從右上方照射）
vec3 sun_dir = normalize(vec3(0.6, 0.8, 0.3));

// 2. 計算背光透射（太陽光從背後穿透水體）
float sun_transmission = pow(max(dot(sun_dir, -final_normal), 0.0), 1.5);

// 3. 薄水層強散射（唇部區域）
float thinness_factor = 1.0 / max(v_water_thickness, 0.1);  // 越薄越亮
float sss_intensity = sss_strength * 3.0 * thinness_factor;

// 4. 顏色隨厚度變化（薄=青綠，厚=深藍）
vec3 thin_color = vec3(0.2, 0.9, 0.8);   // 青綠色
vec3 thick_color = vec3(0.0, 0.3, 0.6);  // 深藍色
vec3 sss_final_color = mix(thick_color, thin_color, thinness_factor * 0.5);

// 5. 組合所有因素
vec3 sss_contribution = sss_final_color * sss_intensity 
                    * (0.3 + 0.7 * sun_transmission)  // 背光面更亮
                    * sss_mask 
                    * (0.5 + 0.5 * sss_view);
```

### 更新 EMISSION：
```glsl
EMISSION += sss_contribution * (1.0 - foam_mask);
```

---

## Step 3：修正法線流動（1小時）

### 問題
法線沿世界座標流動，而非沿著桶浪曲面流動。

### 需要新增的 Varying 變數：
```glsl
varying vec3 v_tangent;
varying vec3 v_wave_normal;
```

### 找到：
```glsl
vec2 uv1 = v_world_pos.xz * normal_tile + TIME * normal_speed;
vec2 uv2 = v_world_pos.zx * normal_tile * 1.2 - TIME * normal_speed * 0.7;
```

### 改為：
```glsl
// 1. 使用切線空間UV（沿著桶浪曲面流動）
vec3 tangent_world = normalize(v_tangent);
vec3 binormal_world = normalize(cross(v_wave_normal, tangent_world));

// 2. 投影世界座標到切線空間
float u_tangent = dot(v_world_pos, tangent_world);
float v_binormal = dot(v_world_pos, binormal_world);

// 3. 生成UV（考慮曲率）
vec2 curved_uv = vec2(u_tangent, v_binormal) * normal_tile * 0.1;

// 4. 流速隨弧形位置變化（唇部更快）
float flow_speed_mult = mix(0.5, 2.5, smoothstep(0.3, 0.9, v_arc_position));

// 5. 添加時間偏移
vec2 flow_offset = normalize(v_tangent.xz + vec2(0.001)) * TIME * normal_speed * flow_speed_mult;
vec2 uv1 = curved_uv + flow_offset;
vec2 uv2 = curved_uv * 1.2 - flow_offset * 0.7;
```

---

## Step 4：添加內部高光（30分鐘）

### 目的
模擬光線在水體內部的反射（類似玉石效果）。

### 在 EMISSION 部分添加：
```glsl
// 模擬光線在水體內部的反射（類似玉石效果）
float view_tangent = abs(dot(view_dir, tangent_world));
float internal_highlight = pow(view_tangent, 8.0)           // 窄高光
                          * smoothstep(0.4, 0.7, v_arc_position)  // 只在中段出現
                          * (v_water_thickness / 3.0);            // 厚度調制

EMISSION += vec3(0.4, 0.7, 0.9) * internal_highlight * 0.5 * (1.0 - foam_mask);
```

---

## Step 5：泡沫分層（1小時）

### 問題
單一泡沫層太單調，缺乏真實感。

### 找到：
```glsl
float foam_mask = smoothstep(0.5, 1.0, v_arc_position) * foam_amount;
foam_mask += fresnel * 0.2;  // 邊緣也有泡沫
foam_mask = clamp(foam_mask * foam_noise_val * 2.0, 0.0, 1.0);
```

### 改為：
```glsl
// Layer 1: 底部翻滾泡沫（大塊、慢速）
float bottom_foam = 0.0;
if (v_arc_position < 0.4) {
    vec2 bottom_uv = v_world_pos.xz * 0.2 + TIME * 0.01;
    float bottom_noise = texture(foam_noise, bottom_uv).r;
    bottom_foam = smoothstep(0.6, 0.9, bottom_noise) * (0.4 - v_arc_position) * 2.0;
}

// Layer 2: 唇部爆炸泡沫（小塊、高速）
float lip_foam = 0.0;
if (v_arc_position > 0.6) {
    vec2 lip_uv = v_world_pos.xz * 0.8 + TIME * 0.05;  // 更高頻率
    float lip_noise = texture(foam_noise, lip_uv).r;
    float explosion_mask = smoothstep(0.6, 0.95, v_arc_position);
    lip_foam = pow(lip_noise, 0.5) * explosion_mask * 0.9;
}

// Layer 3: 邊緣霧化（基於 Fresnel）
float mist_foam = fresnel * 0.2 * smoothstep(0.7, 1.0, v_arc_position);

// 組合
float foam_mask = clamp(bottom_foam + lip_foam + mist_foam, 0.0, 1.0);
```

---

## Step 6：顏色深度梯度（30分鐘）

### 問題
顏色過渡不夠自然，缺乏深度感。

### 找到：
```glsl
vec3 sea_color = mix(color_deep.rgb, color_shallow.rgb, depth_factor);
```

### 改為：
```glsl
// 1. 基於厚度的顏色
float thickness_factor = clamp(v_water_thickness / 2.0, 0.0, 1.0);
vec3 thick_water_color = color_deep.rgb;
vec3 thin_water_color = color_shallow.rgb * 1.2;  // 薄水更亮

// 2. 基於弧形位置的顏色（底部暗，唇部亮）
vec3 depth_color = mix(thick_water_color, thin_water_color, 1.0 - thickness_factor);

// 3. 添加環境光貢獻（內部應該更暗）
float ao = mix(0.6, 1.0, v_arc_position);  // 底部暗 60%

vec3 sea_color = depth_color * ao;
```

---

## Step 7：非均勻曲面擾動（30分鐘）

### 問題
桶浪過於完美光滑，缺乏真實破浪的不規則性和局部擾動。

### 在 Vertex Shader `vertex()` 函數中添加：
```glsl
// 非均勻曲面擾動（真實破浪不是完美管道）
float surface_noise = texture(foam_noise, v_world_pos.xz * 0.05 + TIME * 0.01).r;
float disturbance = (surface_noise - 0.5) * 0.3 * v_arc_position;  // 唇部擾動更大

// 垂直和水平擾動
VERTEX.y += disturbance;
VERTEX.xz += v_world_normal.xz * disturbance * 0.5;

// 同步更新法線（粗略近似）
vec3 neighbor_offset = vec3(0.1, 0.0, 0.0);
float neighbor_noise = texture(foam_noise, (v_world_pos.xz + neighbor_offset.xz) * 0.05 + TIME * 0.01).r;
float slope = (neighbor_noise - surface_noise) * 0.3 * v_arc_position;
v_world_normal = normalize(v_world_normal + vec3(slope, 0.0, slope) * 0.5);
```

### Uniform 參數（可選）：
```glsl
uniform float surface_disturbance : hint_range(0.0, 1.0) = 0.3;  // 擾動強度
uniform float disturbance_scale : hint_range(0.01, 0.2) = 0.05;  // 擾動頻率
```

---

## 🧪 測試檢查點

修改後應該看到：

| # | 項目 | 預期效果 |
|---|------|----------|
| 1 | ✅ 水體厚實感 | 不再透明得像玻璃 |
| 2 | ✅ 唇部青綠色透光 | 背光時更明顯 |
| 3 | ✅ 底部翻滾泡沫 | 大塊深色泡沫 |
| 4 | ✅ 唇部白色爆炸泡沫 | 噴濺效果 |
| 5 | ✅ 法線沿曲面流動 | 不是橫向滑動 |
| 6 | ✅ 中段內部高光 | 微妙的玉石光感 |
| 7 | ✅ 曲面不規則擾動 | 真實破浪的自然感 |

---

## 📝 Mesh Generator 需要傳遞的資料

`BarrelWaveMeshGenerator.gd` 需要設置以下 UV/CUSTOM 通道：

| 通道 | 資料 | 用途 |
|------|------|------|
| UV.x | arc_position | 弧形位置 (0=後方, 1=唇部) |
| CUSTOM0.x | water_thickness | 水體厚度 |
| CUSTOM0.y | edge_blend | 邊緣混合值 |
| TANGENT | tangent vector | 切線方向 |

---
---

# ⛈️ 天氣系統實作計畫 (Weather System Implementation Plan)

為了在「星海餘燼」專案中整合這套複雜的天氣系統，我們建立了一個獨立於水面管理的架構，並透過介面與現有的 `OceanWaterManager` 通訊。

## 📁 資料夾結構：`res://WeatherSystem/`

*   **/Core/**：管理時間（晝夜）、天氣狀態機、全域風力。
*   **/VFX/**：雨水粒子、閃電 Shader、雲朵模型。
*   **/Resources/**：儲存不同天氣的數值預設計（如 `Storm.tres`, `Clear.tres`）。
*   **/Environment/**：Sky Material 與環境照明配置。

---

## 1. 核心天氣狀態規劃 (Weather States)

| 天氣狀態 | 視覺特徵 | 目標 |
| :--- | :--- | :--- |
| **晝夜循環** | 漸變色調 | 實現 24 小時光影變化，影響環境氛圍。 |
| **暴風雨** | 烏雲密閉、垂直感 | 增加海浪強度，啟動雨水與閃電特效。 |
| **龍捲風/氣旋** | 漏斗狀、旋轉感 | 觸發水面物理位移（Vortex），產生毀滅性視覺。 |

---

## 2. 五大實作模組

### ① 光照效果 (Lighting)
*   **晝夜**：透過 `WeatherController` 旋轉太陽角度，並根據時間插值（Interpolate）太陽顏色、能量。
*   **環境**：動態調整 `WorldEnvironment` 的環境光（Ambient）與天空色調（Sky Tint）。

### ② 風力效果 (Wind)
*   **全域同步**：建立 `GlobalWind` 單例，將 `current_wind_strength` 直接同步給 `OceanWaterManager`。
*   **海浪聯動**：風力增加會自動提升海浪的陡度（Steepness）與波長（Wave Length）。

### ③ 雨水效果 (Rain)
*   **粒子系統**：利用 `GPUParticles3D` 實作。
*   **強度驅動**：由 `WeatherState` 中的 `rain_intensity` 參數驅動粒子發射速率。

### ④ 雲變化與龍捲風模擬 (Clouds & Tornado)
*   **物理聯動**：龍捲風中心觸發 `WaterManager` 的 `trigger_vortex` 函數，產生實際的水面下陷。
*   **視覺實作**：使用旋轉的看板粒子（Billboard Particles）與扭曲 Shader 模擬漏斗雲。

### ⑤ 打雷 (Lightning)
*   **閃電 Shader**：在隨機位置生成高強度光束。
*   **光照閃爍**：隨機間隔快速切換 `OmniLight3D` 並同步調整環境曝光。

---

## 3. 開發腳本範例 (WeatherController)

```gdscript
# 主要職責：
# - 透過 Tween 平滑過度 WeatherState 數值
# - 同步 OceanWaterManager 的風浪參數
# - 管理晝夜時間流轉
```
