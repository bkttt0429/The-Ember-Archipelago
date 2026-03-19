class_name WaterBodyManager
extends Node

## ★ 水體管理器 — 管理多個獨立 WaterBody + 碰撞合併

@export_group("碰撞檢測")
@export var merge_check_interval: float = 0.5

@export_group("Debug")
@export var debug_log: bool = true

var _check_timer: float = 0.0
var _wb_script = null

func _ready() -> void:
	_wb_script = load("res://NewWaterSystem/Core/Scripts/WaterBody.gd")
	print("[WaterBodyManager] Initialized (WaterBody script: %s)" % ("OK" if _wb_script else "MISSING!"))

func _physics_process(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= merge_check_interval:
		_check_timer = 0.0
		_check_merges()

func get_water_bodies() -> Array[Node]:
	return get_tree().get_nodes_in_group("WaterBodies")

## 在指定位置建立新水體
func spawn_water_body(pos: Vector3, radius: float = 3.0, initial_volume: float = 5.0) -> Node:
	if not _wb_script:
		_wb_script = load("res://NewWaterSystem/Core/Scripts/WaterBody.gd")
	if not _wb_script:
		print("[WaterBodyManager] ERROR: WaterBody.gd not found!")
		return null
	
	var wb = Node3D.new()
	wb.set_script(_wb_script)
	wb.set("body_radius", radius)
	wb.set("volume", initial_volume)
	wb.set("max_volume", initial_volume * 5.0)
	wb.set("debug_log", true)
	add_child(wb)
	wb.global_position = pos
	if debug_log:
		print("[WaterBodyManager] Spawned WaterBody at %s vol=%.1f r=%.1f" % [pos, initial_volume, radius])
	return wb

func _check_merges() -> void:
	var bodies = get_water_bodies()
	if bodies.size() < 2: return
	
	var merged_any = true
	while merged_any:
		merged_any = false
		bodies = get_water_bodies()
		for i in range(bodies.size()):
			if not is_instance_valid(bodies[i]): continue
			for j in range(i + 1, bodies.size()):
				if not is_instance_valid(bodies[j]): continue
				var a = bodies[i]
				var b = bodies[j]
				if _should_merge(a, b):
					_merge_bodies(a, b)
					merged_any = true
					break
			if merged_any: break

func _should_merge(a: Node, b: Node) -> bool:
	if not a.has_method("get") or not b.has_method("get"): return false
	var r_a = a.get("body_radius")
	var r_b = b.get("body_radius")
	if r_a == null or r_b == null: return false
	var dist = a.global_position.distance_to(b.global_position)
	return dist < (r_a + r_b) * 0.9

func _merge_bodies(a: Node, b: Node) -> void:
	var vol_a = a.get("volume") if a.get("volume") != null else 0.0
	var vol_b = b.get("volume") if b.get("volume") != null else 0.0
	var r_a = a.get("body_radius") if a.get("body_radius") != null else 3.0
	var r_b = b.get("body_radius") if b.get("body_radius") != null else 3.0
	
	if debug_log:
		print("[WaterBodyManager] ★ MERGING: %s (vol=%.1f) + %s (vol=%.1f)" % [a.name, vol_a, b.name, vol_b])
	
	var new_pos = (a.global_position + b.global_position) * 0.5
	var new_volume = vol_a + vol_b
	var new_radius = maxf(r_a, r_b) + a.global_position.distance_to(b.global_position) * 0.3
	
	var merged = spawn_water_body(new_pos, new_radius, new_volume)
	if merged:
		merged.name = "MergedWater_%d" % (randi() % 10000)
		if merged.has_method("add_impulse"):
			merged.add_impulse(new_pos, 5.0, new_radius * 0.5)
	
	a.queue_free()
	b.queue_free()
	
	if debug_log and merged:
		print("[WaterBodyManager]   → New: %s r=%.1f vol=%.1f" % [merged.name, new_radius, new_volume])
