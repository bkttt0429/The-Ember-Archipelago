@tool
class_name WeatherManager
extends Node

## WeatherManager - High-level weather system controller
## Manages weather profiles, global state, and coordinates with WaterManager.

@export var water_manager: OceanWaterManager

@export_group("Global Conditions")
@export var global_wind_strength: float = 1.0:
	set(v):
		global_wind_strength = v
		if water_manager: water_manager.wind_strength = v

@export var global_wind_direction: Vector2 = Vector2(1, 0):
	set(v):
		global_wind_direction = v
		if water_manager: water_manager.wind_direction = v

func _ready():
	if not water_manager:
		# Try to find it in parents or siblings
		water_manager = get_parent().find_child("OceanWaterManager", true, false)
	
	print("[WeatherManager] Initialized.")

func spawn_vortex(world_pos: Vector3, radius: float = 10.0):
	if water_manager:
		water_manager.trigger_vortex(world_pos, radius)

func spawn_waterspout(world_pos: Vector3, radius: float = 8.0):
	if water_manager:
		water_manager.trigger_waterspout(world_pos, radius)

func clear_all_weather():
	if water_manager:
		water_manager.clear_skills()
