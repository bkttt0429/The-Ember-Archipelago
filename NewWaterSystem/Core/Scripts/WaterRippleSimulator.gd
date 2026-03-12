extends Node
class_name WaterRippleSimulator

## Analytic Ripple Simulator (v11)
## 取代舊版 GPU SWE 模擬
## 提供精確的環形緩衝區、明確壽命、時間空間雙重衰減

const MAX_RIPPLES: int = 64

@export_group("波動參數")
@export var ar_lifetime: float = 3.0
@export var ar_speed: float = 2.0
@export var ar_freq: float = 15.0
@export var ar_decay: float = 2.0

@export_group("衝擊參數")
@export var impulse_strength: float = 0.5
@export var idle_impulse_strength: float = 0.1
@export var drop_interval: float = 0.4
@export var min_drop_interval: float = 0.05

var follow_target: Node3D = null

# ★ C8: 風場參數（由 WaterManager 傳入）
var wind_direction: Vector2 = Vector2.ZERO
var wind_strength: float = 0.0

# ★ C7: 多物體衝擊源 Array of {position: Vector3, strength: float}
var extra_impulse_sources: Array = []

var ripples: PackedVector4Array
var _ripple_idx: int = 0
var _time_passed: float = 0.0

var _last_drop_pos: Vector3 = Vector3.ZERO
var _last_drop_time: float = -10.0

func _ready() -> void:
	ripples.resize(MAX_RIPPLES)
	for i in range(MAX_RIPPLES):
		ripples[i] = Vector4(0.0, 0.0, -1000.0, 0.0) # Start time far in the past
	print("[WaterRippleSimulator] v11 Analytic Ring Buffer (Max Ripples = %d)" % MAX_RIPPLES)

func add_ripple(pos: Vector3, strength: float) -> void:
	ripples[_ripple_idx] = Vector4(pos.x, pos.z, _time_passed, strength)
	_ripple_idx = (_ripple_idx + 1) % MAX_RIPPLES
	_last_drop_pos = pos
	_last_drop_time = _time_passed

func _process(delta: float) -> void:
	_time_passed += delta
	
	# === 主角尾流 ===
	if follow_target and is_instance_valid(follow_target):
		var target_pos = follow_target.global_position
		var dist = target_pos.distance_to(_last_drop_pos)
		var time_since = _time_passed - _last_drop_time
		
		# 根據速度決定掉落間隔
		var current_speed = dist / max(time_since, 0.001)
		var actual_interval = drop_interval
		if current_speed > 1.0:
			actual_interval = max(min_drop_interval, drop_interval / current_speed)
			
		if dist >= actual_interval:
			var dynamic_strength = impulse_strength
			if current_speed < 0.5:
				dynamic_strength = idle_impulse_strength
			add_ripple(target_pos, dynamic_strength)
	
	# === 額外衝擊源 ===
	for src in extra_impulse_sources:
		# 簡單處理：如果 extra 源傳過來，可能就是持續產生
		# 這裡假設 manager 每幀都會報吿最新位置
		# 我們可以用機率或時間間隔添加，避免加太多
		# 簡化起見，如果它移動超過 0.5m 就放一個波
		if randf() < 0.1: # 每秒約 6 個波
			add_ripple(src.position, src.strength)

	# Debug
	if Engine.get_frames_drawn() % 180 == 0:
		var active = 0
		for r in ripples:
			if _time_passed - r.z <= ar_lifetime:
				active += 1
		print("[Ripple v11] Active ripples: %d/%d (wind: %.1f)" % [active, MAX_RIPPLES, wind_strength])

func get_analytic_data() -> PackedVector4Array:
	return ripples

func get_analytic_count() -> int:
	return MAX_RIPPLES
