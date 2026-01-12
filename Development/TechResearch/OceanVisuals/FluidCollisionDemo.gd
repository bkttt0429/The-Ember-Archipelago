extends Node3D

@export var gpu_sim: Node3D
@export var emitter_radius: float = 5.0
@export var emitter_strength: float = 50.0

@export var emitter_a_pos: Vector2 = Vector2(-8, 0)
@export var emitter_b_pos: Vector2 = Vector2(8, 0)

func _process(_delta):
	if not gpu_sim: return
	
	# Emit Red Fluid from Left
	gpu_sim.add_collision_emitter(emitter_a_pos, emitter_radius, emitter_strength, true)
	
	# Emit Blue Fluid from Right
	gpu_sim.add_collision_emitter(emitter_b_pos, emitter_radius, emitter_strength, false)
