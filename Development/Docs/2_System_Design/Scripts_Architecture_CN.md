# 腳本架構文檔 (Scripts Architecture)

**最後更新**: 2026-01-18
**狀態**: Stage 1 實作完成

---

## 1. 資料夾結構 (Directory Structure)

```
Scripts/
├── Systems/
│   └── Geopolitics/                 # 地緣政治系統
│       ├── Core/                    # 核心系統 (GDScript)
│       │   ├── FactionData.gd       # 派系資源定義
│       │   ├── GlobalBlackboard.gd  # 全局黑板系統
│       │   ├── WorldGraph.gd        # 世界圖譜關係系統
│       │   └── ResourceNode.gd      # 資源節點定義
│       ├── Extension/               # GDExtension (C++)
│       │   └── NPCAISYSTEM.cpp      # NPC AI 系統核心
│       ├── UI/                      # 調試與 UI 組件
│       │   ├── FactionNodeUI.gd     # 派系節點 UI 組件
│       │   ├── FactionNodeUI.tscn   # 派系節點場景
│       │   ├── GeopoliticsDebugView.gd  # 調試視圖
│       │   └── GeopoliticsDebugView.tscn # 調試視圖場景
│       └── TestScene/              # 測試場景
│           └── GeopoliticsTestScene.tscn
└── Tests/                           # 測試腳本
    └── Test_Geopolitics_Stage1.gd   # Stage 1 集成測試
```

---

## 2. 系統模組概覽 (System Modules Overview)

### 2.1 核心系統

#### FactionData.gd
**類型**: `Resource` 資源類
**職責**: 定義派系的基本屬性、性格係數、SEC 檔案與外交關係

**主要功能**:
- `personality_coefficients`: 侵略性、貿易傾向、忠誠度
- SEC Profile: `truth_awareness`, `suffering_coefficient`, `wall_distrust_index`, `obedience`, `fear_threshold`
- 資源管理: `has_resource()`, `get_resource_production()`
- 外交關係: `get_relation_to()`, `modify_diplomacy()`

**依賴**: `ResourceNode`

---

#### GlobalBlackboard.gd
**類型**: `Node` (建議設為 Autoload)
**職責**: 全局狀態監控與信號發布

**主要功能**:
- 經濟數據: `global_food_price`, `coal_stock`, `ancient_core_stock`
- 環境數據: `storm_intensity` (區域強度映射)
- 玩家狀態: `player_wanted_level`, `player_relic_count`
- 全球緊張度: `world_tension`
- 信號: `resource_shortage`, `storm_warning`, `market_crash`, `world_tension_changed`

---

#### WorldGraph.gd
**類型**: `Node`
**職責**: 管理派系間關係與互動邏輯

**主要功能**:
- 貿易狀態常數: `TRADE_STATUS_EMBARGO`, `TRADE_STATUS_OPEN`, `TRADE_STATUS_LICENSE_HELD`
- `find_invasion_target()`: 根據資源短缺與外交關係尋找最佳入侵目標
- `modify_relation()`: 修改派系關係並發出信號
- `process_tribute()`: 處理進貢系統 (改善關係 → 解鎖貿易/通行證)
- 信號: `relation_changed`, `trade_status_changed`, `invasion_declared`, `tribute_offered`

**依賴**: `FactionData`, `ResourceNode`

---

#### ResourceNode.gd
**類型**: `Resource` 資源類
**職責**: 定義地圖上的可佔領區域與資源產出

**主要屬性**:
- `resource_type`: 資源類型 ("coal", "crystals", "food")
- `production_rate`: 單位時間產出量
- `strategic_value`: 戰略價值 (影響 AI 搶奪意願)
- `current_owner_name`: 當前擁有者名稱

---

### 2.2 擴展系統

#### NPCAISYSTEM.cpp
**類型**: C++ GDExtension
**職責**: 高性能 NPC AI 代理系統

**已實作功能**:
- 基礎代理類別 (`Agent`)
- SEC Profile 數據存儲與檢索
- 模擬步進與狀態管理
- 空間分區 (`SpatialHash`) - 高效能事件查詢
- 沉船幽靈記錄 (`GhostRecorder`) - 捕捉下沉軌跡
- 任務黑板 (`JobBlackboard`) - 動態任務分發
- 事件總線 (`WorldEventBus`) - 物理世界與 AI 決策橋樑

**未來擴展** (參考 `NPC_AI_Modular_Structure_CN.md`):
- NavMesh 導航整合
- 外交關係圖譜 (`KnowledgeGraph`)
- 視覺反饋系統
- 甲板手行為循環

---

### 2.3 UI 組件

#### FactionNodeUI.gd
**類型**: `PanelContainer`
**職責**: 派系節點的 UI 顯示

**主要功能**:
- 顯示派系名稱
- 顯示性格係數 (Agg, Trd)
- 列出擁有的資源與產量

---

#### GeopoliticsDebugView.gd
**類型**: 節點腳本 (具體類型未定)
**職責**: 地緣政治系統的調試視圖

**詳細功能待補充**

---

## 3. 系統交互流程 (System Interaction Flow)

### 3.1 初始化流程

```
Godot 啟動
├─ Autoload: GlobalBlackboard._ready()
│  └─ 初始化全局數據 (經濟、環境、緊張度)
├─ 場景載入: GeopoliticsTestScene.tscn
│  ├─ WorldGraph._ready()
│  │  └─ 註冊所有派系 (FactionData 資源)
│  ├─ 載入 GDExtension: NPCAISYSTEM.cpp
│  │  └─ NPCAIController 類註冊
│  └─ UI 初始化: GeopoliticsDebugView
│     └─ FactionNodeUI 組件生成
└─ 測試啟動: Test_Geopolitics_Stage1
   └─ 驗證 GDExtension 與 GDScript 集成
```

