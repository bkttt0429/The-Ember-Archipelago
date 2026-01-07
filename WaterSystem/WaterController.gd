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
@export var lerp_speed: float = 2.0

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
	
	# 2. Wavelength approximation based on wind speed (Dominant wavelength)
	# L = g * T^2 / (2 * PI), where T ~ V_wind * 0.5 (very rough heuristic)
	# Let's use a simpler heuristic for a styled game:
	_target_wavelength = clamp(wind_speed * 2.0, 2.0, 50.0)

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
	
	# Update wave directions (Multi-wave setup)
	var dir_a = wind_direction
	var dir_b = rotate_vector2(wind_direction, 35.0) 
	
	var wave_a = mat.get_shader_parameter("wave_a")
	if wave_a:
		wave_a.x = dir_a.x
		wave_a.y = dir_a.y
		wave_a.w = _target_wavelength
		mat.set_shader_parameter("wave_a", wave_a)

	var wave_b = mat.get_shader_parameter("wave_b")
	if wave_b:
		wave_b.x = dir_b.x
		wave_b.y = dir_b.y
		wave_b.w = _target_wavelength * 1.5
		mat.set_shader_parameter("wave_b", wave_b)

	# --- AUTOMATED SYNC TO WaterManager via Reflection ---
	if WaterManager:
		var params_to_sync = [
			"height_scale", "wave_a", "wave_b", "wave_c", "wave_d", "wave_e",
			"wave_speed", "ripple_height_scale",
			"waterspout_pos", "waterspout_radius", "waterspout_strength",
			"global_flow_direction", "global_flow_speed"
		]
		for p_name in params_to_sync:
			var val = mat.get_shader_parameter(p_name)
			if val != null:
				WaterManager.set(p_name, val)

	# DRIVE TIME in Shader
	if not Engine.is_editor_hint() and WaterManager:
		mat.set_shader_parameter("sync_time", WaterManager._time)
	else:
		var t = Time.get_ticks_msec() / 1000.0
		mat.set_shader_parameter("sync_time", t)

func rotate_vector2(v: Vector2, angle_deg: float) -> Vector2:
	var rad = deg_to_rad(angle_deg)
	return Vector2(
		v.x * cos(rad) - v.y * sin(rad),
		v.x * sin(rad) + v.y * cos(rad)
	)
