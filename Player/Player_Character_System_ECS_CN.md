# 玩家角色系統架構（ECS / 伺服器權威 / 物理優先）

本文件定義開放世界玩家角色系統的模組化結構，遵循 NPC AI 模組化設計風格，並以 ECS 架構在 Godot 中落地。系統重點包含伺服器權威同步、物理互動優先、生存要素、武器驅動動作模型。

---

## 1. 詳細資料夾結構圖

```text
player/
├── core/
│   ├── PlayerConstants.gd      # 全域常數 (例如速度上限、物理閾值)
│   ├── PlayerMath.gd           # 動作/物理/補間工具
│   └── PlayerEntityFactory.gd  # 玩家 Entity 組裝入口
├── components/
│   ├── IdentityComponent.gd      # 玩家識別與派系
│   ├── TransformComponent.gd     # 位置/旋轉/尺度
│   ├── PhysicsComponent.gd       # 速度/質量/重力
│   ├── MovementState.gd          # 行走/攀爬/游泳狀態
│   ├── CombatState.gd            # 鎖定/格擋/連段
│   ├── VitalsComponent.gd        # HP/體力/飢餓/溫度
│   ├── StatsComponent.gd         # 力量/敏捷/耐力/感知
│   ├── WeaponComponent.gd        # 武器資訊與動作集
│   ├── EquipmentComponent.gd     # 裝備槽與屬性修正
│   ├── InventoryComponent.gd     # 物品欄與重量
│   ├── InteractionComponent.gd   # 互動目標與距離
│   ├── AnimationComponent.gd     # 動畫狀態與 IK 參數
│   ├── SurvivalComponent.gd      # 飢餓/疲勞/環境傷害
│   └── NetworkComponent.gd       # 伺服器同步狀態
├── systems/
│   ├── InputSystem.gd           # 輸入轉指令
│   ├── CommandQueueSystem.gd    # 指令排程與緩衝
│   ├── MovementSystem.gd        # 移動/攀爬/游泳
│   ├── PhysicsInteractionSystem.gd # 物理優先互動
│   ├── CombatSystem.gd          # 攻擊/格擋/連段
│   ├── WeaponActionSystem.gd    # 武器驅動動作
│   ├── StaminaSystem.gd         # 體力消耗/回復
│   ├── SurvivalSystem.gd        # 生存參數更新
│   ├── DamageSystem.gd          # 傷害與死亡流程
│   ├── InventorySystem.gd       # 拾取/掉落/重量
│   ├── InteractionSystem.gd     # 互動流程
│   ├── AnimationSystem.gd       # ECS 驅動動畫
│   ├── CameraSystem.gd          # 追蹤/瞄準
│   ├── NetworkSyncSystem.gd     # 伺服器權威同步
│   └── UISyncSystem.gd          # UI 狀態更新
├── events/
│   ├── WorldEventBus.gd         # 事件總線
│   └── PlayerSignals.gd         # 低頻 Signal 集中
└── managers/
	├── PlayerSimulationManager.gd # 系統註冊與更新
	└── PlayerSpawnManager.gd       # 生成與重生
```

---

## 2. 核心模組職責

* **Input / CommandQueue**：將輸入轉換為可驗證的 Action Command，供伺服器權威處理。
* **PhysicsInteraction**：以物理狀態為權威，動作與動畫跟隨物理結果。
* **WeaponAction**：動作集完全由武器定義，角色本體不持有技能樹。
* **Survival**：飢餓/疲勞/溫度/環境傷害，影響體力與移動性能。
* **NetworkSync**：伺服器權威同步，處理指令驗證與狀態快照。

---

## 3. 伺服器權威資料流

```
Input → Client CommandQueue → Server Validate → Server Simulate
	→ Snapshot + Event → Client Reconcile → Animation/UI
```

### 3.1 權威原則

* 所有移動、戰鬥、物理互動由伺服器裁定
* 客戶端只送出指令與預測動畫
* 回傳狀態以 Snapshot + Event 形式同步

---

## 4. 物理互動優先設計

* 物理碰撞結果優先於動作播放
* 動作若與物理衝突可被中斷或回滾
* AnimationSystem 只讀取 MovementState/PhysicsComponent 產生動畫

---

## 5. 生存系統（Survival）

### 5.1 模組範圍

