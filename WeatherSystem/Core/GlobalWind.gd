extends Node

## GlobalWind - Autoloaded singleton for managing wind across systems
## Provides a central source of truth for wind strength and direction.

signal wind_changed(new_direction: Vector2, new_strength: float)

var current_wind_direction: Vector2 = Vector2(1.0, 0.0):
	set(v):
		current_wind_direction = v
		wind_changed.emit(current_wind_direction, current_wind_strength)

var current_wind_strength: float = 1.0:
	set(v):
		current_wind_strength = v
		wind_changed.emit(current_wind_direction, current_wind_strength)

func _ready():
	print("[GlobalWind] Singleton initialized.")

func get_wind_vector() -> Vector2:
	return current_wind_direction * current_wind_strength
