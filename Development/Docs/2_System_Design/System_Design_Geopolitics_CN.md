

# 《星海餘燼 Starfall Remnants》

# **系統驅動型智慧世界 — 計畫文檔 Project Document**

**版本：1.0**
**更新者：柏坤**
**開發工具：Godot 4.x、GDScript、GraphEdit Tool、Resource Data Assets**
**核心概念：Systemic World, MAS, Utility AI, Knowledge Graph, Blackboard System**

---

# 1. 計畫目的（Project Purpose）

本計畫旨在打造一個 **無需玩家輸入也能自主運行** 的智慧型海上世界，用於低多邊形風格海洋冒險遊戲《星海餘燼》。

此世界由三種核心技術支撐：

1. **黑板系統（BBS）** — 世界狀態統一資料中心
2. **知識圖譜（KG）** — 派系與地緣政治網絡
3. **效用 AI（Utility AI × Game Theory）** — 決策大腦

最終目標：
打造 **可湧現行為（Emergent Behavior）**、**可演化歷史**、**可自我平衡** 的世界框架。

---

# 2. 系統概要（System Overview）

## 2.1 整體架構圖

```
             ┌─────────────────────┐
             │   GlobalBlackboard  │
             │（經濟/環境/玩家狀態） │
             └───────────┬───────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │                                   │
┌──────────────┐                  ┌──────────────────┐
│ FactionBrain │                  │   WorldGraph (KG) │
│（效用 AI）    │                  │（派系/地點/關係）   │
└──────┬───────┘                  └──────────┬─────────┘
       │                                     │
       └─────────────┬───────────────────────┘
                     │
             ┌───────▼────────┐
             │ NPC Ship / Port │
             │（視覺層行為）   │
             └─────────────────┘
```

---

# 3. 系統模組（Modules）

---

## 3.1 黑板系統（Global Blackboard System）

### 3.1.1 功能

* 世界狀態儲存中心
* AI 讀取唯一真實數據源
* 閾值警報（如糧食短缺 → 戰爭準備）

### 3.1.2 儲存資料

* **經濟**

  * 糧食價格
  * 古代核心庫存
  * 原煤供應量
* **環境**

  * 風暴強度
  * 深淵門活動度（水旋渦）
* **玩家**

  * 通緝等級
  * 擁有遺物數量

### 3.1.3 更新頻率

* **每秒 1 次（低頻 Tick）**

---

## 3.2 知識圖譜（WorldGraph / Knowledge Graph）

### 3.2.1 技術

* `Resource` 資料建模
* 節點（Node）+ 邊（Edge）結構

### 3.2.2 節點類型

* **列強勢力**

  * 至高議會（Aurelian Hegemony）
  * 索利斯聯邦（United Solis）
  * 寒霜大公國（Frostbane）
* **非政府勢力**

  * 鋼鐵兄弟會
  * 漂流木公約
  * 餘燼劫掠者
  * 深淵教團
* **地理節點**

  * 天梯（Waterspout）
  * 深淵門（Whirlpool）
  * 大旋渦（Great Maelstrom）

### 3.2.3 邊之屬性

* `DiplomacyValue`（外交值 -1 ~ 1）
* `TradeStatus`（貿易 / 禁運 / 通行證）
* `ControlLevel`（自由航行 / 封鎖區）

---

## 3.3 效用 AI × 賽局理論（FactionBrain）

### 3.3.1 核心公式

```
Desire = (Need - Stock) / Urgency
```

### 3.3.2 決策權重（例：貿易 vs 戰爭）

* 依據「迭代囚徒困境（Iterated Prisoner's Dilemma）」
* 由外交值、需求、文化風格共同加權

### 3.3.3 更新頻率

* **每 5–10 秒**

---

# 4. 重大系統功能（Key Systems）

---

## 4.1 資訊傳播與惡名系統（Reputation & Rumor System）

### 4.1.1 消息強度衰減

