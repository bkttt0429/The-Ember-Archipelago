extends Node

# Singleton instance for easy access
static var instance: Node

# Gerstner Wave Parameters (Must match Shader)
@export_group("Gerstner Waves")
@export var wave_a = Vector4(1.0, 0.0, 0.15, 10.0) # Direction X, Y, Steepness, Wavelength
@export var wave_b = Vector4(0.0, 1.0, 0.15, 20.0)
@export var wave_c = Vector4(0.7, 0.7, 0.1, 5.0)
@export var wave_d = Vector4(-0.5, 0.5, 0.08, 3.0)
@export var wave_e = Vector4(0.2, -0.8, 0.05, 1.5)

# Ripple Settings (Secondary Noise)
# Ripple Settings (Secondary Noise)
@export var ripple_height_scale: float = 0.1
@export var v_noise_tile: int = 200 # Texture tiling scale
@export var height_scale: float = 1.0
@export var amplitude1: float = 2.0
@export var amplitude2: float = 0.5

# Missing variables restored
@export var wave_speed: float = 0.05
var noise1: FastNoiseLite
var noise2: FastNoiseLite
var _time: float = 0.0

func _enter_tree():
	instance = self
	_init_default_noise()

func _init_default_noise():
	# Keep existing noise init for ripples
	noise1 = FastNoiseLite.new()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise1.seed = 700
	noise1.frequency = 0.0194
	
	noise2 = FastNoiseLite.new() # Unused in new logic but kept for safety
	noise2.frequency = 0.075

func _process(delta):
	_time += delta 

func get_wave_height(world_pos: Vector3) -> float:
	# 1. Iterative Solver to find the original vertex position (XZ) 
	# that displaced to the current world_pos.
	var p = world_pos
	# 3 iterations is usually enough for good accuracy
	for i in range(3):
		var displacement = _get_displacement(p)
		# The error is the difference between where the guess displaced to, 
		# and where we actually are.
		var current_p_xz = p + Vector3(displacement.x, 0.0, displacement.z)
		var diff = current_p_xz - Vector3(world_pos.x, 0.0, world_pos.z)
		
		# Simple correction
		p.x -= diff.x
		p.z -= diff.z
	
	# 2. Once we found the source point 'p', calculate its Y displacement
	# 2. Once we found the source point 'p', calculate its Y displacement
	# Apply Domain Warp (Same as Shader)
	var warp_x = sin(p.z * 0.1 + _time * 0.1) * 4.0
	var warp_z = cos(p.x * 0.1 + _time * 0.1) * 4.0
	var p_warped = p + Vector3(warp_x, 0.0, warp_z)
	
	var final_disp = _get_displacement(p_warped)
	
	# 3. Add Ripples (Height only, no XZ displacement)
	# Note: CPU noise sampling might not perfectly align with shader UVs if not carefully matched,
	# but for surface chatter it's acceptable.
	var ripples = _sample_ripple_noise(world_pos.x, world_pos.z)
	
	return final_disp.y + ripples

func _get_displacement(p: Vector3) -> Vector3:
	var disp = Vector3.ZERO
	disp += _gerstner_wave(wave_a, p)
	disp += _gerstner_wave(wave_b, p)
	disp += _gerstner_wave(wave_c, p)
	disp += _gerstner_wave(wave_d, p)
	disp += _gerstner_wave(wave_e, p)
	return disp

func _gerstner_wave(params: Vector4, p: Vector3) -> Vector3:
	var steepness = params.z
	var wavelength = params.w
	
	var k = 2.0 * PI / wavelength
	var c = sqrt(9.8 / k)
	var d = Vector2(params.x, params.y).normalized()
	
	# f = k * (dot(d, p.xz) - c * time * speed)
	var f = k * (d.dot(Vector2(p.x, p.z)) - c * _time * wave_speed)
	var a = steepness / k
	
	var cos_f = cos(f)
	var sin_f = sin(f)
	
	return Vector3(
		d.x * (a * cos_f),
		a * sin_f,
		d.y * (a * cos_f)
	)

func _sample_ripple_noise(x: float, z: float) -> float:
	# Matches Shader: texture(vertex_noise_big, uv * 0.1 + vec2(time * 0.02, 0.0))
	# CPU Noise takes inputs roughly in 0..1 range for frequency ~1.
	# But FastNoiseLite frequency is already set to ~0.02.
	# We just need to handle the movement.
	var move = _time * 0.05 * 200.0 * 0.02 # approximating shader offset
	var val = noise1.get_noise_2d(x + move, z)
	return val * ripple_height_scale
