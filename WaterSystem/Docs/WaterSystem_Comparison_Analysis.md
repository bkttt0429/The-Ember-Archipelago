# 現有水體系統分析與 Reference 對比報告

本報告詳細對比了目前的 `WaterSystem` 與 `Reference/godot4-oceanfft` 專案，並提出了結合兩者優點的混合方案建議。

## 1. 技術現狀對比 (Comparison)

| 特性 (Feature) | 您的系統 (Current System) | 參考方案 (OceanFFT) | 差異分析 (Analysis) |
| :--- | :--- | :--- | :--- |
| **波浪生成** | **Gerstner Waves (8層)** + **SWE (淺水方程)** | **Cascaded FFT (3層級聯快速傅立葉)** | **Current**: 強在交互性 (SWE 漣漪) 和可控性 (Gerstner)。<br>**Reference**: 強在海面的真實細節和隨機性 (JONSWAP 頻譜)。 |
| **法線計算** | **解析解 (Analytical)** + 有限差分 (SWE) | **有限差分 (Finite Difference)** | **Current**: Gerstner 解析法線極其平滑精確。SWE 使用差分。<br>**Reference**: 全局統一使用差分，雖然統一但對採樣精度要求較高。 |
| **白沫 (Foam)** | **近似 Jacobian** + 波高 + 深度 | **精確 Jacobian 行列式** + 閾值 | **Current**: 使用 `n_vec.y` 近似，雖有效但不如行列式精確。<br>**Reference**: 使用 `(Jxx * Jyy) - (Jxy * Jyx)` 準確捕捉浪尖擠壓感。 |
| **光照 (Lighting)** | 基礎 PBR + **偽焦散 (Caustics)** | PBR + **SSS (次表面散射)** + 折射 | **Reference**: 擁有 SSS (模擬光線透射浪尖) 和細膩的折射。<br>**Current**: 擁有 Reference 缺乏的焦散效果 (Caustics)。 |
| **性能 (Performance)** | **高** (頂點計算量較小) | **中** (需大量 Compute Shader 計算) | Gerstner 在 GPU 上的開銷通常顯著低於全尺寸 FFT 模擬。 |

---

## 2. 您的核心技術邏輯 (Current Technology Logic)

目前的系統 (`WaterSurface.gdshader` + `WaterWaves.gdshaderinc`) 採用 **"確定性底層 + 動態交互層"** 混合架構：

1.  **底層 (Base Layer)**: 使用 `gerstner_wave` 函數在頂點著色器中疊加 8 層正弦波變體。提供穩定的、無限重複的海洋基礎形狀。
2.  **交互層 (Interaction Layer)**: 使用 `swe_texture` (Compute Shader 計算的淺水方程) 疊加動態漣漪和障礙物波。
3.  **渲染層 (Rendering)**: 混合兩者的位移與法線，並添加基於深度和波高的白沫邏輯。

*   **優點**: 極佳的性能與交互性平衡。
*   **缺點**: 8 層 Gerstner 波浪在表現"平靜但細節豐富的洋面"或"混沌海面"時，不如 FFT 自然，容易看出重複模式。

---

## 3. 浮力系統實作分析 (Buoyancy System Analysis)

### 3.1 您的浮力實作 (Current Implementation)
**核心組件**: `BuoyantCell.gd` (分佈式單元) + `WaterManager.gd` (CPU波浪計算)

*   **原理**: **分佈式浮力單元 (Distributed Buoyancy Cells)**。
*   **流程**:
    1.  **分佈式檢測**: 物體掛載多個 `BuoyantCell`，每個獨立計算浮力。
    2.  **高度查詢**: 每個 Cell 調用 `WaterManager.get_wave_height()`。
    3.  **CPU 波浪計算**: CPU 端**完全重寫**了與 Shader 相同的 Gerstner Wave 公式，依靠相同的參數保持同步。
    4.  **物理應用**: 根據浸沒體積計算浮力 (`F = -Gravity * Volume * Density`)，並在 Cell 位置施力，自動產生力矩。

*   **優點**: 極佳的物理表現 (自然搖晃、翻滾)，CPU 直接計算波浪無需回讀，延遲低。

### 3.2 Reference (OceanFFT) 的實作
**核心組件**: `BuoyancyBody3D.gd` + `BuoyancyProbe3D.gd`

*   **原理**: **探針式浮力 (Probe-based Buoyancy)**。
*   **流程**:
    1.  **探針採樣**: 物體掛載 `BuoyancyProbe3D` 作為採樣點。
    2.  **高度查詢**: 通過 `Ocean3D` 獲取高度（通常涉及 GPU 位移貼圖的回讀或 CPU 端的 FFT 副本）。
    3.  **物理應用**: 使用簡化公式 `buoyancy = pow(depth, power)`，而非真實的體積浮力。

*   **優點**: 設置簡單，適合大量簡單物體。
*   **缺點**: 物理真實性不如體積法，且過度依賴數據同步可能引入延遲。

### 3.3 浮力總結 (Buoyancy Conclusion)
您的浮力系統在 **物理真實性** 上 **優於 Reference**。您採用的 "Cell 分佈式體積浮力" + "CPU/GPU 雙端同步公式" 是一種非常穩健且高品質的方案。

---

## 4. 結合方案建議 (Hybrid Solution Proposal)

建議採用 **"FFT 驅動視覺 + SWE 驅動交互"** 的終極混合方案。

### 階段一：材質與光照升級 (Visual Upgrade) - **推薦優先執行**
無需替換波浪公式，即可大幅提升視覺效果。

1.  **引入次表面散射 (SSS)**:
    *   移植 OceanFFT 的 SSS 算法，模擬光線穿透浪尖的效果，消除"塑膠感"。
    *   *參考*: `OceanCommon.gdshaderinc` 中的 `sss_backlight_strength` 計算。
2.  **升級白沫 (Foam)**:
    *   改進 Jacobian 計算，引入更精確的擠壓檢測，讓白沫更自然地聚集在浪尖縫隙。
3.  **優化折射 (Refraction)**:
    *   引入基於深度 (`linear_depth`) 的折射衰減，讓淺水處的折射更自然。

### 階段二：波浪驅動升級 (Simulation Upgrade) - **進階**
若追求極致真實感，可編寫 Compute Shader 執行 FFT 生成無縫循環的 **"FFT 位移貼圖"**。

1.  **替換 Gerstner**:
    *   將 `WaterWaves.gdshaderinc` 中的 8 層循環，替換為對 **FFT 位移貼圖** 的採樣。
    *   保留 `swe_texture` 的採樣和疊加邏輯。
2.  **預期結果**:
    *   獲得百萬級別多邊形細節的海面 (FFT) + 可交互的動態漣漪 (SWE)。

---
**總結**: 建議先執行 **階段一**，將 OceanFFT 的 SSS 和改進的光照邏輯整合進現有的 `WaterSurface.gdshader`，這能帶來性價比最高的視覺提升。
