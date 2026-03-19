@tool
class_name AnkleAlignModifier3D
extends SkeletonModifier3D
## 腳踝旋轉對齊修正器 — set_bone_global_pose 法
##
## ★ 必須放在 Skeleton3D 的子節點中，且排在 TwoBoneIK3D 之後 ★

@export_group("Bone Setup")
@export var left_foot_bone: String = "LeftFoot"
@export var right_foot_bone: String = "RightFoot"

@export_group("Raycasts (Optional)")
@export var left_raycast: RayCast3D
@export var right_raycast: RayCast3D

@export_group("Tuning")
@export_range(0.0, 1.0) var blend_strength: float = 1.0
@export_range(1.0, 50.0) var smooth_speed: float = 15.0
@export_range(0.0, 15.0) var min_tilt_degrees: float = 3.0

var left_ground_normal: Vector3 = Vector3.UP
var right_ground_normal: Vector3 = Vector3.UP
var left_ik_weight: float = 1.0
var right_ik_weight: float = 1.0

var _left_idx: int = -1
var _right_idx: int = -1
var _left_active: bool = false
var _right_active: bool = false
var _left_smooth_rot: Quaternion = Quaternion.IDENTITY
var _right_smooth_rot: Quaternion = Quaternion.IDENTITY
var _initialized: bool = false


func _process_modification() -> void:
	var skel := get_skeleton()
	if not skel:
		return
	
	if not _initialized:
		_left_idx = skel.find_bone(left_foot_bone)
		_right_idx = skel.find_bone(right_foot_bone)
		if _left_idx >= 0 and _right_idx >= 0:
			_initialized = true
		else:
			return
	
	if left_raycast and left_raycast.is_colliding():
		left_ground_normal = left_raycast.get_collision_normal()
	if right_raycast and right_raycast.is_colliding():
		right_ground_normal = right_raycast.get_collision_normal()
	
	var dt := get_process_delta_time()
	var skel_inv := skel.global_transform.basis.inverse()
	
	if _left_idx >= 0 and left_ik_weight > 0.01:
		_align_foot(skel, _left_idx, left_ground_normal, left_ik_weight, dt, true, skel_inv)
	if _right_idx >= 0 and right_ik_weight > 0.01:
		_align_foot(skel, _right_idx, right_ground_normal, right_ik_weight, dt, false, skel_inv)


func _align_foot(skel: Skeleton3D, bone_idx: int, ground_normal: Vector3, 
		ik_weight: float, dt: float, is_left: bool, skel_inv: Basis) -> void:
	
	if ground_normal.is_zero_approx():
		return
	
	var bone_global := skel.get_bone_global_pose(bone_idx)
	var current_basis := bone_global.basis.orthonormalized()
	var current_rot := current_basis.get_rotation_quaternion()
	
	var tilt_angle := ground_normal.angle_to(Vector3.UP)
	var foot_was_active := _left_active if is_left else _right_active
	var blend_t := 1.0 - exp(-smooth_speed * dt)
	var smooth_ref := _left_smooth_rot if is_left else _right_smooth_rot
	var smoothed: Quaternion
	
	if tilt_angle < deg_to_rad(min_tilt_degrees):
		# 平地：停用或平滑回歸
		if not foot_was_active:
			return
		smoothed = smooth_ref.slerp(current_rot, blend_t)
		if smoothed.dot(current_rot) > 0.9999:
			if is_left:
				_left_active = false
			else:
				_right_active = false
			return
	else:
		# ★ 斜坡：計算並應用旋轉
		if is_left:
			_left_active = true
		else:
			_right_active = true
		var normal_skel := (skel_inv * ground_normal).normalized()
		var slope_delta := Quaternion(Vector3.UP, normal_skel)
		var blend := ik_weight * blend_strength
		var target_rot := slope_delta * current_rot
		var blended_rot := current_rot.slerp(target_rot, blend)
		smoothed = smooth_ref.slerp(blended_rot, blend_t)
	
	if is_left:
		_left_smooth_rot = smoothed
	else:
		_right_smooth_rot = smoothed
	
	skel.set_bone_global_pose(bone_idx, Transform3D(Basis(smoothed), bone_global.origin))
