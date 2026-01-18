class_name CultureController
extends Node

## 文化偏好 (MVP)

signal culture_shifted(faction: FactionData, profile: CultureProfile)

func register_faction(faction: FactionData, profile: CultureProfile) -> void:
	if faction == null or profile == null:
		return
	faction.set_meta("culture_profile", profile)

func get_profile(faction: FactionData) -> CultureProfile:
	if faction == null:
		return null
	return faction.get_meta("culture_profile", null)

func get_culture_distance(faction_a: FactionData, faction_b: FactionData) -> float:
	var profile_a = get_profile(faction_a)
	var profile_b = get_profile(faction_b)
	if profile_a == null or profile_b == null:
		return 0.0
	return profile_a.distance_to(profile_b)
