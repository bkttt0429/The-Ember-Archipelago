extends Node

# Singleton instance for easy access
static var instance: Node

# N64 Buoyancy Parameters (Must match Shader)
@export_group("Wave Parameters")
@export var texture_scale: float = 64.0
@export var height_scale: float = 0.18
@export var wave_height_scale: float = 5.0
@export var time_scale: float = 0.1
@export var crest_sharpness: float = 0.8


@export_group("Flow Field")
@export var global_flow_direction: Vector2 = Vector2(1.0, 0.0)
@export var global_flow_speed: float = 0.5

# Internal Noise (Must match WaterMaterial.tres FastNoiseLite_lyiw1)
var noise1: FastNoiseLite
var noise2: FastNoiseLite # Optional second layer
var _time: float = 0.0

func _enter_tree():
	instance = self
	_init_default_noise()

func _init_default_noise():
	# Match FastNoiseLite_lyiw1 from WaterMaterial.tres
	noise1 = FastNoiseLite.new()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise1.seed = 700
	noise1.frequency = 0.0194
	noise1.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise1.fractal_octaves = 1
	noise1.fractal_lacunarity = -2.665
	noise1.fractal_gain = 2.46
	
	# Second layer (approximated or same noise with offset)
	noise2 = noise1.duplicate()
	noise2.seed = -40
	noise2.frequency = 0.0228
	noise2.fractal_octaves = 10

func _process(delta):
	_time += delta 

func get_wave_height(world_pos: Vector3, _iterations: int = 1) -> float:
	return _get_fft_analytic_height(world_pos)

func fast_water_height(world_pos: Vector3) -> float:
	return _get_fft_analytic_height(world_pos)

# Definition of Major Wave Components for Sync
# Format: [k_x, k_z, amplitude_real, amplitude_imag]
# Using prime numbers and varied directions to break repetition
var wave_components = [
	[1, 1, 100.0, 0.0],     # Base swell
	[2, 0, 50.0, -50.0],    # Crossing swell
	[-1, 2, 40.0, 30.0],    # Choppy interference
	[0, -2, 30.0, -20.0],   # Counter swell
	[-2, -1, 20.0, 20.0],   # Detail 1
	[3, 1, 15.0, -10.0]     # Detail 2
]


func _get_fft_analytic_height(p: Vector3) -> float:
	var total_h = 0.0
	
	# Sum all synchronized wave components
	for wave in wave_components:
		var kx = wave[0]
		var kz = wave[1]
		var amp_real = wave[2]
		var amp_imag = wave[3]
		
		# Calculate Frequency Vector K
		var k_vec = Vector2(kx, kz) * (2.0 * PI / texture_scale)
		
		# Dispersion Relation: w = sqrt(g * |k|)
		var w = sqrt(9.8 * k_vec.length())
		
		# Phase = K dot X - w * t
		var phase = k_vec.dot(Vector2(p.x, p.z)) - w * _time * time_scale
		
		# Complex Amplitude rotation: (a + ib) * (cos + isin)
		# Real part result: a*cos - b*sin
		total_h += amp_real * cos(phase) - amp_imag * sin(phase)
	
	# Normalization: FFT usually divides by N or N^2.
	# We use an empirical factor to match the GPU visual output magnitude.
	# Initial guess: 1.0 / texture_scale (approx 0.015 for size 64)
	var normalization = 1.0 / texture_scale 
	
	var final_h = total_h * normalization * height_scale * wave_height_scale
	
	if abs(crest_sharpness - 1.0) > 0.01:
		final_h = sign(final_h) * pow(abs(final_h), crest_sharpness)
		
	return final_h

func _cartesian_to_polar(cartesian: Vector2, center: Vector2) -> Vector2:
	var rel = cartesian - center
	var r = rel.length()
	var theta = atan2(rel.y, rel.x)
	return Vector2(r, theta)