* 飢餓 (Hunger)
* 疲勞 (Fatigue)
* 溫度 (Temperature)
* 環境傷害 (EnvironmentDamage)

### 5.2 影響規則

* 飢餓與疲勞降低體力上限
* 低溫/高溫造成持續傷害或速度懲罰

---

## 6. 武器驅動動作模型

* 每把武器提供 Action Set 與屬性修正
* 角色無獨立技能樹
* 裝備切換即切換攻擊組合與動作節奏

資料結構草案：

```
WeaponActionSet { weapon_id, actions, stamina_cost, hit_frames }
ActionCommand { type, target_id, duration, interruptible }
```

---

## 7. 更新頻率矩陣（建議）

```
Input / CommandQueue      每幀
Movement / Combat         每幀
PhysicsInteraction        每幀
Animation / Camera        每幀
Stamina / Survival        0.5s-1s
Inventory / Interaction   1s-2s
NetworkSync               每幀 (快照)
```

---

## 8. 模組依賴矩陣（最小耦合）

```
InputSystem              -> CommandQueueSystem
CommandQueueSystem       -> MovementSystem, WeaponActionSystem
MovementSystem           -> PhysicsComponent, MovementState
PhysicsInteractionSystem -> MovementSystem, CombatSystem, PhysicsComponent
CombatSystem             -> WeaponComponent, StatsComponent, CombatState
WeaponActionSystem       -> WeaponComponent, StaminaSystem
StaminaSystem            -> VitalsComponent, MovementState
SurvivalSystem           -> SurvivalComponent, VitalsComponent, StaminaSystem
DamageSystem             -> CombatState, VitalsComponent
InventorySystem          -> InventoryComponent, EquipmentComponent
InteractionSystem        -> InteractionComponent, WorldEventBus
AnimationSystem          -> MovementState, CombatState, AnimationComponent
CameraSystem             -> MovementState, CombatState
NetworkSyncSystem        -> All authority systems
UISyncSystem             -> VitalsComponent, WeaponComponent, InventoryComponent
```

---

## 9. 伺服器/客戶端同步格式

### 9.1 Client Command

```
ClientCommand {
  client_id,
  tick,
  input_vector,
  action_type,
  action_payload,
  timestamp
}
```

### 9.2 Server Snapshot

```
ServerSnapshot {
  tick,
  entity_id,
  position,
  rotation,
  velocity,
  movement_state,
  combat_state,
  stamina,
  vitals,
  weapon_state
}
```

### 9.3 Server Event

```
ServerEvent {
  tick,
  event_type,
  source,
  target,
  severity,
  payload
}
```

---

## 10. Godot 節點與 ECS 對應

```
PlayerNode (CharacterBody3D)
  -> IdentityComponent
  -> TransformComponent
  -> PhysicsComponent
  -> MovementState
  -> CombatState
  -> VitalsComponent
  -> WeaponComponent
  -> EquipmentComponent
  -> InventoryComponent
  -> InteractionComponent
  -> AnimationComponent
  -> SurvivalComponent
  -> NetworkComponent
```

---

## 11. 信號與事件命名規範

* Signal 使用狀態變化式：`stamina_changed`, `weapon_swapped`
* EventBus 使用行為動作式：`attack_executed`, `hit_confirmed`
* Payload 必填欄位：`source`, `target`, `severity`, `timestamp`

---

## 12. 系統初始化順序（建議）

```
1) PlayerEntityFactory
2) WorldEventBus
3) InputSystem
4) CommandQueueSystem
5) MovementSystem
6) PhysicsInteractionSystem
7) WeaponActionSystem
8) CombatSystem
9) StaminaSystem
10) SurvivalSystem
11) DamageSystem
12) InventorySystem
13) InteractionSystem
14) AnimationSystem
15) CameraSystem
16) NetworkSyncSystem
17) UISyncSystem
```

---

## 13. Phase 建議

### Phase 1：可操作核心

* 移動、跳躍、攻擊、格擋
* 伺服器權威快照同步
* 基本武器動作集

### Phase 2：物理互動與生存

* 推拉、破壞、落水
* 飢餓/疲勞/溫度
* 動作中斷與物理回滾

### Phase 3：進階互動

* 載具/坐騎
* 環境專屬動作
* 複合武器動作集
```
