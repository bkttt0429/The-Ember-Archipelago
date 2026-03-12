extends Node3D
class_name FootIKSystem
## Foot IK System for Godot 4.6+
## Uses TwoBoneIK3D to adapt feet to terrain
##
## Setup:
## 1. Add this script to a Node under your Player
## 2. Set skeleton_path to your Skeleton3D node
## 3. The system automatically creates IK nodes on _ready()

# Configuration
@export_group("Skeleton Setup")
@export var skeleton_path: NodePath
@export var left_hip_bone: String = "mixamorig1_LeftUpLeg"
@export var left_foot_bone: String = "mixamorig1_LeftFoot"
@export var right_hip_bone: String = "mixamorig1_RightUpLeg"
@export var right_foot_bone: String = "mixamorig1_RightFoot"
@export var hips_bone: String = "mixamorig1_Hips"

@export_group("IK Settings")
@export var max_step_up: float = 0.3 # Maximum height adjustment upward
@export var max_step_down: float = 0.5 # Maximum height adjustment downward
@export var ray_length: float = 0.8 # Raycast length from foot
@export var interpolation_speed: float = 12.0 # IK smoothing speed
@export var enable_foot_rotation: bool = true # Align foot to surface normal
@export var enable_pelvis_adjustment: bool = true # Adjust hips height

@export_group("Debug")
@export var debug_draw: bool = false

# Internal references
var _skeleton: Skeleton3D
var _left_ik: Node # TwoBoneIK3D
var _right_ik: Node # TwoBoneIK3D
var _left_target: Marker3D
var _right_target: Marker3D

# Bone indices
var _left_foot_idx: int = -1
var _right_foot_idx: int = -1
var _hips_idx: int = -1

# Current IK offsets (for smoothing)
var _left_foot_offset: float = 0.0
var _right_foot_offset: float = 0.0
var _pelvis_offset: float = 0.0

# Collision layer for terrain
var _terrain_mask: int = 1 # Default to layer 1

var _initialized: bool = false


func _ready() -> void:
	if skeleton_path:
		_initialize()


func _initialize() -> void:
	# Get skeleton
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if not _skeleton:
		push_error("[FootIKSystem] Skeleton3D not found at path: " + str(skeleton_path))
		return
	
	# Find bone indices
	_left_foot_idx = _skeleton.find_bone(left_foot_bone)
	_right_foot_idx = _skeleton.find_bone(right_foot_bone)
	_hips_idx = _skeleton.find_bone(hips_bone)
	
	# Alternative bone names (try common variations)
	if _left_foot_idx == -1:
		_left_foot_idx = _skeleton.find_bone("LeftFoot")
	if _right_foot_idx == -1:
		_right_foot_idx = _skeleton.find_bone("RightFoot")
	if _hips_idx == -1:
		_hips_idx = _skeleton.find_bone("Hips")
	
	if _left_foot_idx == -1 or _right_foot_idx == -1:
		push_error("[FootIKSystem] Could not find foot bones! Left: ", left_foot_bone, " Right: ", right_foot_bone)
		return
	
	# Create IK targets (Marker3D nodes for IK goal positions)
	_left_target = Marker3D.new()
	_left_target.name = "LeftFootTarget"
	add_child(_left_target)
	
	_right_target = Marker3D.new()
	_right_target.name = "RightFootTarget"
	add_child(_right_target)
	
	# Create TwoBoneIK3D nodes (Godot 4.6+)
	_setup_two_bone_ik()
	
	_initialized = true
	print("[FootIKSystem] Initialized with bones: ", left_foot_bone, " / ", right_foot_bone)


func _setup_two_bone_ik() -> void:
	# Check if TwoBoneIK3D class exists (Godot 4.6+)
	if not ClassDB.class_exists("TwoBoneIK3D"):
		push_warning("[FootIKSystem] TwoBoneIK3D not available. Using fallback bone manipulation.")
		return
	
	# Create Left Leg IK
	_left_ik = ClassDB.instantiate("TwoBoneIK3D")
	_left_ik.name = "LeftLegIK"
	_skeleton.add_child(_left_ik)
	
	var left_hip_idx = _skeleton.find_bone(left_hip_bone)
	if left_hip_idx == -1:
		left_hip_idx = _skeleton.find_bone("LeftUpLeg")
	
	_left_ik.set("root_bone", left_hip_idx)
	_left_ik.set("tip_bone", _left_foot_idx)
	_left_ik.set("target_node", _left_target.get_path())
	
	# Create Right Leg IK
	_right_ik = ClassDB.instantiate("TwoBoneIK3D")
	_right_ik.name = "RightLegIK"
	_skeleton.add_child(_right_ik)
	
	var right_hip_idx = _skeleton.find_bone(right_hip_bone)
	if right_hip_idx == -1:
		right_hip_idx = _skeleton.find_bone("RightUpLeg")
	
	_right_ik.set("root_bone", right_hip_idx)
	_right_ik.set("tip_bone", _right_foot_idx)
	_right_ik.set("target_node", _right_target.get_path())
	
	print("[FootIKSystem] TwoBoneIK3D nodes created for both legs")


