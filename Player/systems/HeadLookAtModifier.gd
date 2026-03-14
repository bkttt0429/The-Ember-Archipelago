extends SkeletonModifier3D
class_name HeadLookAtModifier

## 使用 SkeletonModifier3D 實現頭部追蹤
## 這是 Godot 4.3+ 的正確方式，在動畫處理後執行

@export var look_speed: float = 5.0
@export var max_yaw: float = 50.0
@export var max_pitch: float = 30.0
@export var blend_weight: float = 0.8
@export var debug: bool = true
@export var show_debug_sphere: bool = false  # ★ 預設關閉，避免洩漏到場景根節點

var _head_bone_idx: int = -1
var _current_rotation: Vector2 = Vector2.ZERO
var _target_rotation: Vector2 = Vector2.ZERO
var _look_target: Vector3 = Vector3.ZERO
var _player: CharacterBody3D
var _debug_mesh: MeshInstance3D
var _frame_count: int = 0
var _initialized: bool = false

func _ready():
	# ★ 修復 #1：不使用 await（coroutine 在場景早期卸載時不清理，導致 C++ 崩潰）
	# 改用 call_deferred，確保在本幀所有 Node._ready() 都跑完後才初始化
	active = false  # ★ 必須在初始化完成前保持關閉，防止 C++ Quaternion 零向量崩潰
	call_deferred("_initialize")

func _initialize():
	var skeleton = get_skeleton()
	if not skeleton:
		push_error("[HeadLookAtModifier] No skeleton found!")
		return

	_head_bone_idx = skeleton.find_bone("Head")
	if _head_bone_idx < 0:
		push_error("[HeadLookAtModifier] Head bone not found!")
		return

	# 找到 Player 節點
	var node = self
	while node:
		if node is CharacterBody3D:
			_player = node
			break
		node = node.get_parent()

	if not _player:
		push_error("[HeadLookAtModifier] Player not found!")
		return

	# 創建調試球體（只在需要時建立）
	if show_debug_sphere:
		_debug_mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.1
		sphere.height = 0.2
		_debug_mesh.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.GREEN
		mat.emission_enabled = true
		mat.emission = Color.GREEN
		mat.emission_energy_multiplier = 2.0
		_debug_mesh.material_override = mat
		get_tree().root.add_child(_debug_mesh)

	_initialized = true
	# ★ 不在此處設定 active = true
	# SimpleFootIK 的 _process 會在安全時機（0.5秒後，且目標已與臀部拉開距離）才啟動
	# 如果找不到 SimpleFootIK，這裡提供 fallback：2 秒後保護性啟用
	get_tree().create_timer(2.0).timeout.connect(_safe_activate)
	print("[HeadLookAtModifier] Ready! Head: %d" % _head_bone_idx)

func _safe_activate():
	if _initialized and not active:
		active = true
		print("[HeadLookAtModifier] Safe activate triggered.")

func _process(delta):
	if not active or not _player or not _initialized:
		return

	_update_target_rotation()
	_current_rotation = _current_rotation.lerp(_target_rotation, delta * look_speed)

	if show_debug_sphere and _debug_mesh:
		_debug_mesh.global_position = _look_target

	_frame_count += 1
	if debug and _frame_count % 60 == 0:
		print("[HeadLookAtModifier] Yaw: %.1f°" % rad_to_deg(_current_rotation.x))

func _process_modification() -> void:
	# 這個方法在動畫處理完成後被骨架調用
	if not _initialized:
		return
	var skeleton = get_skeleton()
	if not skeleton or _head_bone_idx < 0:
		return

	var yaw = _current_rotation.x * blend_weight
	var pitch = _current_rotation.y * blend_weight

	# 如果旋轉量幾乎為零，直接跳過（避免傳入 Quaternion.from_euler(Vector3.ZERO) 的低精度值）
	if abs(yaw) < 0.001 and abs(pitch) < 0.001:
		return

	# 獲取當前骨骼姿勢
	var current_pose = skeleton.get_bone_pose(_head_bone_idx)
	var current_rot = current_pose.basis.get_rotation_quaternion()

	# ★ 安全守衛：基於退化 Basis 的 Quaternion 可能出 NaN
	if not current_rot.is_normalized():
		return

	# 創建附加旋轉
	var add_quat = Quaternion.from_euler(Vector3(-pitch, yaw, 0))

	# 組合旋轉
	var new_rotation = current_rot * add_quat
	skeleton.set_bone_pose_rotation(_head_bone_idx, new_rotation)

func _update_target_rotation():
	var camera = get_viewport().get_camera_3d()
	if not camera or not _player:
		_target_rotation = Vector2.ZERO
		return

	var camera_forward = -camera.global_transform.basis.z
	var ray_origin = camera.global_position

	_look_target = ray_origin + camera_forward * 20.0

	var head_world_pos = _player.global_position + Vector3(0, 1.6, 0)
	var raw_dir = _look_target - head_world_pos

	# ★ 修復 #2：防止 look_dir 為零向量（目標與頭部重疊時會崩潰）
	if raw_dir.length_squared() < 0.0001:
		_target_rotation = Vector2.ZERO
		return
	var look_dir = raw_dir.normalized()

	var player_forward = _player.global_transform.basis.z
	var player_right = _player.global_transform.basis.x
	var player_up = _player.global_transform.basis.y

	var local_forward = look_dir.dot(player_forward)
	var local_right = look_dir.dot(player_right)
	var local_up = look_dir.dot(player_up)

	if local_forward > 0.1:
		var yaw = atan2(-local_right, local_forward)
		var pitch = asin(clamp(local_up, -1.0, 1.0))
		yaw = clamp(yaw, deg_to_rad(-max_yaw), deg_to_rad(max_yaw))
		pitch = clamp(pitch, deg_to_rad(-max_pitch), deg_to_rad(max_pitch))
		_target_rotation = Vector2(yaw, pitch)
	else:
		_target_rotation = Vector2.ZERO

func _exit_tree():
	if _debug_mesh and is_instance_valid(_debug_mesh):
		_debug_mesh.queue_free()
