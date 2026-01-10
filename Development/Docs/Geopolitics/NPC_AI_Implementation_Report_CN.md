# NPC AI 與地緣政治系統實作報告

**日期**: 2026-01-10
**狀態**: 已完成 (Core Implementation Completed)
**文件位置**: `Development/Scripts/Systems/Geopolitics/NPCAISYSTEM.cpp`

---

## 1. 核心開發概況
本階段開發已將「個體 AI」擴展為具備「派系特徵」與「物理感知」的智慧代理人系統。透過 ECS 架構與事件總線的結合，實現了從物理模擬（如斷裂、水位）到社會行為（如救援、拾荒）的連鎖反應。

## 2. 實作細節

### 2.1 派系組件與需求 (Phase 1)
將派系特色轉化為數據驅動的組件，定義了三個主要派系的生存需求：
- **核心結構 (`FactionComponent`)**: 
  - `Syndicate` (鋼鐵兄弟會)
  - `Covenant` (漂流木公約)
  - `Tidebound` (深淵陣營)
- **資源需求 (`ResourceNeeds`)**:
  - `Coal` (煤炭): 鋼鐵兄弟會的動力來源。若 `< 20` 觸發緊急貿易邏輯。
  - `Scrap` (廢料): 漂流木公約的建材。
  - `Essence` (精華): 深淵陣營的生命源。
- **物理生存 (`BuoyancyComponent`)**:
  - 實作了浮力與生命值的掛鉤。
  - 當浮力 `< 20%` 時，AI 強制進入 `Sinking` (下沉) 狀態，模擬船隻損毀後的反應。

### 2.2 事件總線 2.0 (Phase 2)
建立了 `WorldEventBus`，作為物理世界與 AI 決策的橋樑，支援以下事件類型：
- **`StructuralFailure` (結構斷裂)**: 當船體結構發生物理斷裂時廣播。
- **`HarpoonEvent` (魚叉攻擊)**: 用於觸發戰鬥反應。
- **`FloodingAlarm` (水位警報)**: 來自感測器的數據。
- **`DistressSignal` (求救訊號)**: 派系內部的通訊。

### 2.3 邏輯橋接系統 (Phase 3)
實作了 `LogicBridgeSystem`，解決「玩家裝置如何影響 AI」的問題：
- **傳感器整合**: 允許玩家設置的 `Sensor` (如水位計) 當數值超過閾值時，自動轉發為 `WorldEvent`。
- **應用場景**: 當玩家船艙進水 -> 水位計觸發 -> 發送 `FloodingAlarm` -> AI 收到後切換至 `DamageControl` (損管) 狀態。

### 2.4 派系決策邏輯 (Phase 4)
在 `Agent::decide_next_action` 中實作了差異化的 Utility AI：

| 派系 | 觸發條件 (Trigger) | 反應行為 (Behavior) |
|:---:|:---|:---|
| **鋼鐵兄弟會 (Syndicate)** | 煤炭不足 (`Coal < 20`) | 優先尋找貿易站或煤礦。 |
| | 盟友求救 (`StructuralFailure`) | 若發送者為同派系，發送維修請求。 |
| **漂流木公約 (Covenant)** | 偵測殘骸 (`StructuralFailure`) | 標記為目標，執行 `Scavenge` (拾荒)。 |
| | 受到魚叉攻擊 (`HarpoonEvent`) | 觸發 `SwarmAttack` (蜂群戰術)，全體警覺度拉滿。 |
| **深淵陣營 (Tidebound)** | 高威脅感知 (`Awareness >= High`) | 執行 `Dive` (下潛) 動作以規避視線。 |

---

## 3. 代碼結構說明
所有功能均整合於 `NPCAISYSTEM.cpp`，主要類別包括：
- `Agent`: AI 主體，包含 `FactionComponent`, `ResourceNeeds`, `BuoyancyComponent`。
- `WorldEventBus`: 處理半徑範圍內的事件廣播 (`query_nearby`)。
- `LogicBridgeSystem`: 處理 `Sensor` 數據。
- `Simulation`: 測試環境，包含一個完整的 `test_geopolitics_system()` 演示函式。

## 4. 下一步建議
1. **空間分區 (Spatial Partitioning)**:
   - 目前 `query_nearby` 使用線性搜尋。建議實作 `SpatialHash` 或 `Quadtree` 系統，以支援海量實體 (Over 1000+ entities) 的高效查詢。
2. **沉船幽靈 (Ghost Recorder)**:
   - 開發 `GhostRecorder` 系統，在 `Sinking` 狀態發生時，記錄船隻的 Transform 數據，用於生成「沉船幽靈」場景。
3. **工作黑板 (Job Blackboard)**:
   - 實作「甲板手循環」，讓 AI 能夠根據疲勞度與距離，動態競標並執行如「搬運砲彈」的物理任務。
