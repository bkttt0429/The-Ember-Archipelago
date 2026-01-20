extends Area3D

@export var max_radius: float = 25.0
@export var radial_strength: float = 50.0
@export var tangential_strength: float = 100.0
@export var vertical_strength: float = -80.0
@export var falloff_power: float = 1.0
@export var radius_multiplier: float = 1.0
@export var strength_multiplier: float = 1.0
@export var active: bool = true

func _physics_process(_delta: float) -> void:
	if not active:
		return
	
	var effective_radius = max_radius * radius_multiplier
	if effective_radius <= 0.0:
		return
	
	for body in get_overlapping_bodies():
		if body is RigidBody3D:
			_apply_vortex_forces(body, effective_radius)

func _apply_vortex_forces(body: RigidBody3D, effective_radius: float) -> void:
	var to_center = global_position - body.global_position
	to_center.y = 0.0
	var dist = to_center.length()
	if dist < 0.001 or dist > effective_radius:
		return
	
	var dir_to_center = to_center.normalized()
	if not dir_to_center.is_finite():
		return
	
	var falloff = 1.0 / pow(max(dist, 1.0), falloff_power)
	var strength = strength_multiplier * falloff
	
	var tangential_dir = Vector3(-dir_to_center.z, 0.0, dir_to_center.x)
	var radial_force = dir_to_center * radial_strength * strength
	var tangential_force = tangential_dir * tangential_strength * strength
	
	var vertical_mult = 1.0 - clamp(dist / effective_radius, 0.0, 1.0)
	var vertical_force = Vector3.UP * vertical_strength * strength_multiplier * vertical_mult
	
	body.apply_central_force(radial_force + tangential_force + vertical_force)
