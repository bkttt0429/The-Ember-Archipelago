class_name GlobalBlackboard
extends Node

## 黑板系統 (Global Blackboard)
## 負責即時監控全球環境、經濟數據以及發布全局信號。
## 建議將此腳本設定為 Autoload (Project Settings -> Autoload -> Name: GlobalBlackboard)

# 信號定義
signal resource_shortage(resource_type: String, severity: float)
signal storm_warning(region_id: String, intensity: float)
signal market_crash(market_type: String)
signal world_tension_changed(new_value: float)

# 經濟數據
var global_food_price: float = 12.5
var coal_stock: int = 500
var ancient_core_stock: int = 10 # 極其稀有，影響列強軍備

# 環境數據 (區域ID -> 強度 0.0-1.0)
var storm_intensity: Dictionary = {
	"west_sea": 0.1,
	"north_abyss": 0.9, # 寒霜大公國附近通常很惡劣
	"great_vortex": 0.5
}

# 玩家狀態
var player_wanted_level: float = 0.0
var player_relic_count: int = 0

# 全球緊張度 (0.0 - 100.0)
var world_tension: float = 20.0

func _ready():
	print("[GlobalBlackboard] Initialized. World Tension: %f" % world_tension)

# 調整緊張度
func adjust_tension(amount: float):
	world_tension = clamp(world_tension + amount, 0.0, 100.0)
	emit_signal("world_tension_changed", world_tension)
	
	if world_tension > 80.0:
		print("[GlobalBlackboard] WARNING: World tension critical! War imminent.")

# 模擬資源消耗與檢查
# 可以在 _process 中調用，或由 Timer 觸發
func check_resource_levels():
	# 模擬煤炭消耗
	coal_stock -= 1
	
	if coal_stock < 50:
		print("[GlobalBlackboard] Coal shortage detected!")
		emit_signal("resource_shortage", "coal", 0.8)
		
	if ancient_core_stock < 5:
		print("[GlobalBlackboard] Ancient Core shortage! Arms race triggered.")
		emit_signal("resource_shortage", "ancient_core", 1.0)

# 更新環境
func update_storms(delta: float):
	# 簡單的動態變化
	storm_intensity["great_vortex"] = clamp(storm_intensity["great_vortex"] + randf_range(-0.1, 0.1) * delta, 0.0, 1.0)
