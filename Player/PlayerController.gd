extends CharacterBody3D
class_name PlayerController

## PlayerController - Modular ECS-based Player Character
## Implements the architecture defined in Player_Character_System_ECS_CN.md

@export_group("Nodes (節點參照)")
@export var camera_mount: Node3D # Usually a SpringArm3D or Head node
@export var visuals: Node3D
@export var ground_ray: RayCast3D
@export var interaction_ray: RayCast3D
@export var animation_tree: AnimationTree

@export_group("Step Climbing (樓梯攀爬)")
@export var max_step_height: float = 0.5 # 最大可攀越高度 (約50cm)
@export var step_check_distance: float = 0.5 # 向前檢測距離
@export var step_debug: bool = true # 是否輸出 debug 訊息

@export_group("Settings (設定)")
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -85.0
@export var max_pitch: float = 85.0
@export var movement_profile: MovementProfile

# ECS Components Storage
var components: Dictionary = {}

# ECS Systems Registry
var systems: Array = []

# Internal State
var _water_manager: OceanWaterManager

func _ready() -> void:
	# 1. 搜尋水系統 (供游泳與浮力系統使用)
	_water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers")
	
	# 2. 初始化 ECS 組件 (使用 Factory)
	var factory = PlayerEntityFactory.new()
	components = factory.build_player_entity()
	
	# 補正必要的組件 (確保與系統需求對齊)
	_ensure_component("PhysicsComponent", PhysicsComponent.new())
	_ensure_component("TransformComponent", TransformComponent.new())
	_ensure_component("VitalsComponent", VitalsComponent.new())
	_ensure_component("IdentityComponent", IdentityComponent.new())
	_ensure_component("AnimationComponent", AnimationComponent.new())
	_ensure_component("MovementState", MovementState.new())
	
	# 3. 初始化 ECS 系統
	# 順序：輸入 -> 指令 -> 移動 -> 物理 -> 戰鬥 -> 生存 -> 動畫 -> 相機
	systems = [
		InputSystem.new(),
		MovementSystem.new(),
		PhysicsInteractionSystem.new(),
		InteractionSystem.new(),
		AnimationSystem.new(),
		CameraSystem.new()
	]
	
	for s in systems:
		if s.has_method("set_world"):
			s.set_world(self)
		# 傳遞 MovementProfile 給需要的系統
		if movement_profile and "movement_profile" in s:
			s.movement_profile = movement_profile
	
	# 4. 基礎設定
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	print("[PlayerController] ECS Player Initialized.")

func _ensure_component(comp_name: String, default_instance: Object) -> void:
	if not components.has(comp_name):
		components[comp_name] = default_instance

# ==============================================================================
# ECS World Interface (供 Systems 呼叫)
# ==============================================================================

func get_entities_with(component_names: Array) -> Array:
	# 目前為單人結構，PlayerController 本身即是唯一實體
	for c_name in component_names:
		if not components.has(c_name):
			return []
	return [get_instance_id()]

func get_component(entity_id: int, component_name: String) -> Object:
	if entity_id == get_instance_id():
		return components.get(component_name)
	return null

# ==============================================================================
# Input & Process
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_process_mouse_rotation(event)

