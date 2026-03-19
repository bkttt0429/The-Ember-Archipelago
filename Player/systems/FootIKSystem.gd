extends Node3D
class_name FootIKSystem

## Foot IK System for Godot 4.6+
## Uses TwoBoneIK3D to adapt feet to terrain while blending with animation swing phases.

@export_group("Skeleton Setup")
@export var skeleton_path: NodePath
@export var left_hip_bone: String = "mixamorig1_LeftUpLeg"
@export var left_foot_bone: String = "mixamorig1_LeftFoot"
@export var right_hip_bone: String = "mixamorig1_RightUpLeg"
@export var right_foot_bone: String = "mixamorig1_RightFoot"
@export var hips_bone: String = "mixamorig1_Hips"

@export_group("Animation Integration")
@export var animation_tree_path: NodePath
@export var left_sole_path: NodePath
@export var right_sole_path: NodePath
@export var foot_height_offset: float = 0.08
@export var stance_height_min: float = 0.02
@export var stance_height_max: float = 0.08
@export var moving_ik_weight: float = 1.0
@export var standing_ik_weight: float = 1.0
@export var swing_ik_weight: float = 0.15
@export var airborne_ik_weight: float = 0.0
@export var ik_weight_speed: float = 10.0

@export_group("IK Settings")
@export var max_step_up: float = 0.3
@export var max_step_down: float = 0.5
@export var raycast_height: float = 0.35
@export var ray_length: float = 1.2
@export var interpolation_speed: float = 12.0
@export var rotation_speed: float = 8.0
@export var enable_foot_rotation: bool = true
@export var enable_pelvis_adjustment: bool = true
@export var pelvis_max_offset: float = 0.15
@export var foot_forward_axis: Vector3 = Vector3.FORWARD

@export_group("Debug")
@export var debug_draw: bool = false

var _skeleton: Skeleton3D
var _animation_tree: AnimationTree
var _left_sole: Node3D
var _right_sole: Node3D
var _left_ik: Node
var _right_ik: Node
var _left_target: Marker3D
var _right_target: Marker3D

var _left_foot_idx: int = -1
var _right_foot_idx: int = -1
var _left_hip_idx: int = -1
var _right_hip_idx: int = -1
var _hips_idx: int = -1

var _left_foot_offset: float = 0.0
var _right_foot_offset: float = 0.0
var _pelvis_offset: float = 0.0

var _left_anim_foot_y: float = 0.0
var _right_anim_foot_y: float = 0.0
var _left_phase: float = 1.0
var _right_phase: float = 1.0
var _left_ik_weight: float = 1.0
var _right_ik_weight: float = 1.0

var _left_ground_normal: Vector3 = Vector3.UP
var _right_ground_normal: Vector3 = Vector3.UP
var _hips_base_pose: Transform3D = Transform3D.IDENTITY

var _terrain_mask: int = 1
var _initialized: bool = false


class FootGroundHit:
	var point: Vector3
	var normal: Vector3
	var offset: float
	var has_hit: bool

	func _init(p_has_hit: bool = false, p_point: Vector3 = Vector3.ZERO, p_normal: Vector3 = Vector3.UP, p_offset: float = 0.0) -> void:
		has_hit = p_has_hit
		point = p_point
		normal = p_normal
		offset = p_offset


func _ready() -> void:
	if skeleton_path:
		_initialize()


func _initialize() -> void:
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not _skeleton:
		push_error("[FootIKSystem] Skeleton3D not found at path: " + str(skeleton_path))
		return

	_animation_tree = _resolve_animation_tree()
	_left_sole = get_node_or_null(left_sole_path) as Node3D if left_sole_path != NodePath("") else null
	_right_sole = get_node_or_null(right_sole_path) as Node3D if right_sole_path != NodePath("") else null

	_left_foot_idx = _find_bone_with_fallback(left_foot_bone, ["LeftFoot", "mixamorig1_LeftFoot"])
	_right_foot_idx = _find_bone_with_fallback(right_foot_bone, ["RightFoot", "mixamorig1_RightFoot"])
	_left_hip_idx = _find_bone_with_fallback(left_hip_bone, ["LeftUpLeg", "mixamorig1_LeftUpLeg"])
	_right_hip_idx = _find_bone_with_fallback(right_hip_bone, ["RightUpLeg", "mixamorig1_RightUpLeg"])
	_hips_idx = _find_bone_with_fallback(hips_bone, ["Hips", "mixamorig1_Hips"])

	if _left_foot_idx == -1 or _right_foot_idx == -1:
		push_error("[FootIKSystem] Could not find foot bones! Left: %s Right: %s" % [left_foot_bone, right_foot_bone])
		return

	if _hips_idx != -1:
		_hips_base_pose = _skeleton.get_bone_pose(_hips_idx)

	_create_targets()
	_setup_two_bone_ik()
	_reset_targets_to_animation_pose()

	_initialized = true
	print("[FootIKSystem] Initialized with bones: %s / %s" % [left_foot_bone, right_foot_bone])


