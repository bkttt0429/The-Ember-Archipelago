class_name FactionData
extends Resource

## 派系數據資源
## 定義派系的基本屬性、性格係數以及擁有的領地與外交關係。

# 派系名稱
@export var faction_name: String = "Unnamed Faction"

# 性格係數 (0.0 - 1.0)
# 用於 AI 決策權重
@export var personality_coefficients: Dictionary = {
	"aggression": 0.5, # 侵略性：高則傾向戰爭與擴張
	"trade_focus": 0.5, # 貿易傾向：高則傾向經濟手段
	"loyalty": 0.5 # 忠誠/守信：影響結盟穩定度
}

# ==============================================================================
# 社會-經濟-認知 (SEC) 檔案 (Social-Economic-Cognitive Profile)
# ==============================================================================
@export_group("SEC Profile")
## 真相知曉度 (0.0 - 1.0)：對世界真相（如牆的本質）的了解程度
@export_range(0.0, 1.0) var truth_awareness: float = 0.0

## 苦難係數 (0.0 - 1.0)：派系成員普遍的痛苦程度（資源匱乏、疾病等）
@export_range(0.0, 1.0) var suffering_coefficient: float = 0.0

## 牆的不信任度 (0.0 - 1.0)：對「牆」維護者與現狀的懷疑程度
@export_range(0.0, 1.0) var wall_distrust_index: float = 0.0

## 服從度 (0.0 - 1.0)：對上級命令的服從傾向
@export_range(0.0, 1.0) var obedience: float = 0.8

## 恐懼閾值：累積多少創傷後會導致崩潰或逃跑
@export var fear_threshold: float = 10.0


# 擁有的節點 (MapNode/ResourceNode)
# 暫時使用 Resource，待 MapNode 實作後可替換
# 擁有的節點 (ResourceNode)
@export var owned_nodes: Array[ResourceNode] = []

# 檢查該派系是否擁有特定資源的產出
func has_resource(resource_type: String) -> bool:
	for node in owned_nodes:
		if node.resource_type == resource_type:
			return true
	return false

# 計算特定資源的總產量 (AI 評估用)
func get_resource_production(resource_type: String) -> float:
	var total = 0.0
	for node in owned_nodes:
		if node.resource_type == resource_type:
			total += node.production_rate
	return total

# 外交關係
# Key: 目標派系 (FactionData)
# Value: 關係數據字典
# {
#   "diplomacy_value": float (-1.0 to 1.0),
#   "trade_status": int (Enum: OPEN, EMBARGO, LICENSE_HELD),
#   "is_ally": bool
# }
@export var relations: Dictionary = {}

func get_relation_to(target_faction: FactionData) -> Dictionary:
	if relations.has(target_faction):
		return relations[target_faction]
	return {
		"diplomacy_value": 0.0,
		"trade_status": 0, # DEFINED IN WorldGraph CONSTANTS
		"is_ally": false
	}

func modify_diplomacy(target_faction: FactionData, amount: float):
	if not relations.has(target_faction):
		relations[target_faction] = {
			"diplomacy_value": 0.0,
			"trade_status": 0,
			"is_ally": false
		}
	
	relations[target_faction]["diplomacy_value"] = clamp(relations[target_faction]["diplomacy_value"] + amount, -1.0, 1.0)
