extends Node3D
class_name LookAtTargetController

## 控制 LookAtModifier3D 的目標位置
## 讓頭部跟隨相機方向

@export var distance: float = 5.0
@export var height_offset: float = 0.0
@export var smoothing: float = 10.0
@export var debug: bool = false

var _player: CharacterBody3D
var _target_pos: Vector3 = Vector3.ZERO

func _ready():
	await get_tree().create_timer(0.3).timeout
	_player = get_parent() as CharacterBody3D
	if _player:
		print("[LookAtTargetController] Ready!")
	else:
		push_error("[LookAtTargetController] Parent is not CharacterBody3D")

func _process(delta):
	if not _player:
		return
	
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	# 計算目標位置：從頭部沿相機方向延伸
	var head_pos = _player.global_position + Vector3(0, 1.6 + height_offset, 0)
	var camera_forward = - camera.global_transform.basis.z
	
	_target_pos = head_pos + camera_forward * distance
	
	# 平滑移動
	global_position = global_position.lerp(_target_pos, delta * smoothing)
	
	if debug and Engine.get_process_frames() % 60 == 0:
		print("[LookAtTarget] Position: %s" % global_position)
