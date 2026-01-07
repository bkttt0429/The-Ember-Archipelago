extends Node

# Singleton instance for easy access
static var instance: Node

# N64 Buoyancy Parameters (Must match Shader)
@export_group("Wave Parameters")
@export var height_scale: float = 1.0
@export var wave_speed: float = 0.05 # Match shader default
@export var amplitude1: float = 2.0
@export var amplitude2: float = 0.5
@export var v_noise_tile: float = 200.0

@export_group("Waterspout Buoyancy Sync")
@export var waterspout_pos: Vector3 = Vector3(0, -100, 0)
@export var waterspout_radius: float = 5.0
@export var waterspout_strength: float = 0.0
@export var waterspout_spiral_strength: float = 8.0
@export var waterspout_darkness_factor: float = 0.8


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
	# N64 shader is vertical displacement only, so iterative solver is not needed for XZ
	# Just return Y displacement directly
	return _get_displacement_noise(world_pos).y

func fast_water_height(world_pos: Vector3) -> float:
	return _get_displacement_noise(world_pos).y

func get_water_velocity(world_pos: Vector3) -> Vector3:
	var flow = Vector3(global_flow_direction.x, 0, global_flow_direction.y) * global_flow_speed
	
	# Waterspout Vortex Logic
	var spout_center_xz = Vector2(waterspout_pos.x, waterspout_pos.z)
	var pos_xz = Vector2(world_pos.x, world_pos.z)
	var dist_to_spout = pos_xz.distance_to(spout_center_xz)
	
	if dist_to_spout < waterspout_radius * 2.0 and dist_to_spout > 0.001:
		var influence = clampf(1.0 - dist_to_spout / (waterspout_radius * 2.0), 0.0, 1.0)
		var to_center_xz = (spout_center_xz - pos_xz).normalized()
		var tangent = Vector3(-to_center_xz.y, 0, to_center_xz.x)
		var vortex_vel = tangent * waterspout_strength * 2.0 * influence
		var suction_vel = Vector3.DOWN * waterspout_strength * influence
		flow += vortex_vel + suction_vel
		
	return flow

func _get_displacement_noise(p: Vector3) -> Vector3:
	var t_s = _time * wave_speed
	
	# 1. Planar Wave (Far from center)
	var move1 = t_s * v_noise_tile 
	var n1_planar = (noise1.get_noise_2d(p.x + move1, p.z + move1) + 1.0) * 0.5 
	var n2_planar = (noise2.get_noise_2d(p.x - move1 + 0.3 * v_noise_tile, p.z + 0.476 * v_noise_tile) + 1.0) * 0.5
	
	var h_planar = 0.0
	h_planar += n1_planar * amplitude1
	h_planar += n2_planar * amplitude2
	
	# 2. Polar Wave (Near center)
	var h_vortex = 0.0
	var dist_to_center = Vector2(p.x, p.z).distance_to(Vector2(waterspout_pos.x, waterspout_pos.z))
	
	if dist_to_center < waterspout_radius * 3.0:
		var polar = _cartesian_to_polar(Vector2(p.x, p.z), Vector2(waterspout_pos.x, waterspout_pos.z))
		var r = polar.x
		var theta = polar.y
		
		# Match Shader UV logic:
		var u = r * (1.0 / 20.0) * 100.0 
		var v_scroll = _time * waterspout_spiral_strength * 2.0
		var v = (theta / (2.0 * PI)) * 400.0 + v_scroll
		
		var n1_vortex = (noise1.get_noise_2d(u, v) + 1.0) * 0.5
		var n2_vortex = (noise2.get_noise_2d(u + 50.0, v * 0.9 + 30.0) + 1.0) * 0.5
		
		h_vortex += n1_vortex * amplitude1
		h_vortex += n2_vortex * amplitude2
		
	# 3. Mix
	var vortex_influence = smoothstep(waterspout_radius * 2.5, waterspout_radius * 0.5, dist_to_center)
	var h_final = lerp(h_planar, h_vortex, vortex_influence)
	
	h_final -= height_scale / 2.0
	h_final *= height_scale
	
	var disp = Vector3(0.0, h_final, 0.0)
	
	# APPLY WATERSPOUT (Depth)
	var dist_to_spout = Vector2(p.x, p.z).distance_to(Vector2(waterspout_pos.x, waterspout_pos.z))
	if dist_to_spout < waterspout_radius:
		var spout_m = 1.0 
		var depth = spout_m * waterspout_strength * (1.0 - dist_to_spout / waterspout_radius)
		disp.y -= depth
		
	return disp

func _cartesian_to_polar(cartesian: Vector2, center: Vector2) -> Vector2:
	var rel = cartesian - center
	var r = rel.length()
	var theta = atan2(rel.y, rel.x)
	return Vector2(r, theta)
