@tool
extends MeshInstance3D

## Prompt A: Sea State Controller (WaterController.gd)
## This script drives the water visualization and synchronizes physics data with WaterManager.

@export_group("Wind Dynamics")
## Wind speed in m/s. Wave height is derived from this: Hs = 0.02123 * V^2
@export var wind_speed: float = 10.0:
	set(value):
		wind_speed = value
		_update_wave_params()

## Direction the wind is blowing towards.
@export var wind_direction: Vector2 = Vector2(1.0, 0.0):
	set(value):
		wind_direction = value.normalized()
		_update_wave_params()

@export_group("Smooth Sync")
## How fast parameters interpolate towards the target physics values.
@export var lerp_speed: float = 4.0  # 优化：从 2.0 增加到 4.0，更快响应

# Internal target values calculated from physics formulas
var _target_amplitude: float = 0.5
var _target_wavelength: float = 10.0

func _init():
	# Ensure these are never Nil before _process runs
	_update_wave_params()

func _ready():
	_update_wave_params()
	
	var mat = get_surface_override_material(0)
	if mat:
		# Fix Foam: Manually assign ViewportTexture to Shader
		_setup_foam_texture(mat)

func _update_wave_params():
	# 1. Physical Wave Height Formula (Simplified Pierson-Moskowitz)
	# Hs = 0.02123 * V_wind^2
	_target_amplitude = 0.02123 * pow(wind_speed, 2.0)
	
	# 2. 视觉增强系数（优化：增加 50% 的视觉高度）
	var visual_boost: float = 1.5
	_target_amplitude *= visual_boost
	
	# 3. Wavelength approximation - 减少波长以增加视觉变化
	# 优化：从 wind_speed * 2.0 改为 wind_speed * 1.5，上限从 50 改为 30
	_target_wavelength = clamp(wind_speed * 1.5, 2.0, 30.0)

func _setup_foam_texture(mat: ShaderMaterial):
	var foam_viewport = get_node_or_null("../FoamViewport")
	if foam_viewport and mat:
		foam_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		mat.set_shader_parameter("foam_mask", foam_viewport.get_texture())
		mat.set_shader_parameter("foam_mask_size", float(foam_viewport.size.x) / 10.0)
		print("Foam Texture manually assigned via WaterController")

func _process(delta):
	var mat = get_surface_override_material(0)
	if not mat: return

	# 6. Smoothly interpolate shader parameters
	var current_amp = mat.get_shader_parameter("height_scale")
	if current_amp == null: current_amp = 1.0
	
	# Defence: ensure valid numerical values for interpolation
	var l_speed = lerp_speed if lerp_speed != null else 2.0
	var t_amp = _target_amplitude if _target_amplitude != null else 0.5
	
	var weight = clamp(delta * l_speed, 0.0, 1.0)
	var new_amp = lerpf(float(current_amp), float(t_amp), weight)
	
	mat.set_shader_parameter("height_scale", new_amp)
	
	var time = mat.get_shader_parameter("sync_time")
	if time == null: time = 0.0
	
	# Update wave directions (Multi-wave interference setup with drift)
	var waves = [
		{"param": "wave_a", "angle": 0.0 + sin(time * 0.05) * 2.0, "l_scale": 1.0},
		{"param": "wave_b", "angle": 35.0 + cos(time * 0.07) * 4.0, "l_scale": 1.5},
		{"param": "wave_c", "angle": -25.0 + sin(time * 0.03) * 3.0, "l_scale": 0.8},
		{"param": "wave_d", "angle": 80.0 + cos(time * 0.04) * 6.0, "l_scale": 0.5},
		{"param": "wave_e", "angle": -60.0 + sin(time * 0.02) * 5.0, "l_scale": 1.2}
	]
	
	for w_info in waves:
		var w_param = mat.get_shader_parameter(w_info.param)
		if w_param:
			var dir = rotate_vector2(wind_direction, w_info.angle)
			w_param.x = dir.x
			w_param.y = dir.y
			w_param.w = _target_wavelength * w_info.l_scale
			mat.set_shader_parameter(w_info.param, w_param)

	# --- AUTOMATED SYNC TO WaterManager via Reflection ---
	if WaterManager:
		var params_to_sync = [
			"height_scale", "wave_a", "wave_b", "wave_c", "wave_d", "wave_e",
			"wave_speed", "ripple_height_scale",
			"waterspout_pos", "waterspout_radius", "waterspout_strength",
			"waterspout_spiral_strength", "waterspout_spiral_arms", 
			"waterspout_foam_ring_inner", "waterspout_foam_ring_outer", 
			"waterspout_darkness_factor",
			"global_flow_direction", "global_flow_speed"
		]
		for p_name in params_to_sync:
			var val = mat.get_shader_parameter(p_name)
			if val != null:
				WaterManager.set(p_name, val)

	# DRIVE TIME in Shader (优化：确保时间始终更新)
	var current_time: float
	if not Engine.is_editor_hint() and WaterManager and WaterManager._time != null:
		current_time = WaterManager._time
	else:
		current_time = Time.get_ticks_msec() / 1000.0
	
	mat.set_shader_parameter("sync_time", current_time)
	
	# 确保 wave_speed 被正确设置（优化：同步 wave_speed）
	if WaterManager:
		mat.set_shader_parameter("wave_speed", WaterManager.wave_speed)

func rotate_vector2(v: Vector2, angle_deg: float) -> Vector2:
	var rad = deg_to_rad(angle_deg)
	return Vector2(
		v.x * cos(rad) - v.y * sin(rad),
		v.x * sin(rad) + v.y * cos(rad)
	)
