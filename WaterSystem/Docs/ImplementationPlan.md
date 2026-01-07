# 水體系統優化實施計畫 (COMPLETED)

本計畫旨在透過一系列針對性的改進，提升現有風格化水體系統的視覺表現與物理互動感。

## 階段一：視覺層 - 深度接觸泡沫 (Depth Contact Foam) (已完成)
**目標**：讓水體與岸邊或物體交接處產生自然的泡沫邊緣，增強體積感。

*   [x] **Shader 升級**：
    *   [x] 引入 Depth Texture 讀取功能 (`hint_depth_texture`)。
    *   [x] 計算 Linear Depth 與 Vertex World Position 的差異。
    *   [x] 實作基於深度的混合邏輯，在淺水區顯示泡沫顏色。
    *   [x] 加入 Noise 紋理進行邊緣擾動，避免泡沫邊緣過於生硬直白。

## 階段二：波浪生成 - 不規則性與波峰泡沫 (Irregularity & Crest Foam) (已完成)
**目標**：打破正弦波的規律感，創造更像海洋的混亂波面，並在浪尖產生動態泡沫。

*   [x] **波浪算法優化**：
    *   [x] 在 Shader 中疊加多層不同頻率與方向的 Gerstner 波 (目前僅有單層正弦波)。
    *   [x] 引入 Domain Warping (座標扭曲) 技術，使波浪形狀更自然扭曲。
    *   [x] 同步更新 `WaterManager.gd` 中的 CPU 端波浪計算公式，確保物理浮力與視覺一致。
*   [x] **波峰泡沫 (Crest Foam)**：
    *   [x] 根據頂點位移的高度 (`v_height`) 計算泡沫遮罩。
    *   [x] 使用 `step` 或 `smoothstep` 函數產生硬邊的動漫風格泡沫。
    *   [x] 限制泡沫僅出現在波浪最高點。

## 階段三：VFX 層 - 飛濺粒子 (Splash Particles) (已完成)
**目標**：當物體落水或波浪拍打岩石時，產生相應的飛濺特效。

*   [x] **粒子系統製作**：
    *   [x] 創建 Low-Poly 風格的水花粒子材質 (Billboard 或 幾何體)。
    *   [x] 製作 `SplashParticles.tscn` 場景，包含發射一次性的爆發效果。
*   [x] **互動觸發器**：
    *   [x] 編寫 `WaveSplashDetector.gd` 腳本。
    *   [x] 偵測與水面的高度差，當物體高速進入水面或被波浪吞沒時觸發粒子。
    *   [x] 將偵測器配置在測試場景的岩石周圍。

## 階段四：邏輯層 - 動態漣漪 (Dynamic Ripples) (已完成)
**目標**：物體與水面互動時產生擴散的圓形波紋。

*   [x] **Ripple Map 系統**：
    *   [x] 建立一個新的 `SubViewport` 用於計算漣漪高度場。
    *   [x] 編寫 Shader 模擬波的傳遞 (Wave Equation) 數學模型。
*   [x] **Shader 整合**：
    *   [x] 將 Ripple Map 作為紋理傳入主水體 Shader。
    *   [x] 在 Vertex Shader 中讀取 Ripple Map 並疊加到頂點位移。
    *   [x] 在 Fragment Shader 中利用 Ripple 數值調整法線，產生光影變化。
*   [x] **互動寫入**：
    *   [x] 建立 `RippleManager`，將世界座標轉換為 UV 座標。
    *   [x] 在 Viewport 中繪製「筆刷」來產生漣漪波源 (與 Splash Detector 連動)。

## 驗證與測試 (已完成)
*   [x] **測試場景搭建**：
    *   [x] 設置一個靜態岩石 (用於測試接觸泡沫與持續飛濺)。
    *   [x] 設置一個浮動方塊 (用於測試浮力與動態漣漪)。
*   [x] **性能檢查**：確保 Shader 複雜度在可接受範圍，且 CPU 物理同步無誤。

---
**狀態更新**：
- 所有階段均已實作並經過測試。
- 水體系統現在具備：
  1.  **物理同步波浪** (WaterManager <-> Shader)。
  2.  **視覺深度泡沫** (Contact Foam)。
  3.  **動態互動** (Splash Particles + Dynamic Ripples)。
  4.  **硬邊 Low-Poly 風格**。
- 技術報告已產出至 `WaterSystem/TechnicalReport_WaterOptimization.md`。
