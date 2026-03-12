extends Node3D
class_name LookAtTargetManager

## 目標優先級管理器 - 控制頭部 LookAt 目標選擇

enum TargetType {
	NONE, # 無目標 - 頭部回正
	CAMERA_RAYCAST, # 相機射線點 (預設)
	ENEMY, # 敵人 (戰鬥中)
	POI, # 興趣點 (探索/劇情)
}

@export_group("Settings")
@export var enabled: bool = true
@export var blend_speed: float = 3.0 ## 目標切換平滑速度
@export var max_raycast_distance: float = 100.0
@export var camera_target_distance: float = 10.0 ## 無碰撞時的預設距離

@export_group("Node References")
@export var look_at_target: Node3D ## LookAt 節點 (位置錨點)
@export var look_at_modifier: LookAtModifier3D ## 頭部追蹤 Modifier

@export_group("Collision")
@export var collision_mask: int = 1 ## 射線碰撞層

# 內部狀態
var current_target_type: TargetType = TargetType.CAMERA_RAYCAST
var current_priority: int = 1
var _active_pois: Array[Dictionary] = [] # {node: Node3D, priority: int}
var _active_enemies: Array[Node3D] = []
var _player: CharacterBody3D
var _current_target_position: Vector3 = Vector3.ZERO
var _target_influence: float = 0.6

func _ready():
	_player = get_parent() as CharacterBody3D
	if not _player:
		push_error("[LookAtTargetManager] Parent must be CharacterBody3D")
		enabled = false
		return
	
	if not look_at_target:
		push_error("[LookAtTargetManager] look_at_target not set")
		enabled = false
		return
	
	if not look_at_modifier:
		push_error("[LookAtTargetManager] look_at_modifier not set")
		enabled = false
		return
	
	print("[LookAtTargetManager] Initialized")

func _process(delta):
	if not enabled:
		return
	
	# 1. 決定目標類型與優先級
	_update_target_selection()
	
	# 2. 計算目標位置
	_update_target_position()
	
	# 3. 平滑移動 LookAt 錨點
	look_at_target.global_position = look_at_target.global_position.lerp(
		_current_target_position,
		delta * blend_speed
	)
	
	# 4. 平滑調整 Modifier 的 influence
	_update_modifier_influence(delta)

# ==============================================================================
# 目標選擇邏輯
# ==============================================================================

func _update_target_selection():
	# 優先級 3: 敵人 (戰鬥中)
	if _active_enemies.size() > 0:
		var nearest_enemy = _get_nearest_enemy()
		if nearest_enemy and _player.global_position.distance_to(nearest_enemy.global_position) < 10.0:
			current_target_type = TargetType.ENEMY
			current_priority = 3
			_target_influence = 1.0
			return
	
	# 優先級 2: POI (探索)
	if _active_pois.size() > 0:
		var highest_poi = _get_highest_priority_poi()
		if highest_poi:
			current_target_type = TargetType.POI
			current_priority = 2
			_target_influence = 0.8
			return
	
	# 優先級 1: 相機射線 (預設)
	current_target_type = TargetType.CAMERA_RAYCAST
	current_priority = 1
	_target_influence = 0.6

func _update_target_position():
	match current_target_type:
		TargetType.ENEMY:
			var enemy = _get_nearest_enemy()
			if enemy:
				_current_target_position = enemy.global_position + Vector3(0, 1.6, 0) # 瞄準頭部
		
		TargetType.POI:
			var poi = _get_highest_priority_poi()
			if poi:
				_current_target_position = poi["node"].global_position
		
		TargetType.CAMERA_RAYCAST:
			_current_target_position = _calculate_camera_raycast_point()
		
		TargetType.NONE:
			# 不更新位置，讓 influence 降為 0 即可
			pass

