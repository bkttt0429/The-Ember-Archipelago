class_name BuoyancyProvider
extends Node3D

## BuoyancyProvider - Modular component for physical water interaction.
## Attach this as a child of a RigidBody3D.

@export var water_manager_path: NodePath
@export var buoyancy_force: float = 200.0
@export var linear_damping: float = 1.0
@export var angular_damping: float = 1.0

## Probe points for sampling water height. Local offsets from the RigidBody.
@export var probe_points: Array[Vector3] = [Vector3.ZERO]

var target_body: RigidBody3D
var water_manager: WaterSystemManager

func _ready():
	target_body = get_parent() as RigidBody3D
	if not target_body:
		push_warning("[BuoyancyProvider] Parent must be a RigidBody3D")
		set_physics_process(false)
		return
		
	if water_manager_path:
		water_manager = get_node(water_manager_path)
	else:
		# Auto-find if not set
		var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
		if managers.size() > 0:
			water_manager = managers[0]
		else:
			# Fallback search
			water_manager = get_tree().root.find_child("WaterManager", true, false)

func _physics_process(delta):
	if not target_body or not water_manager:
		# Dynamic retry to find manager if it was spawned late
		var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
		if managers.size() > 0: water_manager = managers[0]
		return
		
	var force_per_probe = buoyancy_force / float(probe_points.size())
	
	for probe in probe_points:
		var global_probe_pos = target_body.to_global(probe)
		var water_h = water_manager.get_water_height_at(global_probe_pos)
		
		if global_probe_pos.y < water_h:
			var depth = water_h - global_probe_pos.y
			var f = Vector3.UP * force_per_probe * depth
			
			# Apply individual probe force at world position
			target_body.apply_force(f, global_probe_pos - target_body.global_position)
			
			# Damping
			target_body.linear_velocity *= (1.0 - linear_damping * delta)
			target_body.angular_velocity *= (1.0 - angular_damping * delta)
