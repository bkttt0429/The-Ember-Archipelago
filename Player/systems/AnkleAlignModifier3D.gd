@tool
class_name AnkleAlignModifier3D
extends SkeletonModifier3D
## 腳踝旋轉對齊修正器（SkeletonModifier3D）
##
## ★ 必須放在 Skeleton3D 的子節點中，且排在 TwoBoneIK3D 之後 ★
## 這樣才能在 IK 解算完成後修正腳踝旋轉，不會產生回饋迴圈。
##
## 工作原理：
##   1. 從 RayCast3D 取得地面法線（或從外部設定）
##   2. 將法線轉換到骨架空間
##   3. 構建「腳底貼地」的目標旋轉，保留動畫 yaw
##   4. 用 slerp 平滑混合
##   5. 寫入 bone pose rotation
##
## 用法：
##   1. 在 Skeleton3D 下加入此節點（排在 TwoBoneIK3D 之後）
##   2. 設定 left/right_foot_bone 名稱
##   3. 設定 left/right_raycast（可選，自動偵測地面法線）
##   4. 或者從外部腳本設定 left/right_ground_normal

@export_group("Bone Setup")
@export var left_foot_bone: String = "LeftFoot"
@export var right_foot_bone: String = "RightFoot"

@export_group("Raycasts (Optional)")
## 如果設定了 RayCast3D，會自動從碰撞點取得地面法線
@export var left_raycast: RayCast3D
@export var right_raycast: RayCast3D

@export_group("Tuning")
## 混合強度（0=不對齊, 1=完全對齊）
@export_range(0.0, 1.0) var blend_strength: float = 0.7
## 平滑速度（越大越快跟隨）
@export_range(1.0, 30.0) var smooth_speed: float = 12.0
## 最小傾斜角度（低於此角度不做旋轉）
@export_range(0.0, 15.0) var min_tilt_degrees: float = 2.0

## 外部可直接設定的地面法線（如果不用 RayCast3D）
var left_ground_normal: Vector3 = Vector3.UP
var right_ground_normal: Vector3 = Vector3.UP

## 外部可控制的 IK 權重（跟 TwoBoneIK 的 influence 同步）
var left_ik_weight: float = 1.0
var right_ik_weight: float = 1.0

# 內部
var _left_idx: int = -1
var _right_idx: int = -1
var _left_smooth_rot: Quaternion = Quaternion.IDENTITY
var _right_smooth_rot: Quaternion = Quaternion.IDENTITY
var _initialized: bool = false


func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	
	# 延遲初始化（找骨骼索引）
	if not _initialized:
		_left_idx = skel.find_bone(left_foot_bone)
		_right_idx = skel.find_bone(right_foot_bone)
		if _left_idx >= 0 and _right_idx >= 0:
			_initialized = true
			# 初始化平滑旋轉為當前姿勢
			_left_smooth_rot = skel.get_bone_pose_rotation(_left_idx)
			_right_smooth_rot = skel.get_bone_pose_rotation(_right_idx)
		else:
			push_warning("[AnkleAlign] Bones not found: %s(%d) / %s(%d)" % [
				left_foot_bone, _left_idx, right_foot_bone, _right_idx])
			return
	
	# 從 RayCast3D 取得法線（如果有設定）
	if left_raycast and left_raycast.is_colliding():
		left_ground_normal = left_raycast.get_collision_normal()
	if right_raycast and right_raycast.is_colliding():
		right_ground_normal = right_raycast.get_collision_normal()
	
	var dt := get_physics_process_delta_time()
	
	# 處理左腳
	if _left_idx >= 0 and left_ik_weight > 0.01:
		_align_foot(skel, _left_idx, left_ground_normal, left_ik_weight, dt, true)
	
	# 處理右腳
	if _right_idx >= 0 and right_ik_weight > 0.01:
		_align_foot(skel, _right_idx, right_ground_normal, right_ik_weight, dt, false)


