extends Node
class_name StepPlanner

## StepPlanner - 偵測樓梯踏面並計算下一個落腳點
## 使用射線掃描偵測前方地形，投影到 2D 計算步伐
##
## ★ 2b 方案：先找到階梯面 → 根據步伐距離投影 XZ → raycast 驗證
## ★ 冷卻機制：防止 step_detected 每幀連發

signal step_detected(foot: String, target_pos: Vector3, step_height: float)

@export_group("Ray Configuration")
@export var ray_count: int = 5 # 射線數量
@export var scan_distance: float = 0.8 # 向前掃描距離
@export var scan_width: float = 0.4 # 左右掃描寬度
@export var max_step_height: float = 0.5 # 最大台階高度

@export_group("Stride Settings")
@export var min_stride: float = 0.3 # 最小步伐距離
@export var max_stride: float = 0.7 # 最大步伐距離
@export var stride_height_clearance: float = 0.15 # 抬腳高度餘量

@export_group("Cooldown")
## 每次觸發 step_detected 後的冷卻時間（秒）
@export var step_cooldown: float = 0.3
## 同一隻腳的最小間隔（避免連續踏同一腳）
@export var same_foot_cooldown: float = 0.5

@export_group("Debug")
@export var debug_draw: bool = true
@export var debug_print: bool = true

# 內部狀態
var _player: CharacterBody3D
var _left_foot_pos: Vector3
var _right_foot_pos: Vector3
var _current_stepping_foot: String = "" # "left" or "right" or "" (reserved for future)
var _detected_steps: Array[Dictionary] = [] # 偵測到的踏面

# 冷卻計時器
var _cooldown_timer: float = 0.0
var _left_foot_cooldown: float = 0.0
var _right_foot_cooldown: float = 0.0

# 最新掃描結果
var _last_scan_result: Dictionary = {}


func _ready() -> void:
	# 尋找 PlayerController
	_player = get_parent() as CharacterBody3D
	if not _player:
		_player = get_tree().get_first_node_in_group("Player") as CharacterBody3D
	
	if _player:
		print("[StepPlanner] Initialized with player: %s" % _player.name)
	else:
		push_warning("[StepPlanner] No CharacterBody3D found!")


func _physics_process(delta: float) -> void:
	if not _player:
		return
	
	# ★ 更新冷卻計時器
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if _left_foot_cooldown > 0.0:
		_left_foot_cooldown -= delta
	if _right_foot_cooldown > 0.0:
		_right_foot_cooldown -= delta
	
	# 從 SimpleFootIK 獲取腳部位置
	var foot_ik = _player.get_node_or_null("SimpleFootIK") as SimpleFootIK
	if foot_ik:
		_left_foot_pos = foot_ik.get_left_foot_position()
		_right_foot_pos = foot_ik.get_right_foot_position()
	
	# 獲取移動方向
	var move_dir = _player.velocity
	if move_dir.length() > 0.1:
		# ★ 冷卻中不掃描
		if _cooldown_timer <= 0.0:
			var scan_result = scan_terrain(move_dir)
			_last_scan_result = scan_result


## 獲取最新掃描結果
func get_last_scan_result() -> Dictionary:
	return _last_scan_result

## 設置當前雙腳位置 (由 FootIK 或 Animation 提供)
func update_foot_positions(left: Vector3, right: Vector3) -> void:
	_left_foot_pos = left
	_right_foot_pos = right