func _process_mouse_rotation(event: InputEventMouseMotion) -> void:
	# 水平旋轉 (角色轉向)
	rotate_y(-event.relative.x * mouse_sensitivity)
	
	# 垂直旋轉 (相機俯仰)
	if camera_mount:
		camera_mount.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_mount.rotation.x = clamp(camera_mount.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func _physics_process(delta: float) -> void:
	# 1. 同步基礎屬性
	_sync_to_ecs()
	
	# 2. 執行所有系統
	for s in systems:
		if s.has_method("update"):
			s.update(delta)
	
	# 3. 套用位移
	_sync_from_ecs()
	
	# 4. 嘗試三階段 Step-Up（但腳步動畫播放中暫停，避免膠囊體搶先上升）
	var did_step_up = false
	var procedural_ik = get_node_or_null("ProceduralFootIK") as ProceduralFootIK
	var ik_stepping = procedural_ik and procedural_ik.is_stepping()
	
	if not ik_stepping:
		did_step_up = _try_step_up_move(delta)
	
	if not did_step_up:
		move_and_slide()

func _sync_to_ecs() -> void:
	var trans = components.get("TransformComponent")
	if trans:
		trans.position = global_position
		trans.rotation = global_rotation
	
	var phys = components.get("PhysicsComponent")
	if phys:
		phys.velocity = velocity
		phys.is_grounded = is_on_floor()

func _sync_from_ecs() -> void:
	var phys = components.get("PhysicsComponent")
	if phys:
		velocity = phys.velocity
	
	var movement = components.get("MovementState")
	if movement:
		movement.speed = velocity.length()


func _handle_water_physics(delta: float) -> void:
	if not _water_manager: return
	
	var h = _water_manager.get_base_water_height_at(global_position)
	var depth = h - global_position.y
	
	var movement = components["MovementState"]
	if depth > 0.5: # 水深超過腰部
		movement.is_swimming = true
		movement.mode = "swim"
		# 浮力效果
		var phys = components["PhysicsComponent"]
		phys.velocity.y += (depth * 5.0) * delta # 簡單的浮力
		phys.velocity *= 0.95 # 水中阻力
	else:
		movement.is_swimming = false

# ==============================================================================
# Utility
# ==============================================================================

func toggle_mouse_lock() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ==============================================================================
# ★★★ Three-Phase Step-Up (Raise → Forward → Drop) ★★★
# ==============================================================================
# 使用 move_and_collide 三階段移動，膠囊體不會卡在台階碰撞器上：
#   Phase 1: 膠囊體向上提升 max_step_height（碰到天花板會停下）
#   Phase 2: 膠囊體向前移動（已經在台階上方，不會碰到台階側面）
#   Phase 3: 膠囊體向下落回地面（精準貼到台階頂面）
# ==============================================================================

## 嘗試三階段 step-up 移動。成功返回 true，無台階返回 false
func _try_step_up_move(delta: float) -> bool:
	# 前置條件檢查
	if not is_on_floor():
		return false
	
	var horizontal_vel = Vector3(velocity.x, 0, velocity.z)
	if horizontal_vel.length() < 0.1:
		return false
	
	var move_dir = horizontal_vel.normalized()
	
	# 快速偵測：前方低處有障礙嗎？
	var space_state = get_world_3d().direct_space_state
	var foot_height = 0.05
	var ray_start = global_position + Vector3.UP * foot_height
	var ray_end = ray_start + move_dir * step_check_distance
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit = space_state.intersect_ray(query)
	
	if not hit:
		return false # 前方無障礙，不需要 step-up
	
	# 確認高處無障礙（排除牆壁）
	var ray_start_high = global_position + Vector3.UP * (max_step_height + 0.05)
	var ray_end_high = ray_start_high + move_dir * step_check_distance
	
	var query_high = PhysicsRayQueryParameters3D.create(ray_start_high, ray_end_high)
	query_high.exclude = [get_rid()]
	query_high.collision_mask = 1
	var hit_high = space_state.intersect_ray(query_high)
	
	if hit_high:
		var low_dist = ray_start.distance_to(hit.position)
		var high_dist = ray_start_high.distance_to(hit_high.position)
		if high_dist <= low_dist + 0.1:
			# 高處也被擋住 → 是牆壁，不是台階
			return false
	
	# ★ 確認是台階而非斜坡：檢查碰撞法線
	if hit.normal.angle_to(Vector3.UP) < deg_to_rad(60.0):
		return false # 法線接近朝上 → 斜坡，不需要 step-up
	
	# ========================================
	# Phase 1: RAISE — 向上提升膠囊體
	# ========================================
	var saved_pos = global_position
	var raise_amount = max_step_height + 0.02
	
	var raise_collision = move_and_collide(Vector3.UP * raise_amount)
	var actual_raise = raise_amount
	if raise_collision:
		actual_raise = raise_amount - raise_collision.get_remainder().length()
		if actual_raise < 0.05:
			# 頭頂空間不足，恢復位置
			global_position = saved_pos
			return false
	
	# ========================================
	# Phase 2: FORWARD — 向前移動（滑行）
	# ========================================
	var forward_motion = horizontal_vel * delta
	var _forward_collision = move_and_collide(forward_motion)
	
	# 即使碰到東西也繼續，因為 Phase 3 的 drop 會決定是否有效
	
	# ========================================
	# Phase 3: DROP — 向下落回地面
	# ========================================
	var drop_amount = actual_raise + 0.1 # 多降一點確保貼地
	var drop_collision = move_and_collide(Vector3.DOWN * drop_amount)
	
	if drop_collision:
		# 有碰到地面 → 檢查是否為有效台階
		var landed_y = global_position.y
		var step_height = landed_y - saved_pos.y
		
		if step_height > 0.02 and step_height <= max_step_height:
			# ✅ 成功 step-up
			# 保持水平速度，清除垂直分量（已經在台階上了）
			velocity.y = 0.0
			if step_debug:
				print("[StepUp] ✅ 三階段 step-up 成功! height=%.3f" % step_height)
			return true
		elif step_height <= 0.02:
			# 沒有實際上升（可能只是地面微調），此為有效移動
			velocity.y = 0.0
			return true
		else:
			# 台階太高，恢復位置
			if step_debug:
				print("[StepUp] ⚠️ 台階高度超出範圍 step_height=%.3f (max=%.2f)" % [step_height, max_step_height])
			global_position = saved_pos
			return false
	else:
		# 沒碰到地面 → 懸空了，恢復位置
		if step_debug:
			print("[StepUp] ⚠️ 向下未碰到地面，恢復位置")
		global_position = saved_pos
		return false
