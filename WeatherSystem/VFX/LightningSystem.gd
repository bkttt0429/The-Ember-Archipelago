@tool
class_name LightningSystem
extends Node3D

@export var light_source: OmniLight3D
@export var sound_player: AudioStreamPlayer
@export var thunder_sounds: Array[AudioStream]
@export var flash_intensity: float = 5.0
@export var flash_duration: float = 0.5

func trigger_flash():
	if not light_source: return
	
	# Random position offset if desired, or just global flash
	# For a "Sky Flash", we usually place it high up relative to the camera or player
	
	# 1. Immediate Flash
	var tween = create_tween()
	light_source.light_energy = flash_intensity
	
	# 2. Flicker down
	tween.tween_property(light_source, "light_energy", flash_intensity * 0.5, 0.05)
	tween.tween_property(light_source, "light_energy", flash_intensity, 0.05)
	tween.tween_property(light_source, "light_energy", 0.0, flash_duration).set_ease(Tween.EASE_OUT)
	
	# 3. Sound
	if sound_player and not thunder_sounds.is_empty():
		# Delay sound based on "distance" (simulated)
		var delay = randf_range(0.0, 1.5)
		await get_tree().create_timer(delay).timeout
		sound_player.stream = thunder_sounds.pick_random()
		sound_player.play()
