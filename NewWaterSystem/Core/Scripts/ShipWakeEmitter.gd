@tool
class_name ShipWakeEmitter
extends Node3D

## ShipWakeEmitter - Generates V-shaped Kelvin Wakes using SWE Compute Shader
## Connects to OceanWaterManager to inject negative pressure impulses over time.

@export var water_manager: OceanWaterManager
@export var is_active: bool = true

@export_group("Wake Settings")
## Multiplier for the downward force based on speed.
@export var wake_strength_multiplier: float = -1.0
## Radius of the wake impulse at this emitter's point.
@export var wake_radius: float = 0.5
## The minimum movement distance required before dropping another wake impulse.
@export var drop_interval_meters: float = 0.25
## Minimum speed to start generating a wake.
@export var min_speed: float = 0.1

var _last_pos: Vector3 = Vector3.ZERO
var _last_drop_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_last_pos = global_position
	_last_drop_pos = global_position

func _physics_process(delta: float) -> void:
	if not is_active or not is_instance_valid(water_manager):
		return
		
	var current_pos = global_position
	var velocity = (current_pos - _last_pos) / max(delta, 0.001)
	var speed = velocity.length()
	
	_last_pos = current_pos
	
	if speed < min_speed:
		return
		
	var dist_since_last_drop = current_pos.distance_to(_last_drop_pos)
	
	if dist_since_last_drop >= drop_interval_meters:
		# Provide a gentle strength based on speed, clamped to avoid SWE instability
		var strength = wake_strength_multiplier * speed
		# SWE breaks (CFL condition) if the displacement gradient is too steep.
		# A limit of -15.0 creates huge waves. -2.0 to -5.0 is appropriate.
		strength = clamp(strength, -15.0, 15.0)
		
		# Trigger the downward displacement depression
		water_manager.trigger_ripple(current_pos, strength, wake_radius)
		_last_drop_pos = current_pos
