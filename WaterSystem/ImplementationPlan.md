# 水體交互升級與優化計畫 (Water Interaction Upgrade Plan)

你的分析非常精準。目前的系統僅完成了基礎的「頂點位移（彈力布）」，缺乏與環境的真實互動。要達成「海浪拍打岩石」的質感，我們將分階段執行以下優化：

## 階段一：視覺層 - 深度接觸泡沫 (Visual Layer - Depth Foam)
**目標**：讓水面與任何物體（岩石、島嶼）接觸的邊緣產生自然的白色泡沫，消除「穿模感」。

- **技術原理**：利用 Godot 的 `depth_texture` 計算水面像素與後方物體像素的深度差 (`Linear Depth Difference`)。
- **實作細節**：
    - 優化 Shader 中的 `depth_fade` 邏輯，不僅用於透明度淡出，更要用於「泡沫混合」。
    - 加入 `contact_foam_threshold` 參數，在深度差極小（例如 < 0.5m）時強制顯示泡沫顏色。
    - 疊加 `Noise` 紋理，讓接觸邊緣不是死板的線條，而是有機的破碎狀。

## 階段二：起伏修正與碎浪優化 (Wave Irregularity & Crest Foam)
**目標**：打破目前的「過於規律」感，並修正浪尖泡沫的視覺效果。

- **波形修正**：
    - 混合多層不同頻率與方向的 Gerstner 波（目前已有，但參數需調校，增加隨機性）。
    - 引入「領域扭曲 (Domain Warping)」，用低頻噪聲干擾波浪的 UV，使波浪走勢更蜿蜒。
- **浪尖泡沫 (Crest Foam)**：
    - 基於波浪高度 (`Vertex Height`) 與 雅可比行列式 (`Jacobian` / 尖銳度) 來判斷泡沫生成區。
    - 確保泡沫只出現在「最高且最尖」的地方，並隨著波浪消散。

## 階段三：特效層 - 碎浪粒子系統 (VFX Layer - Splash Particles)
**目標**：當波浪「撞擊」時產生實體感的水花，增加衝擊力。

- **資產創建**：
    - `SplashParticles.tscn`: 使用 `GPUParticles3D`。
    - **風格**：Low-Poly 方塊或四面體 (Tetrahedron)，半透明材質。
    - **物理**：啟用 Particle Collision，讓水花能沿著岩石滾落。
- **觸發邏輯 (WaterManager)**：
    - 在岩石周圍設置 `RayCast3D` 或 `ShapeCast3D` 向下偵測水面高度。
    - 當 `(水面高度 - 岩石邊緣高度) > 閾值` 時，播放粒子效果與音效。

## 階段四：邏輯層 - 動態漣漪 (Logic Layer - Dynamic Ripples) (進階)
**目標**：物體落水或互動產生的局部波紋。

- **實作**：
    - 建立 `RippleViewport` (2D SubViewport)。
    - 當物體互動時，在 Viewport 的對應 UV 位置繪製「高度筆刷」。
    - 將此 Viewport Texture 傳入 Shader，疊加在頂點位移上。

---

## 執行順序

1.  **Shader 優化 (即刻執行)**：
    - [x] 修正深度偵測，實作「接觸邊緣泡沫」。
    - [x] 微調波浪參數，增加不規則感 (Domain Warping)。
    - [x] 改進浪尖泡沫的混合算法。
2.  **粒子系統 (待命)**：
    - [ ] 建立 `Particles` 場景。
    - [ ] 撰寫簡單的觸發腳本。

我們將優先處理 **Shader 層面** 的「接觸泡沫」與「自然感」，這是最直接的視覺提升。
