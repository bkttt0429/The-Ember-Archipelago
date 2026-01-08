class_name WorldGraph
extends Node

## 世界圖譜系統
## 管理派系之間的關係與互動邏輯。

# 貿易狀態常數
const TRADE_STATUS_EMBARGO = 0      # 禁運/封鎖
const TRADE_STATUS_OPEN = 1         # 開放貿易
const TRADE_STATUS_LICENSE_HELD = 2 # 持有通行證 (特權)

# 訊號定義
signal relation_changed(faction_a: FactionData, faction_b: FactionData, new_value: float)
signal trade_status_changed(faction_a: FactionData, faction_b: FactionData, status: int)
signal invasion_declared(aggressor: FactionData, target: FactionData, reason: String)
signal tribute_offered(source: FactionData, target: FactionData, item: String)

# 註冊在案的所有派系
@export var all_factions: Array[FactionData] = []

# 為攻擊者尋找最佳入侵目標
# 根據資源短缺類型 (shortage_type) 和外交關係進行權重評估
func find_invasion_target(aggressor: FactionData, shortage_type: String) -> FactionData:
	var best_target: FactionData = null
	var highest_score: float = -9999.0
	
	print("[%s] Looking for invasion target due to shortage: %s" % [aggressor.faction_name, shortage_type])
	
	for potential_target in all_factions:
		if potential_target == aggressor:
			continue
			
		# 獲取關係數據
		var relation = aggressor.get_relation_to(potential_target)
		var diplomacy = relation["diplomacy_value"]
		
		# 評分邏輯
		# 1. 外交越差 (負值)，分數越高 -> -diplomacy * 10
		# 2. 如果是盟友 (diplomacy > 0.5)，極力避免 -> 扣分
		var score = -diplomacy * 10
		
		if diplomacy > 0.5:
			score -= 50.0 # 盟友懲罰
			
		# 3. 性格修正
		var aggression = aggressor.personality_coefficients.get("aggression", 0.5)
		score *= (1.0 + aggression)
		
		# 4. 資源需求判定
		# 如果目標根本沒有我們需要的資源，入侵分數應該大幅降低
		if not potential_target.has_resource(shortage_type):
			score -= 1000.0 # 極大懲罰，基本上不會選中
			print("    -> Target has NO %s. Skipping." % shortage_type)
		else:
			# 如果有資源，根據產量增加分數
			var production = potential_target.get_resource_production(shortage_type)
			score += production * 5.0
			print("    -> Target HAS %s (Prod: %.1f). Bonus added." % [shortage_type, production])
		
		print("  -> Evaluating %s: Score %f (Diplomacy: %f)" % [potential_target.faction_name, score, diplomacy])
		
		if score > highest_score:
			highest_score = score
			best_target = potential_target
			
	return best_target

# 修改兩個派系之間的關係
func modify_relation(faction_a: FactionData, faction_b: FactionData, delta: float):
	faction_a.modify_diplomacy(faction_b, delta)
	# 這裡假設外交是相對的，對方也會有反應，但不一定完全對等。簡單起見先同步。
	faction_b.modify_diplomacy(faction_a, delta)
	
	emit_signal("relation_changed", faction_a, faction_b, faction_a.get_relation_to(faction_b)["diplomacy_value"])
	print("Diplomacy update: %s <-> %s changed by %f" % [faction_a.faction_name, faction_b.faction_name, delta])

# 獲取路徑 (暫時簡化為直接連接查詢，未來可擴充為 A* 節點跳躍)
func is_faction_connected(faction_a: FactionData, faction_b: FactionData) -> bool:
	var rel = faction_a.get_relation_to(faction_b)
	return rel["trade_status"] != TRADE_STATUS_EMBARGO

# 進貢系統處理
# 模擬玩家向目標派系提交遺物以改善關係
func process_tribute(source_faction: FactionData, target_faction: FactionData, item_type: String):
	var improvement = 0.0
	
	match item_type:
		"ancient_core":
			improvement = 0.4 # 核心遺物，大幅改善
		"clockwork_mechanism":
			improvement = 0.1 # 普通發條零件
			
	emit_signal("tribute_offered", source_faction, target_faction, item_type)
	print("[%s] Offering tribute (%s) to [%s]..." % [source_faction.faction_name, item_type, target_faction.faction_name])
	
	modify_relation(source_faction, target_faction, improvement)
	
	# 檢查是否由敵對轉為中立，或解鎖通行證
	var current_rel = source_faction.get_relation_to(target_faction)
	if current_rel["diplomacy_value"] > 0.2 and current_rel["trade_status"] == TRADE_STATUS_EMBARGO:
		current_rel["trade_status"] = TRADE_STATUS_OPEN
		emit_signal("trade_status_changed", source_faction, target_faction, TRADE_STATUS_OPEN)
		print("  -> Embargo lifted! Trade is now OPEN.")
		
	if current_rel["diplomacy_value"] > 0.6:
		current_rel["trade_status"] = TRADE_STATUS_LICENSE_HELD
		emit_signal("trade_status_changed", source_faction, target_faction, TRADE_STATUS_LICENSE_HELD)
		print("  -> License GRANTED! You are now a recognized ally.")
