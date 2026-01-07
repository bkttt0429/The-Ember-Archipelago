extends Node

# Singleton instance for easy access
static var instance: Node

# Gerstner Wave Parameters (Must match Shader)
@export_group("Gerstner Waves")
@export var wave_a = Vector4(1.0, 0.0, 0.3, 10.0)   # 优化：steepness 0.15 → 0.3
@export var wave_b = Vector4(0.0, 1.0, 0.25, 15.0)  # 优化：steepness 0.15 → 0.25, wavelength 20 → 15
@export var wave_c = Vector4(0.7, 0.7, 0.2, 5.0)     # 优化：steepness 0.1 → 0.2
@export var wave_d = Vector4(-0.5, 0.5, 0.15, 3.0)  # 优化：steepness 0.08 → 0.15
@export var wave_e = Vector4(0.2, -0.8, 0.12, 1.5)  # 优化：steepness 0.05 → 0.12

@export_group("Global Scale & Speed")
@export var height_scale: float = 1.0
@export var wave_speed: float = 0.18  # 优化：从 0.05 增加到 0.18（提升 3.6 倍）

@export_group("Waterspout Buoyancy Sync")
@export var waterspout_pos: Vector3 = Vector3(0, -100, 0)
@export var waterspout_radius: float = 5.0
@export var waterspout_strength: float = 0.0

# Ripple Settings (Secondary Noise)
@export_group("Ripples")
@export var ripple_height_scale: float = 0.1

@export_group("Flow Field")
@export var global_flow_direction: Vector2 = Vector2(1.0, 0.0)
@export var global_flow_speed: float = 0.5

var noise1: FastNoiseLite
var _time: float = 0.0

func _enter_tree():
	instance = self
	_init_default_noise()

func _init_default_noise():
	noise1 = FastNoiseLite.new()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise1.seed = 700
	noise1.frequency = 0.0194

func _process(delta):
	_time += delta 

func get_wave_height(world_pos: Vector3, iterations: int = 3) -> float:
	# 1. Iterative Solver (XZ displacement)
	var p = world_pos
	for i in range(iterations):
		var displacement = _get_displacement(p)
		var current_p_xz = p + Vector3(displacement.x, 0.0, displacement.z)
		var diff = current_p_xz - Vector3(world_pos.x, 0.0, world_pos.z)
		p.x -= diff.x
		p.z -= diff.z
	
	# 2. Final Displacement
	var final_disp = _get_displacement(p)
	
	# 3. Add Ripples
	var ripples = _sample_ripple_noise(world_pos.x, world_pos.z)
	
	return final_disp.y + ripples

# 优化：快速模式 - 跳过迭代求解器，直接计算（性能提升 3-5 倍）
func fast_water_height(world_pos: Vector3) -> float:
	# 直接计算位移，不进行迭代求解
	var final_disp = _get_displacement(world_pos)
	
	# Add Ripples
	var ripples = _sample_ripple_noise(world_pos.x, world_pos.z)
	
	return final_disp.y + ripples

func get_water_velocity(world_pos: Vector3) -> Vector3:
	var flow = Vector3(global_flow_direction.x, 0, global_flow_direction.y) * global_flow_speed
	
	# Waterspout Vortex Logic
	var spout_center_xz = Vector2(waterspout_pos.x, waterspout_pos.z)
	var pos_xz = Vector2(world_pos.x, world_pos.z)
	var dist_to_spout = pos_xz.distance_to(spout_center_xz)
	
	if dist_to_spout < waterspout_radius * 2.0 and dist_to_spout > 0.001:
		var influence = clampf(1.0 - dist_to_spout / (waterspout_radius * 2.0), 0.0, 1.0)
		# Tangent direction for vortex (clockwise)
		var to_center_xz = (spout_center_xz - pos_xz).normalized()
		var tangent = Vector3(-to_center_xz.y, 0, to_center_xz.x)
		var vortex_vel = tangent * waterspout_strength * 2.0 * influence
		# Downward suction
		var suction_vel = Vector3.DOWN * waterspout_strength * influence
		flow += vortex_vel + suction_vel
		
	return flow

func _get_displacement(p: Vector3) -> Vector3:
	var disp = Vector3.ZERO
	disp += _gerstner_wave(wave_a, p)
	disp += _gerstner_wave(wave_b, p)
	disp += _gerstner_wave(wave_c, p)
	disp += _gerstner_wave(wave_d, p)
	disp += _gerstner_wave(wave_e, p)
	
	# APPLY GLOBAL SCALE (Mandatory for Prompt A physics)
	disp *= height_scale
	
	# APPLY WATERSPOUT (Mandatory for Prompt B buoyancy alignment)
	var dist_to_spout = Vector2(p.x, p.z).distance_to(Vector2(waterspout_pos.x, waterspout_pos.z))
	if dist_to_spout < waterspout_radius:
		var spout_m = 1.0 # Within radius
		var depth = spout_m * waterspout_strength * (1.0 - dist_to_spout / waterspout_radius)
		disp.y -= depth
		
	return disp

func _gerstner_wave(params: Vector4, p: Vector3) -> Vector3:
	var steepness = params.z
	var wavelength = params.w
	
	if wavelength < 0.01: return Vector3.ZERO
	
	var k = 2.0 * PI / wavelength
	if k <= 0.0: return Vector3.ZERO
	
	var c = sqrt(9.8 / k)
	var d_vec = Vector2(params.x, params.y)
	if d_vec.length_squared() < 0.0001: return Vector3.ZERO
	
	var d = d_vec.normalized()
	var f = k * (d.dot(Vector2(p.x, p.z)) - c * _time * wave_speed)
	var a = steepness / k
	
	var res = Vector3(
		d.x * (a * cos(f)),
		a * sin(f),
		d.y * (a * cos(f))
	)
	
	if is_nan(res.x) or is_nan(res.y) or is_nan(res.z):
		return Vector3.ZERO
		
	return res

func _sample_ripple_noise(x: float, z: float) -> float:
	# Sync with Shader: texture() returns 0..1. noise.get_noise_2d returns -1..1.
	# GLSL 'vector + scalar' adds scalar to ALL components.
	var move = _time * 0.01
	var val = (noise1.get_noise_2d(x * 0.05 + move, z * 0.05 + move) + 1.0) * 0.5
	return val * ripple_height_scale
