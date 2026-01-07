# 遊戲設計規範 (Design Rules)

## 美術風格 (Art Style)

### 水面特效 (Water Visuals)
**卡通水面 Shader (Toon Water Shader)**
*   **風格類型**: 硬邊幾何 (Hard-Edged Geometry)
*   **幾何細節 (Geometry Detail)**: 低 (Low) / 極低 (Very Low) - 追求簡約感。
*   **視覺動態 (Visual Dynamics)**: 極高 (Very High) - 強烈的閃爍感與動態變化。
*   **核心技術 (Core Tech)**:
    *   Flat Shading (平面著色)
    *   Vertex Displacement (頂點位移)
    *   **資產來源**: 自製 Shader (參考 godotshaders.com, Taillight Games)。

### 光照與環境 (Lighting & Environment)
*   **天空系統 (Sky System)**:
    *   **首選**: Godot 內建 `ProceduralSkyMaterial` 或 `PhysicalSkyMaterial` (便於日夜循環與色調統一)。
    *   **備選 (風格化)**: GodotShaders.com 的動態動漫天空 (Anime Sky Shaders)。
    *   **備選 (靜態)**: Poly Haven (僅限作為 HDRI 環境光照明來源，視覺上需模糊處理)。
*   **全域光照 (GI)**:
    *   啟用 **SDFGI** (適合開放世界) 或 **VoxelGI**。
    *   環境光模式 (Ambient Light): Sky (配合自訂顏色以達成風格化效果)。

## 物理系統 (Physics System)

### 海洋工程 (Marine Engineering)
*   **浮力模型 (Buoyancy Model)**: 必須使用 **體積浮力 (Volumetric Buoyancy)**。
    *   禁止使用簡單的單點浮力 (Raycast Buoyancy)。
    *   所有大型水上載具必須支援翻轉力矩 (Torque) 運算。
*   **組件標準 (Component Standards)**:
    *   **船體 (Hull)**: 必須是 `RigidBody3D` 並掛載 `MassCalculation.gd`。
    *   **浮力單元 (Buoyant Cells)**: 使用低多邊形 Mesh (如 Cube) 模擬船體體積，掛載 `BuoyantCell.gd`。
*   **水面同步 (Water Sync)**: 
    *   任何涉及水面高度的運算 (如浮力、特效生成) 必須透過 `WaterManager.get_wave_height(global_position)` 獲取高度。
*   **參數與算法同步 (Parameter & Algorithm Sync)**:
    *   `stylized_water.gdshader` 中的 `uniform` 參數 (如 `wave_a`, `wave_speed`) 必須與 `WaterManager.gd` 中的 `@export` 變數嚴格對應。
    *   若修改 Shader 中的波浪公式 (Gerstner + Noise)，必須同時在 `WaterManager.gd` 中以 GDScript 重寫相同的數學邏輯，確保視覺與物理的一致性。
