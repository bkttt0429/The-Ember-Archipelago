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

@export_group("Settings (設定)")
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -85.0
@export var max_pitch: float = 85.0

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
