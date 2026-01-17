@tool
class_name TornadoController
extends Node3D

## TornadoController - Manages visual tornado VFX and links to WaterManager vortex simulation.

@export var water_manager: OceanWaterManager
@export var cloud_particles: GPUParticles3D
@export var radius: float = 15.0
@export var intensity: float = 1.5
@export var rotation_speed: float = 3.0

var _is_active: bool = false
var _duration_timer: float = 0.0

func _ready():
	if not water_manager:
		water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers")
	
	if not cloud_particles:
		cloud_particles = find_child("GPUParticles3D")
	
	# Start inactive
	if cloud_particles:
		cloud_particles.emitting = false

func _process(delta):
	if not _is_active: return
	
	_duration_timer -= delta
	if _duration_timer <= 0:
		stop_tornado()
		return
	
	# Update WaterManager vortex
	if water_manager:
		water_manager.trigger_vortex(global_position, radius, intensity, rotation_speed)
	
	# Visual rotation
	rotate_y(delta * rotation_speed * 0.5)

func start_tornado(pos: Vector3, duration: float = 30.0):
	global_position = pos
	_duration_timer = duration
	_is_active = true
	
	if cloud_particles:
		cloud_particles.emitting = true
	
	print("[TornadoController] Tornado spawned at ", pos, " for ", duration, "s")

func stop_tornado():
	_is_active = false
	if cloud_particles:
		cloud_particles.emitting = false
	
	if water_manager:
		water_manager.active_vortex = null
	
	print("[TornadoController] Tornado dissipated.")

func is_active() -> bool:
	return _is_active
