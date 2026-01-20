extends Node3D

@export var splash_prefab: PackedScene
@export var detection_offset: float = 0.0
@export var splash_cooldown: float = 0.5
@export var splash_threshold: float = 0.2 # How much water must cover this point to splash
@export var trigger_ripples: bool = true # Option to disable ripples for some objects

var _timer: float = 0.0
var _was_underwater: bool = false
var water_manager = null
var ripple_manager = null

func _ready():
	if has_node("/root/WaterManager"):
		water_manager = get_node("/root/WaterManager")
		
	# Find RippleManager using a group or relative path if possible, or just search
	if get_tree().current_scene.has_node("RippleManager"):
		ripple_manager = get_tree().current_scene.get_node("RippleManager")
	
	# Load default splash if not set (convenience)
	if not splash_prefab:
		splash_prefab = load("res://Development/Scripts/Systems/WaterSystem/VFX/Particles/SplashParticles.tscn")

func _process(delta):
	if _timer > 0:
		_timer -= delta
		
	if not water_manager:
		return
		
	var water_height = water_manager.get_wave_height(global_position)
	var my_height = global_position.y + detection_offset
	
	var is_underwater = water_height > my_height + splash_threshold
	
	# Trigger splash on state change (entering water) or if deep enough and wave is rising?
	# Simple logic: On entry
	if is_underwater and not _was_underwater:
		if _timer <= 0:
			_spawn_splash()
			_timer = splash_cooldown
	
	# Also trigger if we are "just at the surface" and wave is hitting us hard?
	# For continuous waves hitting a rock:
	# Continuous splashing while underwater often looks like "pulsing" for static objects.
	# Disabled to prevent "Object didn't move, why ripple?" confusion.
	# To simulate wake for moving objects, we'd need velocity checks.
	# if is_underwater and _timer <= 0:
	# 	if randf() < 0.1: 
	# 		_spawn_splash()
	# 		_timer = splash_cooldown
			
	_was_underwater = is_underwater

func _spawn_splash():
	if splash_prefab:
		var splash = splash_prefab.instantiate()
		get_tree().current_scene.add_child(splash)
		splash.global_position = global_position
		splash.emitting = true
		
		# Cleanup
		await get_tree().create_timer(2.0).timeout
		splash.queue_free()
		
	# Trigger Dynamic Ripple
	# Trigger Dynamic Ripple
	if ripple_manager and trigger_ripples:
		ripple_manager.apply_ripple(global_position, 1.0) # Positive for test
