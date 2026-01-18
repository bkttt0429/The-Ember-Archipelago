extends Node
class_name PlayerSignals

signal stamina_changed(value: float)
signal weapon_swapped(weapon_id: String)
signal survival_changed(hunger: float, fatigue: float, temperature: float)
