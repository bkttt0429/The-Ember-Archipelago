extends Area3D

## Prompt B: Waterspout Force Logic
## This script applies tangential and lift forces to objects entering the area.

@export var tangential_strength: float = 20.0
@export var lift_strength: float = 15.0
@export var attraction_strength: float = 10.0
@export var shader_update_node: NodePath

var water_mesh: MeshInstance3D

func _ready():
	if shader_update_node:
		water_mesh = get_node(shader_update_node) as MeshInstance3D
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta):
	# Update Shader with current position
	if water_mesh:
		var mat = water_mesh.get_surface_override_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("waterspout_pos", global_position)
			mat.set_shader_parameter("waterspout_strength", waterspout_strength)
			mat.set_shader_parameter("waterspout_radius", attract_radius)

func _physics_process(delta):
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D:
			_apply_waterspout_forces(body, delta)

func _apply_waterspout_forces(body: RigidBody3D, _delta: float):
	var to_center = global_position - body.global_position
	to_center.y = 0 # Horizontal only for direction
	
	var dist = to_center.length()
	var dir_to_center = to_center.normalized()
	
	# 1. Attraction Force (Pull towards center)
	body.apply_central_force(dir_to_center * attraction_strength)
	
	# 2. Tangential Force (Rotation)
	# Perpendicular to dir_to_center: (x, z) -> (-z, x)
	var tangential_dir = Vector3(-dir_to_center.z, 0, dir_to_center.x)
	body.apply_central_force(tangential_dir * tangential_strength)
	
	# 3. Lift Force (Upwards)
	# Stronger at center
	var lift_mult = clamp(1.0 - (dist / 10.0), 0.0, 1.0)
	body.apply_central_force(Vector3.UP * lift_strength * lift_mult)
	
	# Reduce gravity effect manually if needed, or just let lift force handle it
	# body.gravity_scale = 0.5 * (1.0 - lift_mult)

func _on_body_entered(body):
	print("Object entered waterspout: ", body.name)

func _on_body_exited(body):
	print("Object exited waterspout: ", body.name)
	if body is RigidBody3D:
		body.gravity_scale = 1.0
