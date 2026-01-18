class_name GovernanceController
extends Node

## 內政與治理成本 (MVP)

signal governance_pressure(faction: FactionData, pressure: float)

@export var tick_interval: float = 30.0
@export var pressure_threshold: float = 1.2

var _states: Dictionary = {}
var _accumulator: float = 0.0

func register_faction(faction: FactionData, state: GovernanceState) -> void:
	_states[faction] = state

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	for faction in _states.keys():
		var state: GovernanceState = _states[faction]
		var pressure = state.territory * (1.0 - state.stability) * state.distance_factor
		if pressure > pressure_threshold:
			emit_signal("governance_pressure", faction, pressure)