func _resolve_animation_tree() -> AnimationTree:
	if animation_tree_path != NodePath(""):
		return get_node_or_null(animation_tree_path) as AnimationTree
	var parent_node := get_parent()
	if parent_node:
		return parent_node.find_child("AnimationTree", true, false) as AnimationTree
	return null


func _find_bone_with_fallback(primary_name: String, fallback_names: Array[String]) -> int:
	var idx := _skeleton.find_bone(primary_name)
	if idx != -1:
		return idx
	for fallback_name in fallback_names:
		idx = _skeleton.find_bone(fallback_name)
		if idx != -1:
			return idx
	return -1


func _create_targets() -> void:
	_left_target = Marker3D.new()
	_left_target.name = "LeftFootTarget"
	add_child(_left_target)

	_right_target = Marker3D.new()
	_right_target.name = "RightFootTarget"
	add_child(_right_target)


func _setup_two_bone_ik() -> void:
	if not ClassDB.class_exists("TwoBoneIK3D"):
		push_warning("[FootIKSystem] TwoBoneIK3D not available. Using fallback bone manipulation.")
		return

	if _left_hip_idx != -1:
		_left_ik = ClassDB.instantiate("TwoBoneIK3D")
		_left_ik.name = "LeftLegIK"
		_skeleton.add_child(_left_ik)
		_left_ik.set("root_bone", _left_hip_idx)
		_left_ik.set("tip_bone", _left_foot_idx)
		_left_ik.set("target_node", _left_target.get_path())

	if _right_hip_idx != -1:
		_right_ik = ClassDB.instantiate("TwoBoneIK3D")
		_right_ik.name = "RightLegIK"
		_skeleton.add_child(_right_ik)
		_right_ik.set("root_bone", _right_hip_idx)
		_right_ik.set("tip_bone", _right_foot_idx)
		_right_ik.set("target_node", _right_target.get_path())

	print("[FootIKSystem] TwoBoneIK3D nodes created for both legs")


func _reset_targets_to_animation_pose() -> void:
	if _left_target and _left_foot_idx != -1:
		_left_target.global_transform = _get_animation_foot_transform(_left_foot_idx)
	if _right_target and _right_foot_idx != -1:
		_right_target.global_transform = _get_animation_foot_transform(_right_foot_idx)


func _process(_delta: float) -> void:
	if not _initialized or not _skeleton:
		return
	_update_animation_foot_heights()


func _physics_process(delta: float) -> void:
	if not _initialized or not _skeleton:
		return

	var left_anim_transform := _get_animation_foot_transform(_left_foot_idx)
	var right_anim_transform := _get_animation_foot_transform(_right_foot_idx)

	var left_hit := _detect_ground(_left_foot_idx, _left_sole, left_anim_transform)
	var right_hit := _detect_ground(_right_foot_idx, _right_sole, right_anim_transform)

	_left_ground_normal = left_hit.normal if left_hit.has_hit else Vector3.UP
	_right_ground_normal = right_hit.normal if right_hit.has_hit else Vector3.UP

	_update_foot_phases(delta)
	_update_ik_weights(delta)

	_left_foot_offset = lerpf(_left_foot_offset, left_hit.offset if left_hit.has_hit else 0.0, delta * interpolation_speed)
	_right_foot_offset = lerpf(_right_foot_offset, right_hit.offset if right_hit.has_hit else 0.0, delta * interpolation_speed)

	_update_foot_target(_left_target, left_anim_transform, left_hit, _left_ik_weight, delta)
	_update_foot_target(_right_target, right_anim_transform, right_hit, _right_ik_weight, delta)

	if enable_pelvis_adjustment:
		_update_pelvis(delta)

	_apply_ik_weights()
	_debug_log(left_hit, right_hit)


