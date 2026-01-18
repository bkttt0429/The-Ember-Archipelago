class_name IdeologyController
extends Node

## 信仰/意識形態 (MVP)

signal ideology_shifted(faction: FactionData, profile: IdeologyProfile)

func register_faction(faction: FactionData, profile: IdeologyProfile) -> void:
	if faction == null or profile == null:
		return
	faction.set_meta("ideology_profile", profile)

func get_profile(faction: FactionData) -> IdeologyProfile:
	if faction == null:
		return null
	return faction.get_meta("ideology_profile", null)

func get_modifier(faction: FactionData) -> Dictionary:
	var profile = get_profile(faction)
	if profile == null:
		return {"aggression": 0.0, "trade": 0.0}
	var aggression = profile.fanaticism * profile.dogma_weight
	var trade = -profile.fanaticism * (1.0 - profile.dogma_weight)
	return {"aggression": aggression, "trade": trade}
