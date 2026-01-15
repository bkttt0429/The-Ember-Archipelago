# 天氣系統實作計畫 (Weather System Implementation Plan)

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
