@tool
extends Node3D

# Simple Buoyancy Script to demonstrate sea interaction
@export var sea_controller_path: NodePath
@export var buoyancy_force: float = 15.0
@export var linear_damping: float = 0.5
@export var angular_damping: float = 0.5

@onready var rb: RigidBody3D = get_parent() as RigidBody3D
@onready var sea: Node3D = get_node_or_null(sea_controller_path)

@export var probe_points: Array[Vector3] = [Vector3.ZERO] # Local offsets for sampling
@export var water_density: float = 1.0 # Multiplier for buoyancy
@export var buoyancy_damping: float = 0.95 # Slow down when in water

func _physics_process(delta):
	if not rb or not sea: return
	
	var total_force = Vector3.ZERO
	var in_water = false
	
	for offset in probe_points:
		var global_probe_pos = rb.global_transform * offset
		var h = sea.get_water_height_at(global_probe_pos)
		var depth = h - global_probe_pos.y
		
		if depth > 0:
			# Buoyancy Force = Density * Volume-equivalent * gravity
			var f = Vector3.UP * depth * buoyancy_force * water_density / probe_points.size()
			rb.apply_force(f, global_probe_pos - rb.global_position)
			in_water = true
	
	if in_water:
		# Apply damping to simulate water resistance
		rb.linear_velocity *= (1.0 - linear_damping * delta)
		rb.angular_velocity *= (1.0 - angular_damping * delta)
