# NewWaterSystem (Pure Ocean)

這是一個精簡、模組化且高效的海洋系統，專注於純粹的水體模擬與天氣交互，移除了所有船隻與舊物理邏輯。

## 📂 目錄結構 (Directory Structure)

```
NewWaterSystem/
├── 📁 scenes/               # 預製場景
│   └── main_ocean.tscn      # [啟動] 標準海洋場景
├── 📁 scripts/              # 核心腳本
│   ├── WaterManager.gd      # (class OceanWaterManager) 核心管理器
│   └── CameraController.gd  # 調試用自由相機
├── 📁 shaders/              #著色器
│   ├── 📁 compute/          # GPU 計算核心 (SWE/天氣)
│   │   ├── water_interaction.glsl  # 淺水方程求解器
│   │   └── Vortex.glsl             # 漩渦效果
│   └── 📁 surface/          # 視覺渲染
│       └── ocean_surface.gdshader  # 海洋表面材質 (含 Gerstner+PBR)
└── 📁 resources/            # 資源文件 (材質/貼圖)
```

## 🚀 快速開始 (Quick Start)

1.  打開 `NewWaterSystem/scenes/main_ocean.tscn`。
2.  按 **F6** 運行場景。
3.  **操作控制**:
    *   **W/A/S/D**: 水平移動
    *   **Q/E**: 垂直升降
    *   **滑鼠右鍵拖曳**: 旋轉視角
    *   **滑鼠左鍵點擊**: 在水面生成漣漪
    *   **R 鍵**: 重置模擬

## 🛠️ 核心組件說明 (Core Components)

### 1. OceanWaterManager (`scripts/WaterManager.gd`)
這是系統的大腦。請注意 Class Name 已改為 `OceanWaterManager` 以避免衝突。

*   **功能**:
    *   管理 Gerstner 波浪參數 (風向、波長、陡度)。
    *   調度 Compute Shader 執行淺水模擬 (SWE)。
    *   處理交互事件 (漣漪、漩渦)。
*   **關鍵屬性 (Inspector)**:
    *   `Grid Res`: 模擬網格解析度 (預設 128)。
    *   `Sea Size`: 海洋平面物理尺寸。
    *   `Colors`: 深水、淺水、泡沫顏色配置。
    *   `Wind & Waves`: 控制波浪形態。

### 2. Ocean Surface Shader (`shaders/surface/ocean_surface.gdshader`)
這是系統的臉面。

*   **特性**:
    *   **Hybrid Displacement**: 結合 Gerstner (大浪) + SWE (交互漣漪)。
    *   **PBR Rendering**: 完整的物理基礎渲染 (金屬度、粗糙度、Fresnel)。
    *   **Advanced Foam**: 基於 Jacobian 行列式與深度混合的白沫系統。
    *   **Detail Normals**: 雙層法線貼圖提供微細節。

### 3. Compute Shaders (`shaders/compute/*.glsl`)
這是系統的心臟。

*   `water_interaction.glsl`: 求解淺水方程 (SWE)，計算波傳播與衰減。
*   `Vortex.glsl`: 生成物理精確的漩渦流場與高度場。

## 📦 API 參考 (API Reference)

若要從其他腳本控制海洋，請獲取 `OceanWaterManager` 實例：

```gdscript
@onready var ocean = get_node("/root/Main/WaterManager") as OceanWaterManager

# 1. 獲取特定位置波浪高度 (用於浮力)
var height = ocean.get_wave_height_at(global_position)

# 2. 觸發交互漣漪
# pos: 世界座標, strength: 強度, radius: 半徑 (米)
ocean.trigger_ripple(pos, 50.0, 2.0)

# 3. 生成漩渦
ocean.trigger_vortex(pos, 1000.0, 15.0)
```

## ⚠️ 注意事項

*   **Autoload**: 本系統不需要 Autoload。直接在場景中使用 `WaterManager` 節點即可。
*   **Vortex**: 目前 `Vortex.glsl` 已包含在目錄中，可通過擴展 `WaterManager` 的 `_run_compute` 函數來調度它 (目前代碼預設調度 SWE)。
