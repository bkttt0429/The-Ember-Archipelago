class_name BuoyancyComponent
extends Node3D

## Buoyancy Component
## Attaches to a RigidBody3D and applies buoyancy forces based on water height.
## Requires a WaterManager in the "WaterSystem_Managers" group.

@export_group("Buoyancy")
@export var buoyancy_force: float = 10.0
@export var drag: float = 2.0
@export var angular_drag: float = 1.0
@export var submerged_height: float = 1.0 ## Approximate height of the object that provides buoyancy

@export_group("Probes")
@export var use_multiple_probes: bool = false
@export var box_size: Vector3 = Vector3(1, 1, 1) ## For auto-generating probes

var _rigid_body: RigidBody3D
var _water_manager: OceanWaterManager
var _probes: Array[Vector3] = []

func _ready():
	_rigid_body = get_parent() as RigidBody3D
	if not _rigid_body:
		push_error("[BuoyancyComponent] Parent must be a RigidBody3D!")
		set_physics_process(false)
		return
		
	# Find Water Manager
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if managers.size() > 0:
		_water_manager = managers[0]
	else:
		push_warning("[BuoyancyComponent] No WaterManager found in 'WaterSystem_Managers' group.")
		set_physics_process(false)
		
	_setup_probes()

func _setup_probes():
	_probes.clear()
	if use_multiple_probes:
		# Create 4 corner probes at the bottom
		var half = box_size * 0.5
		_probes.append(Vector3(-half.x, -half.y, -half.z))
		_probes.append(Vector3(half.x, -half.y, -half.z))
		_probes.append(Vector3(half.x, -half.y, half.z))
		_probes.append(Vector3(-half.x, -half.y, half.z))
	else:
		# Single center probe
		_probes.append(Vector3.ZERO)

func _physics_process(delta):
	if not _water_manager or not _rigid_body: return
	
	var body_gt = _rigid_body.global_transform
	var total_submerged_ratio = 0.0
	
	for local_pos in _probes:
		var global_probe_pos = body_gt * local_pos
		var water_height = _water_manager.get_wave_height_at(global_probe_pos)
		
		# Calculate depth
		var depth = water_height - global_probe_pos.y
		
		if depth > 0:
			# Apply Force at this probe position
			# Force proportional to depth (simplified Archimedes)
			# Normalize by number of probes
			var force_mag = (depth / submerged_height) * buoyancy_force * (1.0 / _probes.size())
			# Clamp max force
			force_mag = min(force_mag, buoyancy_force * 2.0 / _probes.size())
			
			var force_vec = Vector3.UP * force_mag
			_rigid_body.apply_force(force_vec, global_probe_pos - _rigid_body.global_position)
			
			total_submerged_ratio += 1.0 / _probes.size()
			
			# Add Water Drag (Linear and Angular)
			var velocity = _rigid_body.linear_velocity
			var drag_force = - velocity * drag * (depth / submerged_height) * delta
			_rigid_body.apply_force(drag_force, global_probe_pos - _rigid_body.global_position)
	
	# Apply Angular Drag if submerged
	if total_submerged_ratio > 0.0:
		var ang_drag = - _rigid_body.angular_velocity * angular_drag * total_submerged_ratio * delta
		_rigid_body.apply_torque(ang_drag)
