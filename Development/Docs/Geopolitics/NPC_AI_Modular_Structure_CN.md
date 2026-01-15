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
