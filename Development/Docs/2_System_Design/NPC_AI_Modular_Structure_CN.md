# NPC AI 系統模組化結構說明 (進階擴展示意)

為了實現具備「觸感物理」、「動態地緣政治」以及「湧現行為」的智慧世界，我們將系統重構為高度解耦的模組化架構。

## 1. 詳細資料夾結構圖

```text
src/
├── core/
│   ├── Utils.h          # 基礎數學與 Vec3 封裝 (處理向量運算、類型別名)
│   ├── Constants.h      # 全域常數 (如 MAX_AGENTS, 物理閾值)
│   └── MathHelpers.h    # 專門處理彈道預測、PID 控制器算式
├── components/
│   ├── FactionComponent.h
│   ├── FactionComponent.cpp    # 派系屬性、身分識別、SEC Profile 數據
│   ├── BuoyancyComponent.h
│   ├── BuoyancyComponent.cpp   # 浮力模擬、下沉狀態邏輯
│   ├── ResourceNeeds.h         # 資源需求追蹤 (煤炭、廢料等)
│   ├── HullComponent.h         # 船體結構 (HP、裝甲、進水率 - 影響浮力)
│   ├── CargoComponent.h        # 貨倉管理 (重量會影響物理浮力與平衡)
│   └── SensorComponent.h       # 感知組件 (視覺錐、聽覺範圍、異常頻率偵測)
├── combat/ (戰鬥系統)
│   ├── WeaponSystem.h        # 武器控制器 (射速、冷卻、彈藥類型)
│   ├── BallisticsSolver.h    # 彈道解算器 (計算魚叉/砲彈落點，考慮重力與相對速度)
│   ├── TacticalAnalyzer.h    # 戰術分析 (尋找掩體、最佳射擊角度、側翼包抄權重)
│   └── DamageHandler.h       # 傷害處理 (計算穿透、跳彈、船體破裂)
├── economy/ (經濟與貿易)
│   ├── MarketExchange.h      # 市場交易所 (處理供需曲線、通膨計算)
│   ├── TradeRoutePlanner.h   # 貿易路線規劃 (A* 導航權重 + 風險評估)
│   └── InflationManager.h    # 通膨管理器 (基於 SEC 穩定度調整全域物價)
├── social/ (外交與敘事)
│   ├── DiplomacyMatrix.h     # 外交矩陣 (儲存派系間的好感度、盟約狀態)
│   ├── RelationTracker.h     # 個體關係追蹤 (NPC 對玩家的私人恩怨)
│   └── DialogueAssembler.h   # 模糊邏輯組裝器 (實現對話原子組裝)
├── systems/
│   ├── JobBlackboard.h  # 任務分發黑板 (支持任務發布與競標)
│   ├── JobBlackboard.cpp
│   ├── GhostRecorder.h  # 幽靈記錄系統 (記錄下沉軌跡用於遺跡生成)
│   ├── GhostRecorder.cpp
│   ├── WorldEventBus.h  # 空間事件總線 (基於 SpatialHash 的局部事件廣播)
│   ├── WorldEventBus.cpp
│   └── ProjectileManager.h   # 統一管理所有飛行投射物的物理更新
├── agents/
│   ├── Agent.h          # AI 邏輯大腦 (核心決策狀態機、意識系統)
│   ├── Agent.cpp
│   └── BehaviorTree/         # 複雜行為決策樹
│       ├── ActionNode.h
│       └── DecisionNode.h
├── managers/
│   ├── SimulationManager.h   # Godot 節點封裝 (主進入點)
│   └── SimulationManager.cpp # 負責 _process() 循環與系統間的協調
└── register_types.cpp   # GDExtension 類別註冊入口
```

## 2. 核心模組職責

*   **Combat (戰鬥)**: 專注於物理驅動的交戰邏輯，提供高精度的彈道預測與戰術選擇。
*   **Economy (經濟)**: 模擬動態市場，將「資源稀缺」與「派系戰爭」透過物價機制連結。
*   **Social (社交)**: 處理地緣政治的核心——關係網。從巨觀的派系外交到微觀的個人記憶。
*   **BehaviorTree (行為樹)**: 提供可擴展的決策框架，讓 AI 能夠根據環境、派系文化做出複雜的連續動作。
*   **Components (組件化數據)**: 所有的物理屬性（重量、重心、船體損害）都將直接影響 AI 的決策（如：超重會導致 AI 優先排放貨物或尋找最近的港口）。

