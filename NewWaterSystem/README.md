# NewWaterSystem (Pure Ocean)

這是一個精簡、模組化且高效的海洋系統，專注於純粹的水體模擬與天氣交互。

## 📂 目錄結構 (Directory Structure)

```
NewWaterSystem/
├── 📁 Core/                     # 核心模組
│   ├── 📁 Scripts/              # 核心腳本
│   │   ├── WaterManager.gd      # (class OceanWaterManager) 核心管理器
│   │   ├── BuoyancyComponent.gd # 浮力組件
│   │   ├── OceanLODManager.gd   # LOD 管理
│   │   ├── AutoSetupFoam.gd     # 泡沫自動設定
│   │   ├── 📁 Foam/             # 泡沫系統
│   │   │   ├── FoamParticleManager.gd
│   │   │   └── FoamParticleRenderer.gd
│   │   └── 📁 Waves/            # 波浪系統
│   │       └── BreakingWaveComponent.gd
│   └── 📁 Shaders/              # 著色器
│       ├── FoamParticle.gdshader      # 簡化版泡沫粒子
│       ├── SimpleBarrelTest.gdshader  # 桶浪測試
│       ├── SprayParticles.gdshader    # 噴霧粒子
│       ├── 📁 Internal/               # GPU 計算核心
│       │   ├── OceanFFT_*.glsl        # FFT 相關計算
│       │   ├── water_interaction.glsl # 淺水方程求解器
│       │   ├── water_solver_maccormack.glsl
│       │   └── FoamParticle.gdshader  # 進階版泡沫粒子
│       └── 📁 Surface/                # 視覺渲染
│           ├── ocean_surface.gdshader # 海洋表面材質
│           └── barrel_wave.gdshader   # 桶浪效果
├── 📁 Demo/                     # 演示場景
│   ├── 📁 Prefabs/              # 預製件
│   │   └── Boat.tscn
│   ├── 📁 Scenes/               # 測試場景
│   │   ├── BoatDemoLevel.tscn
│   │   ├── BreakingWaveDemo.tscn
│   │   ├── MinimalWaveTest.tscn
│   │   ├── SimpleBarrelTest.tscn
│   │   ├── SkillsDemo.tscn
│   │   └── ...
│   └── 📁 Scripts/              # Demo 專用腳本
│       ├── BoatAutoCircle.gd
│       ├── CameraController.gd
│       ├── DemoUI.gd
│       ├── FreeLookCamera.gd
│       └── ViewSwitcher.gd
├── 📁 Weather/                  # 天氣系統
│   ├── 📁 Components/
│   │   └── WeatherSource.gd
│   ├── 📁 Scripts/
│   │   └── WeatherManager.gd
│   └── 📁 Shaders/
│       ├── Vortex.glsl          # 漩渦效果
│       └── Waterspout.glsl      # 水龍捲效果
├── 📁 docs/                     # 文檔
│   ├── 📁 scripts/              # 視覺化腳本
│   │   ├── barrel_wave_viz.py
│   │   └── breaking_wave_mesh.py
│   ├── BarrelWaveSystem_Design.md
│   ├── Optimization.md
│   └── ... (設計文檔與截圖)
└── README.md
```

## 🚀 快速開始 (Quick Start)

1.  打開 `NewWaterSystem/Demo/Scenes/BoatDemoLevel.tscn` 或其他測試場景。
2.  按 **F6** 運行場景。
3.  **操作控制**:
    *   **W/A/S/D**: 水平移動
    *   **Q/E**: 垂直升降
    *   **滑鼠右鍵拖曳**: 旋轉視角
    *   **滑鼠左鍵點擊**: 在水面生成漣漪
    *   **R 鍵**: 重置模擬

## 🛠️ 核心組件說明 (Core Components)

### 1. OceanWaterManager (`Core/Scripts/WaterManager.gd`)
這是系統的大腦。Class Name 為 `OceanWaterManager`。

*   **功能**:
    *   管理 Gerstner 波浪參數 (風向、波長、陡度)。
    *   調度 Compute Shader 執行淺水模擬 (SWE)。
    *   處理交互事件 (漣漪、漩渦)。
*   **關鍵屬性 (Inspector)**:
    *   `Grid Res`: 模擬網格解析度 (預設 128)。
    *   `Sea Size`: 海洋平面物理尺寸。
    *   `Colors`: 深水、淺水、泡沫顏色配置。
    *   `Wind & Waves`: 控制波浪形態。

### 2. Ocean Surface Shader (`Core/Shaders/Surface/ocean_surface.gdshader`)
這是系統的臉面。

*   **特性**:
    *   **Hybrid Displacement**: 結合 Gerstner (大浪) + SWE (交互漣漪)。
    *   **PBR Rendering**: 完整的物理基礎渲染 (金屬度、粗糙度、Fresnel)。
    *   **Advanced Foam**: 基於 Jacobian 行列式與深度混合的白沫系統。
    *   **Detail Normals**: 雙層法線貼圖提供微細節。

### 3. Compute Shaders (`Core/Shaders/Internal/*.glsl`)
這是系統的心臟。

*   `OceanFFT_*.glsl`: FFT 海洋頻譜計算 (Init, Update, Butterfly, Displace, NormalCombine)。
*   `water_interaction.glsl`: 求解淺水方程 (SWE)，計算波傳播與衰減。
*   `water_solver_maccormack.glsl`: MacCormack 求解器實現。

### 4. Weather System (`Weather/`)
天氣效果模組。

*   `WeatherManager.gd`: 天氣狀態管理。
*   `Vortex.glsl`: 物理精確的漩渦流場與高度場。
*   `Waterspout.glsl`: 水龍捲效果。

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
*   **Demo 場景**: 所有測試場景位於 `Demo/Scenes/`，包含各種功能展示。
*   **效能優化**: 詳見 `docs/Optimization.md`。
