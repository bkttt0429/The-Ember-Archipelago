class_name FactionSubgroupController
extends Node

## 派系內部分裂 (MVP)

signal internal_conflict(faction: FactionData, tension: float)

@export var tick_interval: float = 30.0
@export var conflict_threshold: float = 0.6
@export var tension_decay: float = 0.02

var _subgroups: Dictionary = {}
var _accumulator: float = 0.0

func register_faction(faction: FactionData, groups: Array[SubgroupData]) -> void:
	if faction == null:
		return
	_subgroups[faction] = groups

func add_tension(faction: FactionData, delta: float) -> void:
	if not _subgroups.has(faction):
		return
	for group in _subgroups[faction]:
		group.tension = clamp(group.tension + delta, 0.0, 1.0)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	for faction in _subgroups.keys():
		var groups: Array = _subgroups[faction]
		var weighted_tension = 0.0
		var weight_total = 0.0
		for group in groups:
			weighted_tension += group.tension * group.influence
			weight_total += group.influence
			group.tension = clamp(group.tension - tension_decay, 0.0, 1.0)
		if weight_total > 0.0:
			weighted_tension /= weight_total
		if weighted_tension >= conflict_threshold:
			emit_signal("internal_conflict", faction, weighted_tension)