## 3. 重構藍圖

本次重構旨在將原本單一的運算密集型代碼分配至各個專門模組，實現「高內聚、低耦合」。這不僅有利於開發期間的邏輯除錯，更能在未來支持數以百計的智慧代理人在同一個開放海域協作運行。

---
*更新日期：2026-01-14*
*目前階段：架構設計更新 (Phase 1.5)*

---

## 4. 混合架構（CPU + GPU）效能規劃

### 4.1 設計目標

* 以 CPU 處理高分支、事件驅動、狀態機切換與任務派發
* 以 GPU 或批處理處理大量同構數學計算（評分、感知、熱力圖）
* 確保 1000 NPC 常態世界模擬與 100 NPC 戰鬥場景均可穩定運行

### 4.2 AI 更新頻率分層

* 高頻（0.1s）：戰鬥走位、避障、目標維持
* 中頻（0.5s-1s）：戰術評分、掩體評價、隊形調整
* 低頻（5s-10s）：派系策略、外交、經濟決策
* 超低頻（30s-60s）：反思、記憶彙整、長期計畫

### 4.3 GPU 或批處理適用範圍

* 感知與威脅場計算（視野密度、敵我分布）
* 位置評分（掩體價值、距離權重、路徑風險）
* 大量 NPC 的效用評分（SEC + 需求 + 風險）

### 4.4 CPU 保留範圍

* 任務黑板分派與競標
* 行為狀態機切換與事件觸發
* WorldGraph / GlobalBlackboard 的關係與狀態更新

### 4.5 資料流與決策流程

```
黑板資料（Global/Region/Local）
    → GPU/批處理評分（感知/威脅/效用）
    → CPU 決策（任務派發/狀態機切換）
    → 行為執行（移動/戰鬥/互動）
    → 事件回饋 → 黑板更新
```

### 4.6 啟動 GPU 評分的效能準則

* AI 評分超過 3-5ms/幀時轉入 GPU 或批處理
* NPC 數量接近 5000+ 時優先切換 GPU 評分
* 戰鬥場景以 100 NPC 為上限，全量 AI 優先保持 CPU

---

## 5. 模組化路線（Phase 1-5）

### 5.1 Phase 1：基礎真實感

**MessageQueue（情報傳播與噪聲）**

* 語言：GDScript
* 通訊：Signal（低頻事件）
* 資料結構草案：`MessageData { id, source, target, truth, urgency, decay, travel_time, payload }`
* MVP：事件產生消息，travel_time 遞減，抵達後改變外交/緊張度

**Logistics（物流與補給線）**

* 語言：GDScript
* 通訊：Signal（中頻事件）
* 資料結構草案：`TradeRouteData { from, to, resource, risk, travel_time }`, `ConvoyData { route_id, cargo, escort_level, eta }`
* MVP：資源產出進入 Convoy，ETA 到達後才改變庫存

**PopulationMorale（人口與士氣/戰爭疲勞）**

* 語言：GDScript
* 通訊：Signal（低頻事件）
* 資料結構草案：`PopulationState { population, morale, war_fatigue }`
* MVP：戰爭累積疲勞，士氣下降影響生產與戰爭傾向

### 5.2 Phase 2：環境與偏好

**SeasonalHazard（災害與季節）**

* 語言：GDScript
* 通訊：Signal（低頻事件）
* 資料結構草案：`HazardProfile { region, storm_level, season_phase }`
* MVP：區域風暴強度週期變化，影響航線風險與戰鬥修正

**CultureProfile（文化距離與偏見）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`CultureProfile { honor, chaos, xenophobia }`
* MVP：文化差異作為外交/貿易權重修正因子

**LegalSystem（法律/禁令）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`LegalStatus { embargo, license, blockade }`
* MVP：貿易連通性受禁運與通行證限制

### 5.2 Phase 3：進階經濟與勢力

**BlackMarket（黑市/走私）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`BlackMarketDeal { resource, price_multiplier, risk }`
* MVP：在禁運時仍可交易，但增加緊張度或惡名

**IndustryTech（工業/科技等級）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`IndustryTech { tech_level, industry_capacity }`
* MVP：生產效率與武裝強度加成

**GovernanceCost（內政與治理成本）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`GovernanceCost { territory, stability, distance_factor }`
* MVP：治理成本過高降低士氣與產出

### 5.3 Phase 4：深層社會與陰謀