## 主要偵測函數 - 掃描前方地形
func scan_terrain(move_direction: Vector3) -> Dictionary:
	if not _player:
		return {}
	
	var result = {
		"has_step": false,
		"target_position": Vector3.ZERO,
		"step_height": 0.0,
		"suggested_foot": "",
		"surfaces": []
	}
	
	if move_direction.length() < 0.1:
		return result
	
	var forward = Vector3(move_direction.x, 0, move_direction.z).normalized()
	var right = forward.cross(Vector3.UP).normalized()
	var space_state = _player.get_world_3d().direct_space_state
	
	_detected_steps.clear()
	
	# 發射射線陣列掃描地形
	for i in range(ray_count):
		var t = float(i) / float(ray_count - 1) if ray_count > 1 else 0.5
		var lateral_offset = lerp(-scan_width / 2.0, scan_width / 2.0, t)
		var forward_offset = scan_distance
		
		var ray_origin = _player.global_position + Vector3.UP * (max_step_height + 0.2)
		ray_origin += forward * forward_offset
		ray_origin += right * lateral_offset
		
		var ray_end = ray_origin + Vector3.DOWN * (max_step_height + 0.5)
		
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.exclude = [_player.get_rid()]
		query.collision_mask = 1
		
		var hit = space_state.intersect_ray(query)
		
		if hit:
			var surface_y = hit.position.y
			var height_diff = surface_y - _player.global_position.y
			
			_detected_steps.append({
				"position": hit.position,
				"normal": hit.normal,
				"height_diff": height_diff,
				"lateral_offset": lateral_offset
			})
			
			# Debug 繪製
			if debug_draw:
				_debug_draw_ray(ray_origin, hit.position, Color.GREEN)
		else:
			if debug_draw:
				_debug_draw_ray(ray_origin, ray_end, Color.RED)
	
	# 分析掃描結果
	if _detected_steps.size() > 0:
		result = _analyze_surfaces(forward)
	
	return result

## 分析偵測到的踏面
func _analyze_surfaces(forward: Vector3) -> Dictionary:
	var result = {
		"has_step": false,
		"target_position": Vector3.ZERO,
		"step_height": 0.0,
		"suggested_foot": "",
		"surfaces": _detected_steps.duplicate()
	}
	
	if _detected_steps.is_empty():
		return result
	
	# 計算平均高度差
	var _avg_height_diff = 0.0 # Reserved for terrain slope analysis
	var highest_surface: Dictionary = {}
	var max_height = - INF
	
	for surface in _detected_steps:
		_avg_height_diff += surface.height_diff
		if surface.height_diff > max_height:
			max_height = surface.height_diff
			highest_surface = surface
	
	_avg_height_diff /= _detected_steps.size()
	
	# 判斷是否為台階
	if max_height > 0.02 and max_height <= max_step_height:
		result.has_step = true
		result.step_height = max_height
		result.suggested_foot = _suggest_stepping_foot(highest_surface.position)
		
		# ★ 檢查同腳冷卻
		if result.suggested_foot == "left" and _left_foot_cooldown > 0.0:
			return result # 不觸發，等冷卻結束
		elif result.suggested_foot == "right" and _right_foot_cooldown > 0.0:
			return result
		
		# ★★★ 2b 方案：步伐投影 + raycast 驗證 ★★★
		var projected = _project_landing_with_stride(
			highest_surface.position, result.suggested_foot, forward)
		result.target_position = projected
		
		if debug_print:
			print("[StepPlanner] 偵測到台階! height=%.2f, raw=%s, projected=%s, foot=%s" % [
				max_height,
				highest_surface.position,
				projected,
				result.suggested_foot
			])
		
		# ★ 設定冷卻
		_cooldown_timer = step_cooldown
		if result.suggested_foot == "left":
			_left_foot_cooldown = same_foot_cooldown
		else:
			_right_foot_cooldown = same_foot_cooldown
		
		# 發出信號
		step_detected.emit(result.suggested_foot, result.target_position, max_height)
	
	return result


