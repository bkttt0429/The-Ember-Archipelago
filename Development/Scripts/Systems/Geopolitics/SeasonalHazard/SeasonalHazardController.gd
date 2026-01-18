class_name SeasonalHazardController
extends Node

## 災害與季節 (MVP)

signal hazard_updated(region_id: String, storm_level: float)

@export var tick_interval: float = 10.0
@export var seasonal_speed: float = 0.02

var _profiles: Dictionary = {}
var _accumulator: float = 0.0

func register_region(profile: HazardProfile) -> void:
	if profile == null:
		return
	_profiles[profile.region_id] = profile

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	for region_id in _profiles.keys():
		var profile: HazardProfile = _profiles[region_id]
		profile.season_phase = wrapf(profile.season_phase + seasonal_speed, 0.0, 1.0)
		var target = abs(sin(profile.season_phase * PI * 2.0))
		profile.storm_level = clamp(lerp(profile.storm_level, target, 0.25), 0.0, 1.0)
		emit_signal("hazard_updated", region_id, profile.storm_level)