func _calculate_camera_raycast_point() -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if not camera or not _player:
		return _current_target_position # 保持上一個位置
	
	# 從畫面中心發射射線
	var viewport = get_viewport()
	var screen_center = viewport.get_visible_rect().size / 2.0
	
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)
	var ray_end = ray_origin + ray_direction * max_raycast_distance
	
	# 執行射線檢測
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	# 排除玩家自身
	if _player:
		query.exclude = [_player.get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position
	else:
		# 沒碰到東西，使用預設距離
		var head_pos = _player.global_position + Vector3(0, 1.6, 0)
		return head_pos + ray_direction * camera_target_distance

func _update_modifier_influence(delta: float):
	if not look_at_modifier:
		return
	
	# 檢查目標是否超出角度限制
	var is_out_of_range = _is_target_out_of_angle_limit()
	
	if is_out_of_range or current_target_type == TargetType.NONE:
		# 漸變回正
		look_at_modifier.influence = lerp(
			look_at_modifier.influence,
			0.0,
			delta * blend_speed
		)
	else:
		# 漸變啟用
		look_at_modifier.influence = lerp(
			look_at_modifier.influence,
			_target_influence,
			delta * blend_speed
		)

func _is_target_out_of_angle_limit() -> bool:
	# 簡化版：檢查目標是否在玩家視野範圍內
	# TODO: 可以根據 LookAtModifier3D 的角度限制做更精確判斷
	var head_pos = _player.global_position + Vector3(0, 1.6, 0)
	var to_target = (_current_target_position - head_pos).normalized()
	var forward = - _player.global_transform.basis.z
	
	var dot = to_target.dot(forward)
	return dot < 0.3 # 約 72 度以內

# ==============================================================================
# 輔助函數
# ==============================================================================

func _get_nearest_enemy() -> Node3D:
	if _active_enemies.size() == 0:
		return null
	
	var nearest: Node3D = _active_enemies[0]
	var min_dist = _player.global_position.distance_to(nearest.global_position)
	
	for enemy in _active_enemies:
		var dist = _player.global_position.distance_to(enemy.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = enemy
	
	return nearest

func _get_highest_priority_poi() -> Dictionary:
	if _active_pois.size() == 0:
		return {}
	
	var highest = _active_pois[0]
	for poi in _active_pois:
		if poi["priority"] > highest["priority"]:
			highest = poi
	
	return highest

# ==============================================================================
# Public API - POI 管理
# ==============================================================================

func register_poi(poi: Node3D, priority: int = 2):
	"""註冊一個興趣點 (Point of Interest)"""
	for existing in _active_pois:
		if existing["node"] == poi:
			existing["priority"] = priority # 更新優先級
			return
	
	_active_pois.append({"node": poi, "priority": priority})
	print("[LookAtTargetManager] POI registered: %s (priority: %d)" % [poi.name, priority])

func unregister_poi(poi: Node3D):
	"""移除一個興趣點"""
	for i in range(_active_pois.size() - 1, -1, -1):
		if _active_pois[i]["node"] == poi:
			_active_pois.remove_at(i)
			print("[LookAtTargetManager] POI unregistered: %s" % poi.name)
			return

# ==============================================================================
# Public API - Enemy 管理
# ==============================================================================

func register_enemy(enemy: Node3D):
	"""註冊一個敵人目標"""
	if enemy not in _active_enemies:
		_active_enemies.append(enemy)
		print("[LookAtTargetManager] Enemy registered: %s" % enemy.name)

func unregister_enemy(enemy: Node3D):
	"""移除一個敵人目標"""
	var idx = _active_enemies.find(enemy)
	if idx >= 0:
		_active_enemies.remove_at(idx)
		print("[LookAtTargetManager] Enemy unregistered: %s" % enemy.name)

# ==============================================================================
# Public API - 查詢
# ==============================================================================

func get_current_target() -> Vector3:
	"""獲取當前目標位置"""
	return _current_target_position

func get_current_target_type() -> TargetType:
	"""獲取當前目標類型"""
	return current_target_type
