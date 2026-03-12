extends Node3D
class_name OrientationWarpingSystem
## 朝向變形系統 (Orientation Warping)
## 改編自 AMSG PoseWarping.gd — 讓下半身朝向移動方向，上半身保持面向相機
## 
## 用法：
## 1. 添加為 Player 的子節點 (任意位置)
## 2. 設定 character_node (指向 PlayerController)
## 3. 設定 skeleton_path (指向 Skeleton3D)
## 4. 骨骼名稱通常不需要修改 (預設為 Mixamo 命名)

@export_group("References (參照)")
## 角色物理節點 (PlayerController / CharacterBody3D)
@export var character_node: CharacterBody3D
## 路徑指向 Skeleton3D 節點
@export var skeleton_path: NodePath

@export_group("Bone Names (骨骼名稱)")
## 臀部骨骼名稱 — 此骨骼將朝向移動方向旋轉
@export var hips_bone: String = "Hips"
## 脊柱骨骼名稱陣列 — 這些骨骼會反向旋轉，保持上半身穩定
@export var spine_bones: PackedStringArray = ["Spine", "Spine1", "Spine2"]

@export_group("Settings (設定)")
## 啟用朝向變形
@export var orientation_enabled: bool = true
## 平滑速度 (越高越快跟隨)
@export var smooth_speed: float = 10.0
## 最大朝向角度 (degrees) — 超過此範圍不做變形
@export var max_orientation_angle: float = 90.0
## 最低速度閾值 — 低於此速度不做變形 (避免靜止時旋轉)
@export var min_speed_threshold: float = 0.5

# 內部狀態
var _skeleton: Skeleton3D
var _hips_idx: int = -1
var _spine_indices: Array[int] = []
var _current_orientation: float = 0.0 # 當前平滑後的朝向角度 (radians)
var _initialized: bool = false

func _ready() -> void:
	# 延遲初始化，等場景完全加載
	call_deferred("_deferred_init")

func _deferred_init() -> void:
	# 查找 Skeleton3D
	if skeleton_path:
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	
	# 如果沒指定路徑，自動搜尋
	if not _skeleton and character_node:
		_skeleton = _find_skeleton(character_node)
	
	if not _skeleton:
		push_warning("[OrientationWarping] 找不到 Skeleton3D — 請設定 skeleton_path")
		return
	
	# 查找骨骼索引
	_hips_idx = _skeleton.find_bone(hips_bone)
	if _hips_idx == -1:
		push_warning("[OrientationWarping] 找不到 Hips 骨骼: %s" % hips_bone)
		return
	
	_spine_indices.clear()
	for bone_name in spine_bones:
		var idx = _skeleton.find_bone(bone_name)
		if idx != -1:
			_spine_indices.append(idx)
		else:
			push_warning("[OrientationWarping] 找不到 Spine 骨骼: %s (跳過)" % bone_name)
	
	_initialized = true
	print("[OrientationWarping] ✓ 初始化完成 — Hips: %s(idx=%d), Spine bones: %d 個, Skeleton: %s" % [
		hips_bone, _hips_idx, _spine_indices.size(), _skeleton.name
	])

func _physics_process(delta: float) -> void:
	if not orientation_enabled or not _initialized or not character_node:
		return
	
	# 1. 取得角色水平速度
	var horizontal_velocity = Vector3(
		character_node.velocity.x,
		0.0,
		character_node.velocity.z
	)
	var speed = horizontal_velocity.length()
	
	# 速度太低時不做變形 (靜止或幾乎靜止)
	if speed < min_speed_threshold:
		# 平滑歸零
		_current_orientation = lerp(_current_orientation, 0.0, delta * smooth_speed)
		if absf(_current_orientation) > 0.001:
			_apply_rotation()
		return
	
	# 2. 計算角色面向方向 vs 速度方向的夾角
	var velocity_dir = horizontal_velocity.normalized()
	
	# 角色面向方向 (CharacterBody3D 的 -Z 方向)
	var character_forward = - character_node.global_transform.basis.z
	character_forward.y = 0
	character_forward = character_forward.normalized()
	
	# 計算帶符號角度 (向左為正，向右為負)
	var angle = character_forward.signed_angle_to(velocity_dir, Vector3.UP)
	
	# 限制在最大角度範圍內
	angle = clampf(angle, deg_to_rad(-max_orientation_angle), deg_to_rad(max_orientation_angle))
	
	# 3. 平滑過渡
	_current_orientation = lerp(_current_orientation, angle, delta * smooth_speed)
	
	# 4. 應用旋轉
	_apply_rotation()

func _apply_rotation() -> void:
	if absf(_current_orientation) < 0.001:
		return # 角度太小，跳過
	
	# A. 旋轉 Hips — 使下半身朝向移動方向
	_rotate_bone_y(_hips_idx, _current_orientation)
	
	# B. 反向旋轉每個 Spine 骨骼 — 使上半身保持穩定
	if _spine_indices.size() > 0:
		var counter_rotation = - _current_orientation / float(_spine_indices.size())
		for spine_idx in _spine_indices:
			_rotate_bone_y(spine_idx, counter_rotation)

func _rotate_bone_y(bone_idx: int, angle_rad: float) -> void:
	if bone_idx < 0:
		return
	
	# 獲取當前骨骼的 pose (動畫播放後的結果)
	var current_pose = _skeleton.get_bone_pose(bone_idx)
	
	# 在 Y 軸上疊加旋轉
	var y_rotation = Quaternion(Vector3.UP, angle_rad)
	current_pose.basis = Basis(y_rotation) * current_pose.basis
	
	# 應用修改後的 pose
	_skeleton.set_bone_pose(bone_idx, current_pose)

## 搜尋 Skeleton3D 節點（支持 GLB 實例）
func _find_skeleton(root: Node) -> Skeleton3D:
	# 先嘗試常見名稱（Mixamo GLB 通常叫 GeneralSkeleton）
	var found = root.find_child("GeneralSkeleton", true, false)
	if found and found is Skeleton3D:
		return found as Skeleton3D
	found = root.find_child("Skeleton3D", true, false)
	if found and found is Skeleton3D:
		return found as Skeleton3D
	# 備援：搜尋所有 Skeleton3D 類型的子節點
	for child in root.get_children():
		if child is Skeleton3D:
			return child
		var result = _find_skeleton(child)
		if result:
			return result
	return null
