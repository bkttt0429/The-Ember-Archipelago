# 高階物理水體系統 (Advanced Interactive Water System)

這是一套模組化的 Godot 4 水體解決方案，支持 GPU 漣漪模擬、Gerstner 波浪同步以及物體浮力。

## 目錄結構
- `Core/`: 包含水體管理器與核心 Shader。
- `Components/`: 包含可與水體互動的組件。

## 安裝與使用

### 1. 建立海面
將 `WaterSystemManager.gd` 掛載到場景中的一個 `Node3D` 節點上。
*   它會自動在子層級生成一個名為 `WaterPlane` 的網格。
*   您可以在 Inspector 中調整波浪大小、風力、顏色等參數。

### 2. 陸地碰撞與反射
系統會自動掃描場景中標記為「障礙物」的物體：
1.  選中您的陸地、岩石或斜坡（StaticBody3D）。
2.  將其加入名為 `WaterObstacles` 的 **Group**。
3.  啟動遊戲後，海浪會在接近這些物體時自動平壓，且波紋會產生反射。

### 3. 加入浮力
要讓物體（如木箱、小船）漂浮：
1.  為 `RigidBody3D` 增加一個 `BuoyancyProvider.gd` 子節點。
2.  在 `Probe Points` 中增加採樣點（例如物體的四個角）。
3.  系統會自動尋找場景中的 `WaterSystemManager` 並計算浮力。

## 注意事項
*   **Forward+ 模式**：本系統使用 Compute Shader 與 Screen Space Depth，建議在 Forward+ 模式下運行。
*   **效能**：模擬解析度 (`Grid Res`) 預設為 128，若需在大場景使用可適度調整 `Sea Size`。
