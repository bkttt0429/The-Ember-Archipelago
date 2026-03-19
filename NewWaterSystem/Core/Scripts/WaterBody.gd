class_name WaterBody
extends Node3D

## ★ 有限體積水體 — 使用現有 SWE GPU 高度圖系統
## 不做獨立渲染，而是驅動 OceanWaterManager 的 SWE Compute Shader
## 透過 trigger_water_injection() 持續注入/排出水量
## 水面變化直接反映在 GPU 高度圖上，視覺效果由海洋 Shader 統一處理

# ═══════════════════════════════════
# Exports
# ═══════════════════════════════════
@export_group("水體形狀")
## 水體影響半徑（米）
@export var body_radius: float = 3.0
## 水體影響高度（控制 SWE 注入強度）
@export var body_height: float = 1.0

@export_group("水量")
## 當前水量（m³）— 控制 SWE 持續注入量
@export var volume: float = 10.0
## 最大容量（m³）— 0 = 無上限
@export var max_volume: float = 50.0
## 每秒自動排水量（m³/s）— 0 = 不排水
@export var drain_rate: float = 0.0
## 每秒自動注水量（m³/s）— 0 = 不注水
@export var fill_rate: float = 0.0
## 注入頻率：每秒向 SWE 推送幾次
@export var injection_fps: float = 15.0

@export_group("Debug")
@export var debug_log: bool = false
@export var show_debug_ring: bool = true

# ═══════════════════════════════════
# Internal
# ═══════════════════════════════════
var _water_manager: Node = null
var _injection_timer: float = 0.0
var _is_empty: bool = false
var _debug_ring: MeshInstance3D = null
var _debug_material: StandardMaterial3D = null
var _total_injected: float = 0.0  # 累計注入 SWE 的量

signal volume_changed(new_volume: float)
signal water_depleted
signal body_merged(other: WaterBody)

## 供 WaterBodyManager 用的世界空間 AABB
var world_bounds: AABB:
	get:
		var half = Vector3(body_radius, maxf(body_height, 0.5), body_radius)
		return AABB(global_position - half, half * 2.0)

func _ready() -> void:
	_find_water_manager()
	add_to_group("WaterBodies")
	
	if show_debug_ring:
		_create_debug_ring()
	
	# 初始注入：把初始 volume 轉成 SWE 高度
	_inject_to_swe(volume * 0.1)  # 初始脈衝
	
	print("[WaterBody] 初始化: pos=%s vol=%.1f r=%.1f" % [global_position, volume, body_radius])

func _physics_process(delta: float) -> void:
	if not _water_manager:
		_find_water_manager()
		if not _water_manager: return
	
	# 自動注水/排水
	if fill_rate > 0.0:
		add_water(fill_rate * delta)
	if drain_rate > 0.0:
		remove_water(drain_rate * delta)
	
	# 水量為零
	if volume <= 0.001:
		if not _is_empty:
			_is_empty = true
			water_depleted.emit()
			# 排出 SWE：負注入（讓水降回去）
			_inject_to_swe(-_total_injected * 0.3)
			_total_injected = 0.0
			if _debug_ring: _debug_ring.visible = false
			if debug_log: print("[WaterBody] ★ 水量歸零")
		return
	elif _is_empty:
		_is_empty = false
		if _debug_ring: _debug_ring.visible = true
	
	# 持續向 SWE 注入（維持水位）
	_injection_timer += delta
	var interval = 1.0 / maxf(injection_fps, 1.0)
	if _injection_timer >= interval:
		_injection_timer -= interval
		# 注入量與當前 volume 成正比
		var inject_strength = volume / maxf(max_volume, volume) * body_height * 0.5
		_inject_to_swe(inject_strength)
	
	# 更新 Debug 圈
	if _debug_ring and show_debug_ring:
		_update_debug_ring()

# ═══════════════════════════════════
# Public API
# ═══════════════════════════════════

## 注水（增加 SWE 高度）
func add_water(amount: float) -> void:
	if amount <= 0.0: return
	var old = volume
	volume += amount
	if max_volume > 0.0:
		volume = minf(volume, max_volume)
	if volume != old:
		# 額外脈衝注入（讓增加的水量表現在 SWE 上）
		_inject_to_swe(amount * 0.3)
		volume_changed.emit(volume)
		if debug_log: print("[WaterBody] + %.2f → vol=%.1f" % [amount, volume])

## 排水（降低 SWE 高度）
func remove_water(amount: float) -> void:
	if amount <= 0.0: return
	var old = volume
	volume = maxf(volume - amount, 0.0)
	if volume != old:
		# 負注入（讓水面下降）
		_inject_to_swe(-amount * 0.2)
		volume_changed.emit(volume)
		if debug_log: print("[WaterBody] - %.2f → vol=%.1f" % [amount, volume])

## 在指定世界座標產生漣漪擾動
func add_impulse(world_pos: Vector3, strength: float, radius: float = 0.5) -> void:
	if _water_manager and _water_manager.has_method("trigger_ripple"):
		_water_manager.trigger_ripple(world_pos, strength, radius)

# ═══════════════════════════════════
# SWE 注入
# ═══════════════════════════════════
func _inject_to_swe(strength: float) -> void:
	if not _water_manager: return
	if absf(strength) < 0.001: return
	
	if _water_manager.has_method("trigger_water_injection"):
		_water_manager.trigger_water_injection(global_position, strength, body_radius)
		_total_injected += maxf(strength, 0.0)
	elif _water_manager.has_method("trigger_ripple"):
		# Fallback: 用普通漣漪
		_water_manager.trigger_ripple(global_position, strength, body_radius)

func _find_water_manager() -> void:
	_water_manager = get_tree().root.find_child("OceanWaterManager", true, false)
	if not _water_manager:
		_water_manager = get_tree().root.find_child("WaterManager", true, false)

# ═══════════════════════════════════
# Debug 視覺化
# ═══════════════════════════════════
func _create_debug_ring() -> void:
	_debug_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.03
	torus.outer_radius = body_radius
	torus.rings = 32
	torus.ring_segments = 6
	
	_debug_material = StandardMaterial3D.new()
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_material.albedo_color = Color(0.2, 0.7, 1.0, 0.5)
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.no_depth_test = true
	torus.material = _debug_material
	
	_debug_ring.mesh = torus
	_debug_ring.position = Vector3(0, 0.05, 0)
	_debug_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_debug_ring)

func _update_debug_ring() -> void:
	if not _debug_material: return
	# 顏色隨水量變化：空=紅，滿=藍
	var fill_ratio = volume / maxf(max_volume, volume)
	var col = Color(1.0 - fill_ratio, 0.3 + fill_ratio * 0.4, fill_ratio, 0.4 + fill_ratio * 0.2)
	_debug_material.albedo_color = col
	# 大小隨水量微調
	var scale_factor = 0.8 + fill_ratio * 0.4
	_debug_ring.scale = Vector3(scale_factor, 1, scale_factor)
