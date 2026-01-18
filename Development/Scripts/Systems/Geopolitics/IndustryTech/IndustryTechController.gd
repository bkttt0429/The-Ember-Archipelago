class_name IndustryTechController
extends Node

## 工業/科技等級 (MVP)

signal tech_level_changed(faction: FactionData, state: IndustryTechState)

@export var tick_interval: float = 30.0

var _states: Dictionary = {}
var _accumulator: float = 0.0

func register_faction(faction: FactionData, state: IndustryTechState) -> void:
	_states[faction] = state

func apply_progress(faction: FactionData, delta: float) -> void:
	if not _states.has(faction):
		return
	var state = _states[faction]
	state.tech_level = max(0.0, state.tech_level + delta)
	state.industry_capacity = max(0.0, state.industry_capacity + delta * 0.5)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	for faction in _states.keys():
		emit_signal("tech_level_changed", faction, _states[faction])