func _physics_process(delta: float) -> void:
	if not _initialized or not _skeleton:
		return
	
	# Get player's world transform
	var player_transform = get_parent().global_transform if get_parent() else global_transform
	
	# Update each foot
	var left_offset = _update_foot_ik(_left_foot_idx, _left_target, player_transform, delta)
	var right_offset = _update_foot_ik(_right_foot_idx, _right_target, player_transform, delta)
	
	# Smooth the offsets
	_left_foot_offset = lerp(_left_foot_offset, left_offset, delta * interpolation_speed)
	_right_foot_offset = lerp(_right_foot_offset, right_offset, delta * interpolation_speed)
	
	# Adjust pelvis based on foot offsets
	if enable_pelvis_adjustment:
		_update_pelvis(delta)


func _update_foot_ik(foot_idx: int, target: Marker3D, _player_transform: Transform3D, delta: float) -> float:
	if foot_idx == -1:
		return 0.0
	
	# Get foot bone global position
	var foot_global_pose = _skeleton.get_bone_global_pose(foot_idx)
	var foot_world_pos = _skeleton.global_transform * foot_global_pose.origin
	
	# Cast ray downward from foot
	var ray_origin = foot_world_pos + Vector3.UP * 0.1
	var ray_end = ray_origin + Vector3.DOWN * ray_length
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = _terrain_mask
	query.exclude = [get_parent().get_rid()] if get_parent() is CollisionObject3D else []
	
	var result = space_state.intersect_ray(query)
	var target_offset: float = 0.0
	
	if result:
		var ground_y = result.position.y
		var foot_height = foot_world_pos.y
		target_offset = clamp(ground_y - foot_height, -max_step_down, max_step_up)
		
		# Set target position
		var new_target_pos = foot_world_pos + Vector3(0, target_offset, 0)
		target.global_position = target.global_position.lerp(new_target_pos, delta * interpolation_speed)
		
		# Align foot to surface normal
		if enable_foot_rotation:
			_align_foot_to_normal(target, result.normal, delta)
		
		# Debug mode: print hit info
		if debug_draw and Engine.get_process_frames() % 60 == 0:
			print("[FootIK] Hit ground at y=", ground_y)
	else:
		# No ground detected, reset to default position
		target.global_position = target.global_position.lerp(foot_world_pos, delta * interpolation_speed)
		
		# Debug mode: print miss info
		if debug_draw and Engine.get_process_frames() % 60 == 0:
			print("[FootIK] No ground detected")
	
	return target_offset


func _align_foot_to_normal(target: Marker3D, ground_normal: Vector3, delta: float) -> void:
	if ground_normal.length_squared() < 0.01:
		return
	
	var default_up = Vector3.UP
	var rotation_axis = default_up.cross(ground_normal).normalized()
	
	if rotation_axis.length_squared() < 0.01:
		return # Normals are parallel
	
	var rotation_angle = acos(clamp(default_up.dot(ground_normal), -1.0, 1.0))
	var align_quat = Quaternion(rotation_axis, rotation_angle)
	
	# Smoothly interpolate rotation
	var current_quat = Quaternion(target.transform.basis)
	var smoothed_quat = current_quat.slerp(align_quat, delta * interpolation_speed * 0.5)
	target.transform.basis = Basis(smoothed_quat)


func _update_pelvis(delta: float) -> void:
	if _hips_idx == -1:
		return
	
	# Calculate average offset (or use minimum to prevent floating)
	var avg_offset = min(_left_foot_offset, _right_foot_offset)
	avg_offset = clamp(avg_offset, -0.15, 0.15) # Limit pelvis movement
	
	# Smooth pelvis adjustment
	_pelvis_offset = lerp(_pelvis_offset, avg_offset, delta * interpolation_speed * 0.5)
	
	# Apply to hips bone
	var hips_pose = _skeleton.get_bone_pose(_hips_idx)
	hips_pose.origin.y += _pelvis_offset
	_skeleton.set_bone_pose(_hips_idx, hips_pose)


## Set the terrain collision mask for raycasting
func set_terrain_mask(mask: int) -> void:
	_terrain_mask = mask


## Enable/disable foot IK at runtime
func set_enabled(enabled: bool) -> void:
	set_physics_process(enabled)
	
	if _left_ik:
		_left_ik.set("active", enabled)
	if _right_ik:
		_right_ik.set("active", enabled)


## Reset IK to default state
func reset() -> void:
	_left_foot_offset = 0.0
	_right_foot_offset = 0.0
	_pelvis_offset = 0.0