### 3.2 運行循環

```
每一幀 (每秒 1 次低頻 Tick)
├─ GlobalBlackboard.check_resource_levels()
│  └─ 資源檢查 → 發送 resource_shortage 信號
├─ GlobalBlackboard.update_storms(delta)
│  └─ 更新環境數據
├─ NPCAISYSTEM._process(delta) [C++]
│  ├─ WorldEventBus 處理事件
│  ├─ Agent 行為更新
│  └─ JobBlackboard 任務分配
├─ WorldGraph.find_invasion_target()
│  └─ 根據資源短缺與外交關係評分
└─ 信號處理
   ├─ resource_shortage → AI 決策 (貿易/戰爭)
   └─ relation_changed → UI 更新
```

### 3.3 事件驅動示例

```
玩家攻擊派系 A 的船隻
├─ 物理系統: 發送 StructuralFailure 事件
├─ NPCAISYSTEM [C++]: WorldEventBus 接收
│  ├─ 目擊者記錄事件
│  ├─ GhostRecorder 記錄下沉軌跡 (若沉沒)
│  └─ JobBlackboard 發布救援/拾荒任務
├─ WorldGraph [GDScript]: modify_relation(玩家, 派系A, -0.3)
│  ├─ 關係值下降
│  └─ 發送 relation_changed 信號
├─ GlobalBlackboard: world_tension += 5.0
│  └─ 緊張度上升
└─ UI 更新: GeopoliticsDebugView 顯示新關係狀態
```

---

## 4. 數據流 (Data Flow)

### 4.1 SEC Profile 數據流

```
FactionData (GDScript) ←→ NPCAISYSTEM (C++)
├─ GDScript 定義 SEC 結構
├─ C++ 透過 set_agent_sec_profile() 設置
└─ C++ 透過 get_agent_sec_profile() 檢索
```

### 4.2 外交關係數據流

```
WorldGraph (GDScript)
├─ 存儲於 FactionData.relations 字典
├─ modify_relation() 更新雙向關係
├─ 信號通知 UI 與 AI 系統
└─ 進貢系統: process_tribute() → 關係改善 → 解鎖貿易狀態
```

### 4.3 資源數據流

```
ResourceNode (GDScript)
├─ 由 FactionData.owned_nodes 引用
├─ get_resource_production() 計算總產量
├─ find_invasion_target() 評估資源需求
└─ GlobalBlackboard 監控全局庫存
```

---

## 5. 模組化擴展路線摘要

* 詳細規劃與效能分層見 `NPC_AI_Modular_Structure_CN.md`
* Phase 1: MessageQueue, Logistics, PopulationMorale
* Phase 2: SeasonalHazard, CultureProfile, LegalSystem
* Phase 3: BlackMarket, IndustryTech, GovernanceCost
* Phase 4: FactionSubgroups, Ideology, Espionage
* Phase 5: PersonalMemory, MultiLayerBlackboard

---

## 6. 當前實作狀態 (Implementation Status)

### ✅ 已完成 (Stage 1)

| 模組 | 狀態 | 文件 |
|------|------|------|
| 派系數據資源 | ✅ | `FactionData.gd` |
| 全局黑板系統 | ✅ | `GlobalBlackboard.gd` |
| 世界圖譜系統 | ✅ | `WorldGraph.gd` |
| 資源節點定義 | ✅ | `ResourceNode.gd` |
| GDExtension AI 核心 | ✅ | `NPCAISYSTEM.cpp` |
| 基礎 UI 組件 | ✅ | `FactionNodeUI.gd`, `GeopoliticsDebugView.gd` |
| 集成測試 | ✅ | `Test_Geopolitics_Stage1.gd` |

### 🚧 進行中

| 模組 | 狀態 | 備註 |
|------|------|------|
| NavMesh 導航整合 | 🚧 | NPCAISYSTEM 擴展功能 |
| 外交關係圖譜 | 🚧 | KnowledgeGraph 類別 |

### ❌ 未實作

| 模組 | 狀態 | 計劃 |
|------|------|------|
| 視覺反饋系統 | ❌ | 根據 AwarenessState 觸發特效 |
| 甲板手行為循環 | ❌ | 基於 JobBlackboard 實作 |
| 訊息隊列系統 | ❌ | 惡名與謠言傳播機制 |

---

## 6. 技術設計決策 (Technical Design Decisions)

### 6.1 混合語言架構

**決策**: GDScript (邏輯層) + C++ (效能層)

**原因**:
- GDScript 快速開發與調試
- C++ 處理大量實體的 AI 運算
- 透過 GDExtension 無縫整合

---

### 6.2 資源類別設計

**決策**: 使用 `Resource` 類別存儲派系與節點數據

**原因**:
- 便於在編輯器中創建實例
- 支持檔案序列化
- 減少運行時資源加載開銷

---

### 6.3 信號驅動架構

**決策**: 使用 Godot 信號系統進行模組間通信

**原因**:
- 解耦模組依賴
- 事件驅動更適合模擬系統
- 便於調試與監控

---

## 7. 參考文檔

- 系統設計: `System_Design_Geopolitics_CN.md`
- 模組結構: `NPC_AI_Modular_Structure_CN.md`
- 實作報告: `3_Implemented_Archive/NPC_AI_Implementation_Report_CN.md`
- 任務清單: `4_Tasks_WIP/TODO.md`

---

*文檔版本: 1.0*
*創建日期: 2026-01-18*
