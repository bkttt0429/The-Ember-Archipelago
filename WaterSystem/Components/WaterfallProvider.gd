extends Node3D

## WaterfallProvider - Handles waterfall logic and surface interaction.
## Must be placed at the TOP of the waterfall.

@export var water_manager: WaterSystemManager
@export var impact_strength: float = 2.0
@export var impact_radius: float = 0.1
@export var show_debug_ray: bool = false

func _ready():
	if not water_manager:
		var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
		if not managers.is_empty():
			water_manager = managers[0]

func _physics_process(_delta):
	if not water_manager: return
	
	var space_state = get_world_3d().direct_space_state
	var from = global_position
	var to = from + Vector3.DOWN * 100.0 # Max height detection
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true # Should hit the water plane if it has a collider or a specific island
	
	# Actually, the water manager has the global Y position. 
	# We can just hit that plane or a custom collision.
	var result = space_state.intersect_ray(query)
	
	var impact_pos = Vector3.ZERO
	if result:
		impact_pos = result.position
	else:
		impact_pos = Vector3(from.x, water_manager.global_position.y, from.z)
	
	# Update Shader Parameters per frame
	if has_node("MeshInstance3D"):
		var mesh_inst = get_node("MeshInstance3D")
		var mat = mesh_inst.get_surface_override_material(0)
		if mat:
			mat.set_shader_parameter("sea_level", water_manager.global_position.y)

	# Trigger Ripple
	if impact_pos.y <= water_manager.global_position.y + 0.2:
		water_manager.trigger_ripple(impact_pos, impact_strength, impact_radius)
		
		if has_node("ImpactParticles"):
			get_node("ImpactParticles").global_position = impact_pos
