extends Node3D

## 河道兩端注水碰撞測試
## 兩端各注水一次，讓兩股水體在中央自然碰撞合併

var _wm = null
@export var inject_duration: float = 3.0   ## 注水持續時間（秒）後停止
@export var inject_interval: float = 0.05  ## 注水間隔（秒）
@export var inject_height: float = 15.0    ## 注水量
@export var inject_radius: float = 5.0     ## 注水半徑
@export var source_spread_x: float = 3.0   ## X 軸散佈範圍
@export var source_z_head: float = -13.0   ## 頭端 Z
@export var source_z_tail: float = 13.0    ## 尾端 Z

var _inject_timer: float = 0.0
var _elapsed: float = 0.0
var _injecting: bool = true

func _ready():
	await get_tree().create_timer(1.0).timeout
	var wm_nodes = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if wm_nodes.size() > 0:
		_wm = wm_nodes[0]
		print("[RiverDemo] ✓ WaterManager 就緒 — 兩端各注水 %.1fs" % inject_duration)
	else:
		print("[RiverDemo] ✗ 找不到 WaterManager")

func _process(delta):
	if not _wm or not _injecting:
		return
	
	_elapsed += delta
	_inject_timer += delta
	
	if _inject_timer >= inject_interval:
		_inject_timer = 0.0
		_do_inject()
	
	if _elapsed >= inject_duration:
		_injecting = false
		print("[RiverDemo] 注水結束，等待碰撞...")

func _do_inject():
	if not _wm.has_method("trigger_water_injection"):
		return
	for i in range(4):
		_wm.trigger_water_injection(
			Vector3(randf_range(-source_spread_x, source_spread_x), 0, source_z_head + randf_range(-0.5, 0.5)),
			inject_height, inject_radius)
		_wm.trigger_water_injection(
			Vector3(randf_range(-source_spread_x, source_spread_x), 0, source_z_tail + randf_range(-0.5, 0.5)),
			inject_height, inject_radius)
