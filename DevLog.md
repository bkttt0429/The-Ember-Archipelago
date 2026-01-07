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
### 2026-01-07: 水體系統全面優化實作 (Comprehensive Water System Implementation)

我們完成了從簡易 Noise 水面到具備「次世代 Low-Poly 效果」與「精確物理互動」的水系統升級。

#### 1. 核心波浪代數 (Core Wave Mathematics)
*   **技術選型**: 放棄了純 Noise 隨機位移，改採 **多層 Gerstner Wave (5層疊加)**。
    *   **優勢**: 提供了具體且可預測的方向性波形、陡峭的浪尖 (Steepness) 以及自然的頂點水平移動。
*   **同步技術**: 
    *   **CPU 迭代解算器 (Iterative Solver)**: 為了解決 Gerstner 波在水平方向產生的位移，我們在 `WaterManager.gd` 實作了迭代法（3次疊代），以根據物體世界座標反求對應的波浪高度，實現了 **毫釐級的 CPU/GPU 視覺同步**。

#### 2. 進階視覺渲染 (Advanced Rendering)
*   **深度感知系統 (Depth Awareness)**:
    *   **線性深度泡沫**: 利用 `hint_depth_texture` 計算水體與幾何體的交集深度，自動在岸邊、岩石及物體交界處生成動態泡沫。
    -   **多層色帶 (Banded Color)**: 透過 `step` 函數實作淺水 (Shallow)、中層 (Mid) 與深水 (Deep) 的硬邊色彩過渡，完美符合 Low-Poly 美術風格。
*   **動態泡沫系統 (Dynamic Foam)**:
    -   **波峰泡沫 (Crest Foam)**: 根據頂點垂直位移量 (`v_height`) 加權 Noise 紋理，僅在浪尖高度產生破碎感泡沫。
    -   **尾浪投影 (Wake Projection)**: 採用 `SubViewport` 正交投影技術，將船隻運動產生的 Mesh 軌跡投影至 Shader 紋理，實現物體移動帶動的水面浪痕。

#### 3. 物理互動與 VFX (Interaction & VFX)
*   **動態漣漪 (Dynamic Ripples)**:
    -   實作了基於法線擾動與頂點位移的 **Ripple Map** 系統。利用波方程式 (Wave Equation) 在 Viewport 中模擬圓形波紋的擴散與衰減。
*   **特殊地貌與天氣互動**:
    -   **水下漩渦/水柱位移 (Waterspout)**: 透過 `waterspout_pos` 參數同時影響 Shader 位移與 `WaterManager` 物理力場，實現視覺與物理統一的下陷/旋轉效果。
*   **互動粒子 (Splash Particles)**:
    -   開發了 `WaveSplashDetector.gd`，當偵測到高速物體入水或波浪拍打岩石時，觸發 Low-Poly 風格的水花粒子。

#### 4. 系統架構結論
水系統現已轉變為一個 **數據驅動 (Data-Driven)** 的模組。透過 `WaterManager` 單例管理所有波浪參數，能確保遊戲中所有實體（玩家船隻、浮漂、岩石）在視覺波動與物理力學上保持絕對的一致性。
### 2026-01-07: 水體系統全面優化 - 第一階段實作完成

我們針對水體系統進行了深度優化，核心修復了流體動力學與同步機制。

#### 1. 水流場系統與阻力修正 (#1)
- **實作內容**: 在 `WaterManager` 引入了 `global_flow_direction` 與 `global_flow_speed`。
- **物理擬真**: 將物體的阻力計算從「絕對速度」修正為「相對速度」(`linear_velocity - water_velocity`)。
- **渦流整合**: 海龍捲 (Waterspout) 現在具備切線方向的渦流場，會帶動周圍漂浮物旋轉並向中心聚集。

#### 2. 自動化參數同步 (#2)
- **技術改進**: 在 `WaterController.gd` 實作了基於反射 (Reflection) 的參數同步系統。
- **優點**: 任何在 Shader 中新增的參數（如 `wave_c`, `flow_speed` 等）只需加入清單即可自動同步至 CPU 端，消除了手動維護導致的物理/視覺誤差。