func _update_animation_foot_heights() -> void:
	if _left_foot_idx != -1:
		_left_anim_foot_y = _get_animation_foot_transform(_left_foot_idx).origin.y
	if _right_foot_idx != -1:
		_right_anim_foot_y = _get_animation_foot_transform(_right_foot_idx).origin.y


func _get_animation_foot_transform(foot_idx: int) -> Transform3D:
	if foot_idx == -1:
		return global_transform
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(foot_idx)


func _get_sampling_origin(foot_idx: int, sole_node: Node3D, anim_transform: Transform3D) -> Vector3:
	if sole_node:
		return sole_node.global_position
	return anim_transform.origin


func _detect_ground(foot_idx: int, sole_node: Node3D, anim_transform: Transform3D) -> FootGroundHit:
	if foot_idx == -1:
		return FootGroundHit.new()

	var sample_origin := _get_sampling_origin(foot_idx, sole_node, anim_transform)
	var ray_origin := sample_origin + Vector3.UP * raycast_height
	var ray_end := ray_origin + Vector3.DOWN * ray_length

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = _terrain_mask
	var exclude: Array[RID] = []
	var parent_node := get_parent()
	if parent_node is CollisionObject3D:
		exclude.append(parent_node.get_rid())
	query.exclude = exclude

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return FootGroundHit.new()

	var hit_point: Vector3 = result.position
	var offset := clampf(hit_point.y - sample_origin.y, -max_step_down, max_step_up)
	return FootGroundHit.new(true, hit_point, result.normal.normalized(), offset)


func _update_foot_phases(delta: float) -> void:
	var left_target_phase := _compute_foot_phase(_left_anim_foot_y)
	var right_target_phase := _compute_foot_phase(_right_anim_foot_y)

	if _is_airborne_state():
		left_target_phase = 0.0
		right_target_phase = 0.0

	_left_phase = lerpf(_left_phase, left_target_phase, delta * 12.0)
	_right_phase = lerpf(_right_phase, right_target_phase, delta * 12.0)

	if _is_moving_state() and _left_phase < 0.3 and _right_phase < 0.3:
		if _left_anim_foot_y <= _right_anim_foot_y:
			_left_phase = maxf(_left_phase, 0.8)
		else:
			_right_phase = maxf(_right_phase, 0.8)


func _compute_foot_phase(anim_foot_y: float) -> float:
	var body_y: float = get_parent().global_position.y if get_parent() else global_position.y
	var above: float = (anim_foot_y - body_y) - foot_height_offset
	return 1.0 - clampf((above - stance_height_min) / maxf(stance_height_max - stance_height_min, 0.001), 0.0, 1.0)


func _update_ik_weights(delta: float) -> void:
	var base_weight := standing_ik_weight
	if _is_airborne_state():
		base_weight = airborne_ik_weight
	elif _is_moving_state():
		base_weight = moving_ik_weight

	var left_target_weight := base_weight
	var right_target_weight := base_weight

	if _is_airborne_state():
		left_target_weight = airborne_ik_weight
		right_target_weight = airborne_ik_weight
	else:
		left_target_weight = lerpf(swing_ik_weight, base_weight, _left_phase)
		right_target_weight = lerpf(swing_ik_weight, base_weight, _right_phase)

	_left_ik_weight = lerpf(_left_ik_weight, clampf(left_target_weight, 0.0, 1.0), delta * ik_weight_speed)
	_right_ik_weight = lerpf(_right_ik_weight, clampf(right_target_weight, 0.0, 1.0), delta * ik_weight_speed)


func _update_foot_target(target: Marker3D, anim_transform: Transform3D, hit: FootGroundHit, ik_weight: float, delta: float) -> void:
	if not target:
		return

	var target_origin := anim_transform.origin
	if hit.has_hit:
		target_origin += Vector3.UP * hit.offset * ik_weight

	var smooth_weight := clampf(delta * interpolation_speed, 0.0, 1.0)
	target.global_position = target.global_position.lerp(target_origin, smooth_weight)

	if enable_foot_rotation:
		var basis_target := anim_transform.basis
		if hit.has_hit and ik_weight > 0.01:
			basis_target = _build_ground_aligned_basis(anim_transform.basis, hit.normal, ik_weight)
		target.global_basis = target.global_basis.slerp(basis_target.orthonormalized(), clampf(delta * rotation_speed, 0.0, 1.0))
	else:
		target.global_basis = target.global_basis.slerp(anim_transform.basis.orthonormalized(), clampf(delta * rotation_speed, 0.0, 1.0))


