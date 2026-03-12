extends Node3D
class_name ShipBuoyancyDriver

@export var rigid_body: RigidBody3D
@export var floaters: Array[Node3D] = [] ## Assign Marker3D nodes representing the 4 corners of the ship
@export var buoyancy_force: float = 100.0 ## Force multiplier
@export var water_drag: float = 1.0 ## Water resistance

var ocean_sampler: OceanBuoyancySampler3D

func _ready():
	if not rigid_body:
		rigid_body = get_parent() as RigidBody3D
	
	if floaters.is_empty():
		for child in get_children():
			if child is Marker3D or child is Node3D:
				floaters.append(child)
	
	# Look for an existing Sampler or create one
	ocean_sampler = get_node_or_null("OceanBuoyancySampler3D")
	if not ocean_sampler:
		if ClassDB.class_exists("OceanBuoyancySampler3D"):
			ocean_sampler = ClassDB.instantiate("OceanBuoyancySampler3D")
			add_child(ocean_sampler)
			ocean_sampler.add_to_group("ocean_samplers")
			print("[ShipBuoyancyDriver] Created internal OceanBuoyancySampler3D for ", name)
		else:
			push_error("[ShipBuoyancyDriver] C++ module OceanBuoyancySampler3D not found! Did you compile it?")


func _physics_process(_delta):
	if not ocean_sampler or not rigid_body:
		return
	
	for floater in floaters:
		# Ask the C++ Extension for the EXACT height of the Gerstner Wave at this global position
		var wave_y = ocean_sampler.get_wave_height(floater.global_position)
		
		# (Optional) we could read SWE texture too for interaction ripples 
		# But this C++ Sampler focuses purely on base Ocean Waves
		
		var depth = wave_y - floater.global_position.y
		
		if depth > 0.0:
			# Submerged
			var force = Vector3.UP * depth * buoyancy_force
			
			# Apply individual drag per point to simulate rotational drag
			var local_pos = floater.global_position - rigid_body.global_position
			var point_vel = rigid_body.linear_velocity + rigid_body.angular_velocity.cross(local_pos)
			var drag_force = - point_vel * water_drag * depth
			
			var total_local_force = force + drag_force
			rigid_body.apply_force(total_local_force, floater.global_position - rigid_body.global_position)
