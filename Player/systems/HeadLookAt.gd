extends Node3D
class_name HeadLookAt

## 程序化頭部追蹤 - 帶射線可視化

@export var enabled: bool = true
@export var look_speed: float = 5.0
@export var max_yaw: float = 50.0
@export var max_pitch: float = 30.0
@export var blend_weight: float = 0.8
@export var debug: bool = true
@export var show_debug_ray: bool = true

var _skeleton: Skeleton3D
var _head_bone_idx: int = -1
var _player: CharacterBody3D
var _current_rotation: Vector2 = Vector2.ZERO
var _target_rotation: Vector2 = Vector2.ZERO
var _initialized: bool = false
var _frame_count: int = 0
var _look_target: Vector3 = Vector3.ZERO
var _debug_mesh: MeshInstance3D

func _ready():
	# 創建調試用的球體
	if show_debug_ray:
		_debug_mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		_debug_mesh.mesh = sphere
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.RED
		mat.emission_enabled = true
		mat.emission = Color.RED
		mat.emission_energy_multiplier = 5.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_debug_mesh.material_override = mat
		
		# 使用 call_deferred 添加子節點
		get_tree().root.call_deferred("add_child", _debug_mesh)
		print("[HeadLookAt] Debug sphere created")
	
	await get_tree().create_timer(0.5).timeout
	_initialize()

func _initialize():
	_player = get_parent() as CharacterBody3D
	if not _player:
		push_error("[HeadLookAt] Parent is not CharacterBody3D")
		return
	
	var mannequin = _player.get_node_or_null("Visuals/Characters_Mannequin")
	if mannequin:
		_skeleton = _find_skeleton(mannequin)
	
	if not _skeleton:
		push_error("[HeadLookAt] Could not find Skeleton3D")
		return
	
	_head_bone_idx = _skeleton.find_bone("Head")
	if _head_bone_idx < 0:
		push_error("[HeadLookAt] Could not find Head bone")
		return
	
	# 連接 skeleton_updated 信號
	if not _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	
	_initialized = true
	print("[HeadLookAt] Ready! Head: %d (Using skeleton_updated signal)" % _head_bone_idx)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

func _process(delta):
	if not _initialized or not enabled:
		return
	
	_update_target_rotation()
	_current_rotation = _current_rotation.lerp(_target_rotation, delta * look_speed)
	
	# 更新調試球體位置
	if show_debug_ray and _debug_mesh and _debug_mesh.is_inside_tree():
		_debug_mesh.global_position = _look_target
	
	_frame_count += 1
	if debug and _frame_count % 60 == 0:
		var sphere_info = "Sphere: N/A"
		if _debug_mesh and _debug_mesh.is_inside_tree():
			sphere_info = "Sphere: %s" % _debug_mesh.global_position
		print("[HeadLookAt] Yaw: %.1f° Target: %s %s" % [rad_to_deg(_current_rotation.x), _look_target, sphere_info])

func _update_target_rotation():
	var camera = get_viewport().get_camera_3d()
	if not camera or not _player:
		_target_rotation = Vector2.ZERO
		return
	
	# 使用相機的前方方向
	var camera_forward = - camera.global_transform.basis.z
	
	# 計算目標點：距離玩家頭部 5 米
	var head_world_pos = _player.global_position + Vector3(0, 1.6, 0)
	_look_target = head_world_pos + camera_forward * 5.0
	
	var look_dir = (_look_target - head_world_pos).normalized()
	
	# 使用玩家的本地座標系
	var player_forward = - _player.global_transform.basis.z # 注意負號
	var player_right = _player.global_transform.basis.x
	var player_up = _player.global_transform.basis.y
	
	var local_forward = look_dir.dot(player_forward)
	var local_right = look_dir.dot(player_right)
	var local_up = look_dir.dot(player_up)
	
	# 調試輸出
	if debug and _frame_count % 120 == 0:
		print("[HeadLookAt] local_forward: %.2f, local_right: %.2f" % [local_forward, local_right])
	
	# 計算 yaw 和 pitch（不管面向）
	var yaw = atan2(local_right, local_forward)
	var pitch = asin(clamp(local_up, -1.0, 1.0))
	yaw = clamp(yaw, deg_to_rad(-max_yaw), deg_to_rad(max_yaw))
	pitch = clamp(pitch, deg_to_rad(-max_pitch), deg_to_rad(max_pitch))
	_target_rotation = Vector2(yaw, pitch)

func _on_skeleton_updated():
	if not enabled or _head_bone_idx < 0:
		return
		
	# 在這裡直接修改骨骼姿勢，不需要使用 pose override
	# 因為這是最後階段，直接 set_bone_pose 會生效
	
	var yaw = _current_rotation.x * blend_weight
	var pitch = _current_rotation.y * blend_weight
	
	# 獲取當前姿勢（已經包含動畫）
	var current_pose = _skeleton.get_bone_pose(_head_bone_idx)
	var current_rot = current_pose.basis.get_rotation_quaternion()
	
	# 創建附加旋轉
	var add_quat = Quaternion.from_euler(Vector3(-pitch, yaw, 0))
	
	# 組合旋轉
	var new_rotation = current_rot * add_quat
	
	# 直接設定當前姿勢
	_skeleton.set_bone_pose_rotation(_head_bone_idx, new_rotation)

func _exit_tree():
	if _debug_mesh and is_instance_valid(_debug_mesh):
		_debug_mesh.queue_free()