```
Strength(B) = Strength(A) * e^(-k * distance)
```

### 4.1.2 謠言失真度

```
Distortion = BaseNoise + CultureChaosFactor
```

### 4.1.3 目擊者機制

* 玩家若擊沉帝國船只
* 附近 NPC 會記錄事件
* 回港 → 更新 KG diplomacy（惡名 + 戰爭傾向）

### 4.1.4 RRT（Real-time Relay Transmission）

* 消息視為「移動中的資料包」
* 玩家可物理攔截目擊者（消滅或封堵）
* 消息即可被終止傳播

---

## 4.2 關係衰減與歷史記憶

基礎公式：

```
Favorability(t+1) 
  = Favorability(t) * e^(-λt) 
  + Σ(ΔInfluence)
```

文化對 λ 的影響：

* **至高議會**：紀律文化 → λ 小（忘記慢）
* **餘燼劫掠者**：混亂文化 → λ 大（波動劇烈）

---

## 4.3 經濟擾動與蝴蝶效應

情境範例：
玩家走私大量糧食給「鋼鐵兄弟會」

→ 黑板：糧價下降
→ KG：鋼鐵兄弟會對至高議會依賴降低
→ FactionBrain：取消「生存遠征」戰爭
→ 建立新「貿易鏈依賴」邊

---

# 5. 系統互動流程（Flow）

---

## 5.1 世界運行循環（World Simulation Loop）

```
Tick (1s)
 ├─ 更新黑板：經濟、天氣、玩家通緝
 ├─ 更新訊息隊列（消息傳播）
 ├─ 每 10 秒：更新 AI 派系決策
 └─ 事件觸發 → 更新 KG 關係
```

---

## 5.2 決策偽代碼（示例）

```pseudo
function decide_action(factionA, factionB):
    need = factionA.food_need
    stock = factionA.food_stock
    urgency = factionA.urgency_factor

    desire = (need - stock) / urgency
    diplomacy = KG.get_diplomacy(factionA, factionB)

    # 囚徒困境 payoff
    payoff_trade = UtilityMatrix.trade
    payoff_war = UtilityMatrix.war

    if diplomacy < -0.5:
        trade_score = payoff_trade * (0.3 + diplomacy)
        war_score = payoff_war   * (1 - diplomacy)
    else:
        trade_score = payoff_trade * (1 + diplomacy)
        war_score = payoff_war   * (0.2 - diplomacy)

    return WAR if war_score > trade_score else TRADE
```

---

# 6. 目擊者訊息隊列（Message Queue）

### 6.1 消息格式

```
Message {
    id
    source
    targets[]
    travel_time
    truthfulness
    urgency
}
```

### 6.2 流程

```
Add to Queue 
→ 每 tick travel_time-- 
→ 抵達港口 → 更新 KG / 惡名
→ 若途中遭攔截 → cancel_message()
```

---

# 7. 開發檔案（Deliverables）

| 檔名                    | 內容              |
| --------------------- | --------------- |
| `FactionData.gd`      | 派系屬性、文化、資源      |
| `GlobalBlackboard.gd` | 世界狀態中心          |
| `WorldGraph.gd`       | 知識圖譜（外交、貿易、控制力） |
| `FactionBrain.gd`     | 功能性 AI  + 賽局權重  |
| `MessageQueue.gd`     | 資訊傳播、惡名系統       |

---

# 8. 效能與編輯器支援

### 8.1 優化建議

* 使用 signals 而非 `_process` 輪詢
* 大量行為改為 **事件驅動**

### 8.2 編輯器工具

* 客製 `GraphEdit` 用來編輯：

  * 派系外交
  * 地區控制
  * 經濟流

---

# 9. 後續可追加（如你需要）

✔ Godot 專案模板
✔ 各系統的 GDScript 實作骨架
✔ 事件系統（Event Dispatcher）
✔ 自動任務生成（PCG Mission System）
✔ 世界觀設定文檔（Lore Bible）

---
