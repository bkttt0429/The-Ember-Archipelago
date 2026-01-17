# NPC AI 與地緣政治系統實作報告

**日期**: 2026-01-10
**狀態**: 基礎功能與擴展實作已完成 (Core & Expansion Implemented)
**文件位置**: `Development/Scripts/Systems/Geopolitics/NPCAISYSTEM.cpp`

---

## 1. 核心開發概況
本階段開發已將「個體 AI」擴展為具備「派系特徵」與「物理感知」的智慧代理人系統，並完成了高性能擴展功能（空間分區、幽靈記錄、任務黑板）。透過 ECS 架構與事件總線的結合，實現了從物理模擬（如斷裂、水位）到社會行為（如救援、拾荒）的連鎖反應。

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

### 2.2 擴展功能實作 (New!)

#### A. 空間分區 (`SpatialHash`)
- **目的**: 解決海量實體下的事件查詢效能瓶頸。
- **實作**: 採用 `SpatialHash` 算法將 3D 世界劃分為網格，`query_nearby` 的複雜度從 $O(N)$ 降至接近 $O(1)$。

#### B. 沉船幽靈記錄 (`GhostRecorder`)
- **目的**: 捕捉船隻沉沒時的動態軌跡。
- **實作**: 當 `BuoyancyState` 為 `Sinking` 時，系統自動記錄 Transform 數據，為後續生成「沉船遺蹟」提供數據基礎。

#### C. 任務黑板 (`JobBlackboard`)
- **目的**: 實現派系內部的協同作業。
- **實作**: 支持任務發布（如維修請求、拾荒標記）與競標機制，AI 根據其派系偏好（如 Covenant 偏好拾荒）動態領取任務。

### 2.3 事件總線 2.0
建立了 `WorldEventBus`，作為物理世界與 AI 決策的橋樑，支援以下事件類型：
- **`StructuralFailure` (結構斷裂)**: 當船體結構發生物理斷裂時廣播。
- **`HarpoonEvent` (魚叉攻擊)**: 用於觸發戰鬥反應。
- **`FloodingAlarm` (水位警報)**: 來自感測器的數據。
- **`DistressSignal` (求救訊號)**: 派系內部的通訊。

### 2.4 邏輯橋接系統
實作了 `LogicBridgeSystem`，解決「玩家裝置如何影響 AI」的問題：
- **傳感器整合**: 允許玩家設置的 `Sensor` (如水位計) 當數值超過閾值時，自動轉發為 `WorldEvent`。

---

## 3. 代碼結構說明
所有功能均整合於 `NPCAISYSTEM.cpp`，主要類別包括：
- `Agent`: AI 主體，包含 `FactionComponent`, `ResourceNeeds`, `BuoyancyComponent`。
- `WorldEventBus`: 使用 `SpatialHash` 處理半徑範圍內的事件廣播。
- `GhostRecorder`: 記錄下沉過程中的歷史幀。
- `JobBlackboard`: 管理動態任務的分發。

## 4. 下一步建議
1. **導航網格整合 (NavMesh Integration)**:
   - 將 `Chaser` 系統與 Godot 的導航堆棧連接，實現跨島嶼的複雜路徑規劃。
2. **外交關係圖譜 (Diplomacy Graph)**:
   - 實作 `KnowledgeGraph` 類別，記錄派系間的動態友好度，影響 AI 的 `hostile_towards` 判斷。
3. **視覺反饋系統**:
   - 根據 `AwarenessState` 觸發不同的視覺特效（如驚嘆號、警戒光圈）。
4. **甲板手行為循環**:
   - 基於 `JobBlackboard` 實作更細緻的甲板內務行為（如滅火、修補漏洞）。