func _build_ground_aligned_basis(anim_basis: Basis, ground_normal: Vector3, blend_weight: float) -> Basis:
	var normal := ground_normal.normalized()
	if normal.length_squared() < 0.001:
		return anim_basis.orthonormalized()

	var forward := anim_basis * foot_forward_axis
	var tangent := (forward - normal * forward.dot(normal)).normalized()
	if tangent.length_squared() < 0.001:
		tangent = (anim_basis.z - normal * anim_basis.z.dot(normal)).normalized()
	if tangent.length_squared() < 0.001:
		tangent = Vector3.FORWARD.cross(normal).normalized()
	if tangent.length_squared() < 0.001:
		tangent = Vector3.RIGHT

	var right := normal.cross(tangent).normalized()
	if right.length_squared() < 0.001:
		right = anim_basis.x.normalized()

	var aligned_basis := Basis(right, normal, tangent).orthonormalized()
	return anim_basis.orthonormalized().slerp(aligned_basis, clampf(blend_weight, 0.0, 1.0))


func _update_pelvis(delta: float) -> void:
	if _hips_idx == -1:
		return

	var target_offset := minf(_left_foot_offset * _left_phase, _right_foot_offset * _right_phase)
	target_offset = clampf(target_offset, -pelvis_max_offset, pelvis_max_offset)
	_pelvis_offset = lerpf(_pelvis_offset, target_offset, delta * interpolation_speed * 0.5)

	var hips_pose := _hips_base_pose
	hips_pose.origin.y = _hips_base_pose.origin.y + _pelvis_offset
	_skeleton.set_bone_pose(_hips_idx, hips_pose)


func _apply_ik_weights() -> void:
	if _left_ik:
		_left_ik.set("influence", _left_ik_weight)
		_left_ik.set("active", _left_ik_weight > 0.001)
	if _right_ik:
		_right_ik.set("influence", _right_ik_weight)
		_right_ik.set("active", _right_ik_weight > 0.001)


func _is_moving_state() -> bool:
	if not _animation_tree:
		return false
	var value = _animation_tree.get("parameters/conditions/is_moving")
	return value is bool and value


func _is_airborne_state() -> bool:
	if not _animation_tree:
		return false
	var is_airborne = _animation_tree.get("parameters/conditions/is_airborne")
	if is_airborne is bool and is_airborne:
		return true
	var is_jumping = _animation_tree.get("parameters/conditions/is_jumping")
	if is_jumping is bool and is_jumping:
		return true
	var is_landing = _animation_tree.get("parameters/conditions/is_landing")
	return is_landing is bool and is_landing


func _debug_log(left_hit: FootGroundHit, right_hit: FootGroundHit) -> void:
	if not debug_draw:
		return
	if Engine.get_physics_frames() % 60 != 0:
		return
	print("[FootIK] L phase=%.2f w=%.2f hit=%s y=%.3f n=(%.2f,%.2f,%.2f) | R phase=%.2f w=%.2f hit=%s y=%.3f n=(%.2f,%.2f,%.2f)" % [
		_left_phase, _left_ik_weight, left_hit.has_hit, left_hit.point.y, _left_ground_normal.x, _left_ground_normal.y, _left_ground_normal.z,
		_right_phase, _right_ik_weight, right_hit.has_hit, right_hit.point.y, _right_ground_normal.x, _right_ground_normal.y, _right_ground_normal.z
	])


func set_terrain_mask(mask: int) -> void:
	_terrain_mask = mask


func set_enabled(enabled: bool) -> void:
	set_process(enabled)
	set_physics_process(enabled)

	if _left_ik:
		_left_ik.set("active", enabled)
	if _right_ik:
		_right_ik.set("active", enabled)


func reset() -> void:
	_left_foot_offset = 0.0
	_right_foot_offset = 0.0
	_pelvis_offset = 0.0
	_left_phase = 1.0
	_right_phase = 1.0
	_left_ik_weight = standing_ik_weight
	_right_ik_weight = standing_ik_weight
	if _hips_idx != -1:
		_skeleton.set_bone_pose(_hips_idx, _hips_base_pose)
	_reset_targets_to_animation_pose()
