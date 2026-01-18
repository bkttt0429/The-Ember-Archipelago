class_name PopulationController
extends Node

## 人口、士氣與戰爭疲勞 (MVP)

signal morale_updated(faction: FactionData, state: PopulationState)

@export var tick_interval: float = 5.0
@export var fatigue_recovery: float = 0.02
@export var morale_recovery: float = 0.01

var _states: Dictionary = {}
var _accumulator: float = 0.0

func register_faction(faction: FactionData, state: PopulationState) -> void:
	_states[faction] = state

func apply_war_event(faction: FactionData, intensity: float) -> void:
	if not _states.has(faction):
		return
	var state = _states[faction]
	state.war_fatigue = clamp(state.war_fatigue + intensity, 0.0, 1.0)
	state.morale = clamp(state.morale - intensity * 0.2, 0.0, 1.0)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	for faction in _states.keys():
		var state: PopulationState = _states[faction]
		state.war_fatigue = clamp(state.war_fatigue - fatigue_recovery, 0.0, 1.0)
		state.morale = clamp(state.morale + morale_recovery, 0.0, 1.0)
		emit_signal("morale_updated", faction, state)
