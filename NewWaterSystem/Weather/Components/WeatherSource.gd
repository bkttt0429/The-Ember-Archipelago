@tool
class_name WeatherSource
extends Node3D

## WeatherSource - A spatial source for weather events (e.g., a tornado point)

enum WeatherType {VORTEX, WATERSPOUT}

@export var type: WeatherType = WeatherType.WATERSPOUT
@export var radius: float = 10.0
@export var intensity: float = 1.0
@export var auto_spawn: bool = true

func _ready():
	if auto_spawn and not Engine.is_editor_hint():
		activate()

func activate():
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if managers.is_empty() and water_manager:
		managers = [water_manager]
		
	for m in managers:
		if m.has_method("trigger_vortex") or m is OceanWaterManager:
			match type:
				WeatherType.VORTEX:
					m.trigger_vortex(global_position, radius, intensity)
				WeatherType.WATERSPOUT:
					m.trigger_waterspout(global_position, radius, intensity)

@export var water_manager: Node # Fallback optional direct reference

func _process(_delta):
	if Engine.is_editor_hint(): return
	# Simple proximity or continuous update logic could go here
	# For now, just ensure it's registered
