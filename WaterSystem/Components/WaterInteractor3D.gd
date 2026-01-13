@tool
extends Node3D

## WaterInteractor3D - Automatic interaction with WaterSystemManager
## Add this to any moving object (Boat, Character, Rock) to create ripples/wakes.

@export var water_manager: WaterSystemManager
@export_group("Settings")
@export var impact_strength: float = 2.0
@export var impact_radius: float = 0.5
@export var min_velocity_threshold: float = 0.5
@export var foam_factor: float = 1.0

var last_pos: Vector3
var current_velocity: Vector3

func _ready():
	last_pos = global_position
	if not water_manager:
		var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
		if not managers.is_empty():
			water_manager = managers[0]

func _process(delta):
	if not water_manager: return
	if Engine.is_editor_hint() and not water_manager.rd: return # Don't run in editor if RD not init
	
	# Calculate velocity manually if not a physics body
	current_velocity = (global_position - last_pos) / delta
	last_pos = global_position
	
	var vel_len = current_velocity.length()
	if vel_len < min_velocity_threshold: return
	
	# Check if we are at water level
	var sea_level = water_manager.global_position.y
	var my_y = global_position.y
	
	# If we are near water level, trigger interaction
	if abs(my_y - sea_level) < impact_radius:
		# Dynamic strength based on velocity
		var dynamic_strength = impact_strength * (vel_len / 5.0)
		water_manager.trigger_ripple(global_position, dynamic_strength, impact_radius)
		
		# Optional: If moving fast enough, spawn vortex or more ripples
		if vel_len > 10.0:
			water_manager.trigger_vortex(global_position, dynamic_strength * 0.2, impact_radius * 2.0)