**FactionSubgroups（派系內部分裂）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`Subgroup { name, alignment, influence }`
* MVP：內部派系拉扯造成決策偏移

**Ideology（信仰/意識形態）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`IdeologyProfile { fanaticism, doctrine }`
* MVP：修正戰爭/貿易偏好

**Espionage（間諜與滲透）**

* 語言：GDScript
* 通訊：事件總線（WorldEventBus）
* 資料結構草案：`EspionageAction { source, target, type, success_rate }`
* MVP：向 MessageQueue 注入假消息

### 5.4 Phase 5：個體層與多層真相

**PersonalMemory（個體記憶/仇恨）**

* 語言：C++（高頻更新）
* 通訊：事件總線（WorldEventBus）
* 資料結構草案：`PersonalMemory { entity_id, event, grudge, decay }`
* MVP：影響個體行為偏好（支援/背叛/追擊）

**MultiLayerBlackboard（多層黑板真相差異）**

* 語言：GDScript
* 通訊：Signal
* 資料結構草案：`BlackboardLayer { scope, data, truth_bias }`
* MVP：Region/Local 黑板資訊具有延遲與偏差

---

## 6. 模組依賴矩陣（最小依賴）

* Core 必須先存在：`GlobalBlackboard`, `WorldGraph`, `FactionData`, `ResourceNode`
* 高頻事件優先走 `WorldEventBus`，低頻用 Signal

```
MessageQueue        -> GlobalBlackboard, WorldGraph
Logistics           -> GlobalBlackboard, FactionData
PopulationMorale    -> GlobalBlackboard, FactionData
SeasonalHazard      -> GlobalBlackboard
CultureProfile      -> FactionData, WorldGraph
LegalSystem         -> WorldGraph
BlackMarket         -> GlobalBlackboard, WorldGraph
IndustryTech        -> FactionData
GovernanceCost      -> FactionData
FactionSubgroups    -> FactionData
Ideology            -> FactionData
Espionage           -> MessageQueue, WorldEventBus
PersonalMemory      -> WorldEventBus
MultiLayerBlackboard-> GlobalBlackboard
```

---

## 7. 更新頻率矩陣（建議）

```
MessageQueue         1s
Logistics            1-5s
PopulationMorale     5-10s
SeasonalHazard       10-30s
CultureProfile       30-60s
LegalSystem          10-30s
BlackMarket          10-30s
IndustryTech         30-60s
GovernanceCost       30-60s
FactionSubgroups     30-60s
Ideology             30-60s
Espionage            5-10s
PersonalMemory       0.1-0.5s
MultiLayerBlackboard 5-10s
```

---

## 8. 與 JobBlackboard / WorldEventBus 串接表

```
MessageQueue         -> Signal: message_delivered
Logistics            -> Signal: resource_arrived
PopulationMorale     -> Signal: morale_updated
SeasonalHazard       -> Signal: hazard_updated
CultureProfile       -> Signal: culture_shifted
LegalSystem          -> Signal: legal_status_changed
BlackMarket          -> Signal: illicit_trade_triggered
IndustryTech         -> Signal: tech_level_changed
GovernanceCost       -> Signal: governance_pressure
FactionSubgroups     -> Signal: internal_conflict
Ideology             -> Signal: ideology_shifted
Espionage            -> EventBus: false_info_injected
PersonalMemory       -> EventBus: memory_updated
MultiLayerBlackboard -> Signal: layer_updated

JobBlackboard consumer examples:
- resource_arrived -> 發布護航/防禦任務
- hazard_updated -> 發布避風/改道任務
- false_info_injected -> 發布調查/截獲任務
```

---

## 9. 模組初始化順序（建議）

```
1) GlobalBlackboard (autoload)
2) WorldGraph (autoload or singleton)
3) JobBlackboard (autoload or singleton)
4) MessageQueue
5) Logistics
6) PopulationMorale
7) SeasonalHazard
8) CultureProfile
9) LegalSystem
10) BlackMarket
11) IndustryTech
12) GovernanceCost
13) FactionSubgroups
14) Ideology
15) Espionage
16) PersonalMemory
17) MultiLayerBlackboard
```

---

## 10. 信號/事件命名規範

* Signal 命名使用動詞過去式或狀態變化：`resource_arrived`, `morale_updated`
* EventBus 事件使用動作型短語：`false_info_injected`, `memory_updated`
* payload 統一使用字典，必要欄位：`source`, `target`, `severity`, `timestamp`

---

