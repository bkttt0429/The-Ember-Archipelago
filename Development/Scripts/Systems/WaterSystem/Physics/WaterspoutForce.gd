extends Area3D

## Prompt B: Waterspout Force Logic
## This script applies tangential and lift forces to objects entering the area.

@export var tangential_strength: float = 60.0
@export var lift_strength: float = 30.0
@export var attraction_strength: float = 30.0
@export var attract_radius: float = 10.0
@export var spout_strength: float = 12.0
@export var spiral_strength: float = 15.0
@export var spiral_arms: int = 4
@export var foam_ring_inner: float = 3.0
@export var foam_ring_outer: float = 8.0
@export var darkness_factor: float = 0.9
@export var radius_multiplier: float = 1.0
@export var strength_multiplier: float = 1.0
@export var active: bool = true
@export var shader_update_node: NodePath
@export var vfx_scene: PackedScene = preload("res://Development/Scripts/Systems/WaterSystem/VFX/Particles/WaterspoutVFX.tscn")

var water_mesh: MeshInstance3D
var vfx_instance: Node3D
var water_manager: WaterSystemManager

func _ready():
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if managers.size() > 0:
		water_manager = managers[0]

	if vfx_scene:
		vfx_instance = vfx_scene.instantiate()
		add_child(vfx_instance)
		vfx_instance.position = Vector3.ZERO
		vfx_instance.scale = Vector3.ONE * (attract_radius / 5.0)
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta):
	if not active:
		return
		
	var effective_radius = attract_radius * radius_multiplier
	var effective_spout_strength = spout_strength * strength_multiplier
	
	# Push configuration to WaterManager (The Authority)
	# This allows the visual system (Shader) and Buoyancy System to be in sync with this physical object
	if water_manager:
		water_manager.waterspout_pos = global_position
		water_manager.waterspout_radius = effective_radius
		water_manager.waterspout_strength = effective_spout_strength # Controls depth
		water_manager.waterspout_spiral_strength = spiral_strength * strength_multiplier
		water_manager.waterspout_darkness_factor = darkness_factor
	
	if vfx_instance:
		vfx_instance.scale = Vector3.ONE * (effective_radius / 5.0)
		
	# Update VFX Funnel Time
	if vfx_instance:
		var funnel = vfx_instance.get_node_or_null("Funnel")
		if funnel and funnel is MeshInstance3D:
			var mat = funnel.mesh.surface_get_material(0)
			if mat is ShaderMaterial:
				# Use WaterManager time if available
				var t = water_manager._time if water_manager else Time.get_ticks_msec() / 1000.0
				mat.set_shader_parameter("sync_time", t)

func _physics_process(delta):
	if not active:
		return
		
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body is RigidBody3D:
			_apply_waterspout_forces(body, delta)

func _apply_waterspout_forces(body: RigidBody3D, _delta: float):
	var to_center = global_position - body.global_position
	to_center.y = 0 # Horizontal only for direction
	
	var dist = to_center.length()
	var effective_radius = attract_radius * radius_multiplier
	var strength = strength_multiplier
	
	# Safety check: avoid division by zero or normalizing zero vector
	if dist < 0.001:
		return
		
	var dir_to_center = to_center.normalized()
	
	if not dir_to_center.is_finite():
		return
	
	# 1. Attraction Force (Pull towards center)
	body.apply_central_force(dir_to_center * attraction_strength * strength)
	
	# 2. Tangential Force (Rotation)
	# Perpendicular to dir_to_center: (x, z) -> (-z, x)
	var tangential_dir = Vector3(-dir_to_center.z, 0, dir_to_center.x)
	body.apply_central_force(tangential_dir * tangential_strength * strength)
	
	# 3. Lift Force (Upwards)
	# Stronger at center
	var lift_mult = clamp(1.0 - (dist / max(effective_radius, 0.001)), 0.0, 1.0)
	body.apply_central_force(Vector3.UP * lift_strength * strength * lift_mult)
	
	# Reduce gravity effect manually if needed, or just let lift force handle it
	# body.gravity_scale = 0.5 * (1.0 - lift_mult)

func _on_body_entered(body):
	print("Object entered waterspout: ", body.name)

func _on_body_exited(body):
	print("Object exited waterspout: ", body.name)
	if body is RigidBody3D:
		body.gravity_scale = 1.0
