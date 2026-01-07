# 迷霧洋流：無盡航路 (Mist Currents: The Endless Way) - 開發日誌

## 專案啟動：企劃草案整合
**日期**: 2026-01-07

### 一、 核心定位
(See previous log for details)

---

## 技術實作紀錄

### 2026-01-07: 卡通水面 Shader (Toon Water Shader)
**風格選定：硬邊幾何 (Hard-Edged Geometry)**
*   **幾何與細節**: 低 (最簡單) / 極低
*   **視覺動態**: 極高 (閃爍感強)
*   **核心技術**: Flat Shading, Vertex Displacement

已建立基礎 `stylized_water.gdshader`，位於 `WaterSystem/` 目錄。

**實作功能：**
* **渲染模式**：`render_mode unshaded`，移除 PBR 光影，完全由 Shader 控制色彩。
* **色塊化 (Color Banding)**：
    * 使用 `step(color_step_height, wave_height)` 區分 `deep_color` 與 `mid_color`。
    * 提供 `uniform` 參數可於編輯器調整顏色閾值。
* **泡沫邊緣 (Foam Line)**：
    * 利用 `depth_texture` 計算像素深度差。
    * 當深度差小於 `foam_thickness` 時繪製白色泡沫。

**待辦事項：**
* [ ] 整合 Vertex Shader 的 FFT 位移邏輯。
* [ ] 實作動態尾浪 (Wake) 系統。

### 2026-01-07: 水物理與海洋工程系統 (Marine Engineering System)

我們成功整合了兩套不同的開源技術，創造出一個既具備「像素風格視覺」又擁有「擬真體積浮力」的混合系統。

#### 1. 核心架構 (Core Architecture)
系統由三個主要層級組成，透過全域單例 (Singleton) 進行同步：

*   **視覺層 (GPU)**: 負責渲染水面、光影、泡沫與波浪動畫。
*   **物理層 (CPU)**: 負責計算物體在波浪中的浮力、水阻力與重力。
*   **同步層 (Bridge)**: `WaterManager` (Autoload) 確保 GPU 的波浪視覺與 CPU 的物理計算完全一致。

#### 2. 視覺渲染 (Visual Rendering)
基於 **Taillight Games - Godot 4 Pixelated Water** 的技術移植。

*   **Shader**: `stylized_water.gdshader` (移植自 `64-water-intense.gdshader`)。
*   **波浪生成 (Wave Generation)**:
    *   使用 **Vertex Displacement (頂點位移)** 技術。
    *   波形由兩張不同頻率與速度的 Noise Texture (噪聲貼圖) 疊加而成，而非傳統的 Sin/Gerstner 波。
*   **Pixelation**: 透過 `round_to_pixel` 函數在 Shader 中針對 UV 進行量化，產生像素化的鋸齒邊緣風格。
*   **泡沫系統 (Foam Projection)**:
    *   採用 **Viewport Projection** 技術。
    *   場景中有一個專屬的 `SubViewport` 和 `FoamCamera` (正交投影，由上往下拍)。
    *   任何標記為 Layer 2 的物件（如船尾的白色浪花 Mesh）會被拍進一張 Texture，再即時投影到水面上顯示為泡沫。
*   **網格優化**: 使用高細分平面的 `PlaneMesh` (50x50 大小, 400x400 細分) 以支撐精細的波浪起伏。

#### 3. 物理模擬 (Physics Simulation)
基於 **Godot Ocean Waves Buoyancy** 的技術移植。

*   **浮力原理 (Buoyancy)**:
    *   **體積法 (Volumetric)**: 不僅僅是判斷點的高度，而是計算 Cell (浮力單元) 沒入水中的體積百分比。
    *   公式: $F_{buoyancy} = \rho \cdot V_{submerged} \cdot -g$ (阿基米德原理)。
    *   **優勢**: 物體會根據形狀產生正確的翻轉力矩 (Torque)，能模擬船艙進水側傾、頭重腳輕等複雜動態。
*   **組件構成**:
    *   `MassCalculation.gd`: 掛載於 `RigidBody3D` (船體)。負責計算整船質量、慣性矩與水阻力 (Drag)。
    *   `BuoyantCell.gd`: 掛載於子 `MeshInstance3D`。代表船身的一個「氣室」或「木塊」，負責產生該局部的浮力。

#### 4. 關鍵同步技術 (The "Secret Sauce")
這原本是兩套不相容的系統（一套用 Noise，一套用 Gerstner 波），我們透過以下方式解決了同步問題：

*   **CPU 端數學重現 (CPU-Side Recreation)**: 我們在 `WaterManager.gd` 中使用 `FastNoiseLite` 完全重寫了 Shader 的頂點位移邏輯。
*   **參數映射 (Parameter Mapping)**: Shader 中的 Noise Texture 被轉換為 CPU 端的具體 Noise Seed 與 Frequency 參數。
*   **直接採樣 (Direct Sampling)**: 物理運算時，不使用 GPU 回讀 (Readback)，而是直接在 CPU 根據物體座標 `(x, z)` 和同步時間 `_time` 計算水面高度。這保證了百萬個物理單元的高效運算而無需 GPU 通訊開銷。

### 2026-01-07: 系統修復與優化 (System Fixes & Optimization)
**Shader 編譯錯誤修復**
*   **問題**: `stylized_water.gdshader` 出現多個變數未定義與函數簽章不匹配錯誤，導致與 `WaterManager` 的同步失效。
*   **解決方案**:
    1.  **Varying 變數**: 補回缺失的 `varying mat4 camera_mix` 宣告，修復 Fragment Shader 中的矩陣運算。
    2.  **函數簽章**: 修正 `sample_ripple_noise` 的呼叫參數，移除多餘的 `sampler2D` 傳入（直接使用全域 uniform）。
    3.  **代碼清理**: 移除 `vertex()` 函數末段殘留的無效代碼區塊（含重複定義的變數與未定義引用），確保編譯器正確解析。
*   **狀態**: Shader 編譯成功，水面渲染恢復正常。

**腳本驗證**
*   確認 `WaterManager.gd` 中 `noise1`, `noise2`, `_time` 等關鍵變數已正確宣告並初始化，消除了編輯器的 Parse Error。
