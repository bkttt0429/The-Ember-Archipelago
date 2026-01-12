extends Node

@export var water_manager: WaterManager
@export var ripple_count: int = 5
@export var spawn_radius: float = 10.0

func _process(delta):
	# Press Space to spawn multiple ripples
	if Input.is_action_just_pressed("ui_accept"):
		for i in range(ripple_count):
			var random_pos = Vector3(
				randf_range(-spawn_radius, spawn_radius),
				0.0,
				randf_range(-spawn_radius, spawn_radius)
			)
			# Assuming global_position of this node is near water center
			water_manager.trigger_ripple(water_manager.to_global(random_pos), 2.0, 0.2)
			print("Spawned ripple at: ", random_pos)
