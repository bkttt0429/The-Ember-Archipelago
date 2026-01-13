@tool
extends Node3D

## WaterTestMover - Moves an object along a fixed route to test ripples.

enum MovementMode {CIRCLE, PING_PONG}

@export var mode: MovementMode = MovementMode.CIRCLE
@export var radius: float = 10.0 # Also used as distance for PING_PONG
@export var speed: float = 2.0
@export var float_amplitude: float = 0.2
@export var float_speed: float = 1.5

var time: float = 0.0

func _process(delta):
	# If we are in editor, ensure we have a parent (spawner) to be safe
	if Engine.is_editor_hint() and not get_parent(): return
	
	time += delta
	
	# We move in local space relative to the spawner/manager
	var target_local_pos: Vector3
	
	if mode == MovementMode.CIRCLE:
		var angle = time * speed
		target_local_pos = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	else: # PING_PONG
		var offset_val = sin(time * speed) * radius
		target_local_pos = Vector3(offset_val, 0.0, 0.0)
	
	# Floating vertical movement
	target_local_pos.y = sin(time * float_speed) * float_amplitude
	
	# Calculate look direction based on local movement
	var move_dir = target_local_pos - position
	if move_dir.length() > 0.01:
		# Use global coordinates for look_at to ensure accuracy
		var global_target = to_global(target_local_pos)
		if (global_target - global_position).length() > 0.01:
			look_at(global_target, Vector3.UP)
	
	# Apply to local position
	position = target_local_pos
