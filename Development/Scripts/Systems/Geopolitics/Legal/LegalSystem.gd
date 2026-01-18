class_name LegalSystem
extends Node

## 法律/禁令 (MVP)

signal legal_status_changed(faction_a: FactionData, faction_b: FactionData, status: LegalStatus)

var _relations: Dictionary = {}

func set_status(faction_a: FactionData, faction_b: FactionData, status: LegalStatus) -> void:
	if faction_a == null or faction_b == null or status == null:
		return
	if not _relations.has(faction_a):
		_relations[faction_a] = {}
	_relations[faction_a][faction_b] = status
	emit_signal("legal_status_changed", faction_a, faction_b, status)

func get_status(faction_a: FactionData, faction_b: FactionData) -> LegalStatus:
	if faction_a == null or faction_b == null:
		return null
	if not _relations.has(faction_a):
		return null
	return _relations[faction_a].get(faction_b, null)
