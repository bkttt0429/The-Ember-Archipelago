@tool
class_name RainController
extends Node3D

@export var rain_particles: GPUParticles3D
@export var max_emission_rate: float = 5000.0

func _ready():
	if not rain_particles:
		rain_particles = find_child("GPUParticles3D")

func set_intensity(val: float):
	if not rain_particles: return
	
	val = clamp(val, 0.0, 1.0)
	
	if val <= 0.001:
		if rain_particles.emitting:
			rain_particles.emitting = false
	else:
		if not rain_particles.emitting:
			rain_particles.emitting = true
		
		# amount_ratio is a Godot 4.x feature to scale particle count without restarting
		rain_particles.amount_ratio = val
		
		# If the particle material is a ShaderMaterial, we could pass intensity there too
		if rain_particles.process_material is ShaderMaterial:
			rain_particles.process_material.set_shader_parameter("rain_intensity", val)
