# 水體系統模組化開發報告 (Modular Water System Development Report)

## 1. 開發背景
本項目的水體系統最初為技術研究（Tech Research）階段的代碼，分布在 `Development/TechResearch/FluidSimulation` 目錄下。為了方便在「星海餘燼」主項目中實現大規模、跨場景的重複使用，我們執行了本次模組化重構。

## 2. 核心技術架構
模組化後的系統採用了 **「核心-組件 (Core-Component)」** 架構：

### A. 核心組件 (Core)
- **WaterSystemManager.gd**: 作為系統的單一入口點。
  - 負責 GPU RenderingDevice 的生命週期管理。
  - 運行 SWE (Shallow Water Equation) Compute Shader。
  - 執行「射線烘焙」以識別陸地碰撞。
  - 提供 CPU 端的高度查詢 API (`get_water_height_at`)。

### B. 渲染層 (Shaders)
- **WaterSurface.gdshader**: 基於 PBR 的頂點動畫著色器。
- **WaterSolver.glsl**: 處理漣漪傳遞與障礙物反射的計算著色器。
- **WaterWaves.gdshaderinc**: **關鍵技術點**。封裝了 Gerstner Wave 算法。這使得 Shader (GPU) 與 GDScript (CPU) 能共享同一套波浪邏輯，從而實現完美的物理同步。

### C. 互動組件 (Components)
- **BuoyancyProvider.gd**: 功能解耦後的浮力組件。
  - 使用者只需將此腳本掛載到 `RigidBody3D`。
  - 它會自動尋找場景中的 `WaterSystemManager` 並動態計算多點浮力。

## 3. 重大改進與修正
- **穿模壓制 (Clipping Suppression)**：在頂點著色器中引入了 `is_obstacle` 權重。當波浪接近被標記為陸地的區域時，頂點位移會自動衰減，解決了水流穿過島嶼的視覺問題。
- **自動化標記**：不再寫死節點名稱（如 `Seabed_Slope`）。現在只需將物體加入 `WaterObstacles` 群組，系統即可自動識別。
- **自動碰撞生成**：針對沒有碰撞梯度的模型，系統會在烘焙前嘗試自動生成 Trimesh 碰撞，降低了配置門檻。

## 4. 下一步計畫
- **材質細節優化**：加入法線貼圖與次表面散射 (SSS)。
- **環境集成**：集成反射探針 (Reflection Probe) 與 SSR。
- **泡沫藝術化**：進一步細化浪尖細節。
