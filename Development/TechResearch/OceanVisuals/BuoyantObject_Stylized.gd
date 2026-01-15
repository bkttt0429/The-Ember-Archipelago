extends Node3D

## BuoyantObject_Stylized.gd
## Adds stable buoyancy, orientation (tilt), and water interaction ripples to an object.
## Optimized for large scale objects and stable wave alignment.

@export var float_force: float = 30.0
@export var water_drag: float = 0.85
@export var ripple_strength: float = 8.0
@export var ripple_radius: float = 1.5
@export var rotation_speed: float = 2.0
@export var probe_distance: float = 5.0 # Adjusted for large scale (10x)

var velocity: Vector3 = Vector3.ZERO
var gpu_local_ocean: GpuLocalOcean
var water_manager: WaterSystemManager

func _ready():
	gpu_local_ocean = get_tree().root.find_child("GpuLocalOcean_SWE", true, false)
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if managers.size() > 0:
		water_manager = managers[0]

func _physics_process(delta):
	if not water_manager: return

	# 1. SAMPLE HEIGHTS (Stable Yaw-Aligned)
	var current_pos = global_position
	var center_h = water_manager.get_water_height_at(current_pos)
	
	# Use Yaw-only rotation for probes to prevent "sampling loop" where tilting boat reads wrong slope
	var yaw_basis = Basis(Vector3.UP, transform.basis.get_euler().y)
	var forward_dir = yaw_basis.z.normalized() # Backwards in Godot (+Z)
	var right_dir = yaw_basis.x.normalized() # Right (+X)
	
	var p_f_world = current_pos + forward_dir * probe_distance
	var p_r_world = current_pos + right_dir * probe_distance
	
	var h_f = water_manager.get_water_height_at(p_f_world)
	var h_r = water_manager.get_water_height_at(p_r_world)
	
	# 2. CALC WAVE SLOPE NORMAL
	# Construct relative vectors based on ACTUAL sampled positions
	var v_f = (p_f_world - current_pos)
	v_f.y = h_f - center_h
	
	var v_r = (p_r_world - current_pos)
	v_r.y = h_r - center_h
	
	# Cross Product for Normal
	# We want UP vector.
	# Godot: Right (+X), Up (+Y), Back (+Z)
	# v_f is Back (+Z). v_r is Right (+X).
	# v_f (Z) cross v_r (X) = Y (Up)
	var wave_normal = v_f.cross(v_r).normalized()
	
	# 3. STABLE ROTATION (Slerp with Up-Vector Constraint)
	var current_quat = transform.basis.get_rotation_quaternion()
	var current_scale = transform.basis.get_scale()
	
	# Clamp the wave normal to prevent extreme tilting
	var up_dot = wave_normal.dot(Vector3.UP)
	if up_dot < 0.7: # Approx 45 degrees
		var axis = wave_normal.cross(Vector3.UP).normalized()
		# check for zero length axis (if normal is exactly down/up)
		if axis.length_squared() > 0.001:
			wave_normal = Vector3.UP.rotated(axis, -0.78)
		else:
			wave_normal = Vector3.UP # Fallback
	
	# Construct target basis
	var target_y = wave_normal
	# Keep the original forward pointing direction (Yaw preservation)
	# We use the flat forward_dir we calculated earlier to avoid roll influence
	var desired_forward = forward_dir
	
	var target_x = target_y.cross(desired_forward).normalized()
	var target_z = target_x.cross(target_y).normalized()
	
	if target_x.length() > 0.001:
		var target_basis = Basis(target_x, target_y, target_z)
		var target_quat = target_basis.get_rotation_quaternion()
		
		# Smoothly interpolate rotation
		var new_quat = current_quat.slerp(target_quat, rotation_speed * delta)
		transform.basis = Basis(new_quat).scaled(current_scale)

	# 4. BUOYANCY LOGIC (Vertical)
	var depth = center_h - global_position.y
	
	if depth > 0:
		# Correct Physical Damping (Exponential Decay or Time-Step Integration)
		# Previous: velocity *= water_drag (Dependent on framerate!)
		# New: velocity *= (1.0 - drag * delta) approx for small delta
		# More stable damping:
		var damping_factor = clamp(1.0 - (water_drag * delta), 0.0, 1.0)
		velocity.y += float_force * depth * delta
		velocity.x *= damping_factor # Damping horizontal motion
		velocity.z *= damping_factor # Damping horizontal motion
		velocity.y *= damping_factor # Damping vertical motion
		
		if gpu_local_ocean and velocity.length() > 0.1:
			gpu_local_ocean.add_interaction_world(global_position, ripple_radius, velocity.length() * ripple_strength * delta)
	else:
		velocity.y -= 9.8 * delta
		
	global_position += velocity * delta
	
	if global_position.y < -50.0:
		global_position.y = -50.0
		velocity.y = 0
