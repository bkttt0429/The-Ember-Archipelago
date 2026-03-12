extends RefCounted
class_name CameraSystem

## 相機系統 - 第三人稱相機控制
## 功能：平滑跟隨、動態FOV、碰撞避障、衝刺效果

var ecs_world: Node = null

# 相機平滑設定
var _smooth_velocity := Vector3.ZERO
var _smooth_rotation := 0.0

# FOV 設定
const BASE_FOV := 60.0
const SPRINT_FOV := 75.0
const SWIM_FOV := 55.0
const FOV_SMOOTH_SPEED := 8.0

# 相機晃動
var _shake_amount := 0.0
var _shake_decay := 5.0

func set_world(world: Node) -> void:
	ecs_world = world

func update(delta: float) -> void:
	if not ecs_world: return
	
	var camera_mount = ecs_world.get("camera_mount") as Node3D
	if not camera_mount: return
	
	var movement = ecs_world.get_component(ecs_world.get_instance_id(), "MovementState")
	var physics = ecs_world.get_component(ecs_world.get_instance_id(), "PhysicsComponent")
	
	# 取得 Camera3D (SpringArm3D 的子節點)
	var spring_arm = camera_mount.get_child(0) as SpringArm3D
	var camera: Camera3D = null
	if spring_arm:
		camera = spring_arm.get_child(0) as Camera3D
	
	if not camera: return
	
	# === 1. 動態 FOV ===
	var target_fov := BASE_FOV
	if movement:
		match movement.mode:
			"sprint":
				target_fov = SPRINT_FOV
			"swim":
				target_fov = SWIM_FOV
			"walk":
				target_fov = BASE_FOV - 5.0 # 走路時稍微縮小
	
	# 根據速度微調 FOV
	if physics:
		var speed = Vector2(physics.velocity.x, physics.velocity.z).length()
		target_fov += clamp(speed * 0.5, 0, 10) # 速度加成
	
	camera.fov = lerp(camera.fov, target_fov, FOV_SMOOTH_SPEED * delta)
	
	# === 2. 相機晃動效果 ===
	if _shake_amount > 0:
		var shake_offset = Vector3(
			randf_range(-1, 1) * _shake_amount,
			randf_range(-1, 1) * _shake_amount * 0.5,
			0
		)
		camera.position = camera.position.lerp(Vector3(0, 0, spring_arm.spring_length if spring_arm else 4) + shake_offset, 0.5)
		_shake_amount = max(0, _shake_amount - _shake_decay * delta)
	
	# === 3. SpringArm 動態長度 (可選) ===
	if spring_arm and movement:
		var target_length := 4.0
		if movement.mode == "combat":
			target_length = 2.5 # 戰鬥模式拉近
		elif movement.mode == "sprint":
			target_length = 5.0 # 衝刺拉遠
		
		spring_arm.spring_length = lerp(spring_arm.spring_length, target_length, 3.0 * delta)

## 觸發相機晃動
func shake(intensity: float = 0.3) -> void:
	_shake_amount = intensity

## 設置相機模式
func set_camera_mode(mode: String) -> void:
	# 可擴展：切換第一人稱/第三人稱等
	pass