## ★★★ 2b 方案：在階梯面上根據步伐距離投影落腳點 ★★★
## 1. 用步伐距離決定 XZ 位置
## 2. Raycast 驗證該位置是否在階梯面上
## 3. 通過 → 用投影位置；失敗 → fallback 到原始命中點
func _project_landing_with_stride(
	raw_hit_pos: Vector3, foot: String, forward: Vector3
) -> Vector3:
	# 決定當前腳和對側腳的位置
	var current_foot_pos: Vector3
	var other_foot_pos: Vector3
	
	if foot == "left":
		current_foot_pos = _left_foot_pos
		other_foot_pos = _right_foot_pos
	else:
		current_foot_pos = _right_foot_pos
		other_foot_pos = _left_foot_pos
	
	# 計算步伐投影（2D）
	var current_2d = Vector2(current_foot_pos.x, current_foot_pos.z)
	var other_2d = Vector2(other_foot_pos.x, other_foot_pos.z)
	var forward_2d = Vector2(forward.x, forward.z).normalized()
	
	# 當前步伐距離 → clamp 到合理範圍
	var current_stride = current_2d.distance_to(other_2d)
	var ideal_stride = clamp(current_stride * 1.1, min_stride, max_stride)
	
	# 從當前腳位置沿前進方向投影
	var projected_2d = current_2d + forward_2d * ideal_stride
	
	# 用原始命中的 Y 值（階梯面高度）
	var projected_3d = Vector3(projected_2d.x, raw_hit_pos.y, projected_2d.y)
	
	# ★ Raycast 驗證：投影位置是否仍然在階梯面上？
	if _player:
		var space_state = _player.get_world_3d().direct_space_state
		var verify_origin = projected_3d + Vector3.UP * (max_step_height + 0.2)
		var verify_end = projected_3d + Vector3.DOWN * (max_step_height + 0.5)
		
		var query = PhysicsRayQueryParameters3D.create(verify_origin, verify_end)
		query.exclude = [_player.get_rid()]
		query.collision_mask = 1
		
		var verify_hit = space_state.intersect_ray(query)
		
		if verify_hit:
			# 驗證通過：使用投影的 XZ + 實際 raycast 的 Y
			var verified_y = verify_hit.position.y
			var height_diff = abs(verified_y - raw_hit_pos.y)
			
			if height_diff < max_step_height:
				if debug_print:
					print("[StepPlanner] 步伐投影驗證通過: stride=%.2f, verified_y=%.3f" % [ideal_stride, verified_y])
				return Vector3(projected_2d.x, verified_y, projected_2d.y)
			else:
				if debug_print:
					print("[StepPlanner] 步伐投影高度差過大 (%.2f)，fallback到原始命中點" % height_diff)
		else:
			if debug_print:
				print("[StepPlanner] 步伐投影位置無地面，fallback到原始命中點")
	
	# Fallback：使用原始射線命中位置
	return raw_hit_pos


## 建議哪隻腳先踏出
func _suggest_stepping_foot(target_pos: Vector3) -> String:
	# 投影到 2D (XZ 平面)
	var target_2d = Vector2(target_pos.x, target_pos.z)
	var left_2d = Vector2(_left_foot_pos.x, _left_foot_pos.z)
	var right_2d = Vector2(_right_foot_pos.x, _right_foot_pos.z)
	
	# 計算哪隻腳離目標更遠 (較遠的腳先動，模擬自然步態)
	var _left_dist = left_2d.distance_to(target_2d) # Reserved for distance-based selection
	var _right_dist = right_2d.distance_to(target_2d)
	
	# 也考慮當前哪隻腳在後面
	var player_2d = Vector2(_player.global_position.x, _player.global_position.z)
	var left_behind = left_2d.distance_to(player_2d)
	var right_behind = right_2d.distance_to(player_2d)
	
	# 後面的腳先動
	if left_behind > right_behind:
		return "left"
	else:
		return "right"

## 計算建議的落腳點 (考慮步伐距離) - 舊 API 保留
func get_next_footstep(current_foot_pos: Vector3, other_foot_pos: Vector3, target_surface: Vector3) -> Vector3:
	# 投影到 2D
	var current_2d = Vector2(current_foot_pos.x, current_foot_pos.z)
	var other_2d = Vector2(other_foot_pos.x, other_foot_pos.z)
	var target_2d = Vector2(target_surface.x, target_surface.z)
	
	# 計算當前步伐距離
	var current_stride = current_2d.distance_to(other_2d)
	
	# 計算朝向目標的方向
	var direction = (target_2d - current_2d).normalized()
	
	# 計算理想步伐距離
	var ideal_stride = clamp(current_stride * 1.1, min_stride, max_stride)
	
	# 計算新的落腳點 (2D)
	var new_pos_2d = current_2d + direction * ideal_stride
	
	# 在目標表面找最近的有效位置
	var result = Vector3(new_pos_2d.x, target_surface.y, new_pos_2d.y)
	
	return result

## Debug 繪製射線 (使用 DebugDraw 或臨時 MeshInstance)
func _debug_draw_ray(_from: Vector3, _to: Vector3, _color: Color) -> void:
	# 簡單的 debug - 在控制台輸出
	# 實際可用 DebugDraw3D 插件或自訂繪製
	pass

## 獲取 2D 步伐距離
func get_stride_distance_2d() -> float:
	var left_2d = Vector2(_left_foot_pos.x, _left_foot_pos.z)
	var right_2d = Vector2(_right_foot_pos.x, _right_foot_pos.z)
	return left_2d.distance_to(right_2d)