func _align_foot(skel: Skeleton3D, bone_idx: int, ground_normal: Vector3, 
		ik_weight: float, dt: float, is_left: bool) -> void:
	
	# 超小角度（幾乎水平面）→ 漸進回到原始旋轉
	var tilt_angle := ground_normal.angle_to(Vector3.UP)
	if tilt_angle < deg_to_rad(min_tilt_degrees):
		# 慢慢回到 IK 解算的原始旋轉
		var current_pose_rot := skel.get_bone_pose_rotation(bone_idx)
		if is_left:
			_left_smooth_rot = _left_smooth_rot.slerp(current_pose_rot, 1.0 - exp(-smooth_speed * dt))
		else:
			_right_smooth_rot = _right_smooth_rot.slerp(current_pose_rot, 1.0 - exp(-smooth_speed * dt))
		return
	
	# 1. 將世界空間法線轉換到骨架空間
	var skel_inv_basis := skel.global_transform.basis.inverse()
	var raw_local := skel_inv_basis * ground_normal
	if raw_local.is_zero_approx():
		return
	var local_normal := raw_local.normalized()
	
	# 2. 取得 IK 處理後的腳骨姿勢（骨架空間）
	var bone_global_pose := skel.get_bone_global_pose(bone_idx)
	var bone_basis := bone_global_pose.basis.orthonormalized()
	if bone_basis.determinant() < 0.001:
		return  # 退化 basis
	var current_global_rot := bone_basis.get_rotation_quaternion()
	
	# 3. 計算腳骨 forward（骨架空間），投影到水平面保留 yaw
	var foot_forward := bone_global_pose.basis.z.normalized()
	var foot_forward_flat := Vector3(foot_forward.x, 0, foot_forward.z).normalized()
	if foot_forward_flat.length_squared() < 0.001:
		foot_forward_flat = Vector3.FORWARD
	
	# 4. 用地面法線構建目標 Basis（保留 yaw）
	var target_up := local_normal
	var raw_right := foot_forward_flat.cross(target_up)
	if raw_right.is_zero_approx():
		return
	var target_right := raw_right.normalized()
	var raw_forward := target_up.cross(target_right)
	if raw_forward.is_zero_approx():
		return
	var target_forward := raw_forward.normalized()
	
	var target_basis := Basis(target_right, target_up, target_forward).orthonormalized()
	if target_basis.determinant() < 0.001:
		return  # 退化 basis
	var target_global_rot := target_basis.get_rotation_quaternion()
	
	# 5. 混合：IK 旋轉 → 對齊旋轉
	var effective_blend := ik_weight * blend_strength
	# 安全檢查：確保兩個 quaternion 都是有效的
	if current_global_rot.length_squared() < 0.001 or target_global_rot.length_squared() < 0.001:
		return
	var blended_global_rot := current_global_rot.slerp(target_global_rot, effective_blend)
	
	# 6. 轉換回 bone-local 旋轉
	var parent_idx := skel.get_bone_parent(bone_idx)
	var parent_global_rot: Quaternion
	if parent_idx >= 0:
		parent_global_rot = skel.get_bone_global_pose(parent_idx).basis.get_rotation_quaternion()
	else:
		parent_global_rot = Quaternion.IDENTITY
	
	var rest := skel.get_bone_rest(bone_idx)
	var rest_rot := rest.basis.get_rotation_quaternion()
	
	# bone_pose_rotation = rest_inv * parent_global_inv * final_global
	var local_rot := rest_rot.inverse() * parent_global_rot.inverse() * blended_global_rot
	
	# 7. 平滑（避免突變抖動）
	if is_left:
		_left_smooth_rot = _left_smooth_rot.slerp(local_rot, 1.0 - exp(-smooth_speed * dt))
		skel.set_bone_pose_rotation(bone_idx, _left_smooth_rot)
	else:
		_right_smooth_rot = _right_smooth_rot.slerp(local_rot, 1.0 - exp(-smooth_speed * dt))
		skel.set_bone_pose_rotation(bone_idx, _right_smooth_rot)
