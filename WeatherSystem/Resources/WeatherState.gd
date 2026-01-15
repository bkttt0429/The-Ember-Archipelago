@tool
class_name WeatherState
extends Resource

@export var name: String = "Clear"

@export_group("Water Impact")
@export var wind_strength: float = 1.0
@export var wind_direction: Vector2 = Vector2(1, 0)
@export var wave_steepness: float = 0.25

@export_group("Atmosphere")
@export var sky_color: Color = Color(0.3, 0.5, 0.8)
@export var fog_density: float = 0.001

@export_group("VFX")
@export var rain_intensity: float = 0.0
@export var storm_mode: bool = false