#### 3. 視覺與美術風格強化 (#3, #9, #10)
- **視覺效果**: 調整了 `depth_band` 與顏色飽和度，增強了卡通色彩層次。
- **硬邊極致化**: 全面改採 `step()` 函數實作雙層硬邊泡沫，視覺風格更趨向經典卡通效果。
- **動態流動**: 實作了泡沫紋理的 UV 漂移，讓玩家能透過泡沫移動方向直觀判斷水流方向。

#### 4. 性能優化 (#5, #6)
- **自適應迭代**: 根據物體運動速度動態調整頂點位移迭代次數（靜止物 1 次，快速移動物 5 次），顯著降低大規模物理模擬的 CPU 開銷。
- **Ripple 系統優化**: 降低模擬解析度至 256x256，並實作了距離感知的 LOD 系統，當相機過遠時自動暫停計算。
### 2026-01-07: 水體系統全面優化 - 第二階段：視覺細節調優完成

我們針對診斷出的「水面過白」與「層次模糊」問題進行了精確調優。

#### 1. 泡沫覆蓋率精確控制 (Foam Coverage Control)
- **波峰閥值**: `foam_crest_threshold` 提升至 **2.8**，確保泡沫僅出現在波浪頂端 10-15%。
- **接觸泡沫收緊**: `foam_shore_extent` 降至 **0.2**，消除了岸邊過大的白色色塊。
- **透明度優化**: `foam_opacity` 降至 **0.6**，讓底層水色能透出，增加層次感。

#### 2. 色彩深度系統復原 (Depth Banding Recovery)
- **對比度增強**: 引入 `color_saturation` (1.5) 並更新了色彩定義：
    - **淺水**: 亮青色 (#33D9FF)
    - **深水**: 深海藍 (#001A33)
- **硬邊分層修正**: 調整 `depth_band` 閾值 (1.0, 3.0)，使淺水區更明顯且深水區更深邃，完美恢復卡通硬邊質感。

#### 3. 動態質感與硬邊優化 (Stylized Polish)
- **破碎感強化**: 泡沫 Noise UV 縮放調整為 **0.05**，視覺呈現更大塊、更具幾何感的「破碎浪」質感。
- **Fresnel 反射衰減**: 反射系數降至 **0.15**，解決了斜向視角下因反射天空導致的泛白問題。
- **動態生命週期**: 在 Shader 中實作了基於時間與高度的脈衝調製，使波峰泡沫具備自然的「閃爍與生滅」動態感。

#### 4. 系統穩定性
- 所有的視覺參數均已整合進 `WaterController` 的自動同步清單，確保編輯器中調整的效果即時映射至物理系統。
### 2026-01-07: 緊急修復與海龍捲真實感提升

#### 1. 全白畫面緊急修復 (Emergency White-Out Fix)
- **問題分析**: 由於波峰泡沫閾值 (`foam_crest_threshold`) 設置過低 (1.35)，且波高縮放 (`height_scale`) 較大，導致泡沫覆蓋率接近 100%，畫面呈現全白。
- **修正措施**: 
    - 將 `foam_crest_threshold` 提升至 **3.5**（確保僅頂端 10-15% 產生泡沫）。
    - 降低 `foam_opacity` 至 **0.4** 以增加視覺通透感。
    - 收緊岸邊泡沫範圍 (`foam_shore_extent` = 0.15)。

#### 3. 海龍捲 3D 漏斗實作 (3D Funnel Column)
- **結構化建模**: 新增了基於 Cylinder Mesh 的漏斗模型，補足了原本僅有粒子系統導致的「虛無感」。
- **頂點扭動 (Vertex Wobble)**: 在 Shader 中實作了隨時間變化的正弦波位移，讓水柱呈現有機的擺動感。
- **螺旋紋理與近景淡出**: 
    - 實作了向上攀升的螺旋雜訊紋理（Vortex Panning）。
    - 引入 `proximity_fade` 確保水柱與海面接合處自然過度，避免生硬的交錯線。
- **物理與視覺同步**: 透過 `WaterspoutForce.gd` 自動同步全域時間，確保水柱擺動與海浪波動頻率一致。
