@tool
class_name WeatherConfig
extends Resource

@export_group("VFX Timing")
@export var lightning_min_interval: float = 3.0
@export var lightning_max_interval: float = 12.0
@export var tornado_min_interval: float = 20.0
@export var tornado_max_interval: float = 60.0

@export_group("Tornado Settings")
@export var tornado_min_duration: float = 15.0
@export var tornado_max_duration: float = 40.0
@export var tornado_spawn_radius_x: float = -10.0
@export var tornado_spawn_radius_z: float = 10.0
@export var tornado_manual_spawn_radius: float = 15.0

@export_group("Weather Transition")
@export var default_transition_duration: float = 5.0
