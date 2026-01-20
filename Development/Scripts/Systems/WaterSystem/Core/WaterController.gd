@tool
extends MeshInstance3D

## N64 Water Controller (WaterController.gd)
## This script drives the water visualization and synchronizes physics data with WaterManager.

var water_manager: WaterSystemManager

@export_group("Smooth Sync")
## How fast parameters interpolate towards the target physics values.
@export var lerp_speed: float = 4.0

@export_group("Water Colors")
@export var shallow_color: Color = Color(0.25, 0.7, 0.85):
	set(value):
		shallow_color = value
		_update_colors()
@export var mid_color: Color = Color(0.1, 0.45, 0.65):
	set(value):
		mid_color = value
		_update_colors()
@export var deep_color: Color = Color(0.05, 0.25, 0.45):
	set(value):
		deep_color = value
		_update_colors()

func _ready():
	_update_colors()
	
	# Find Water Manager
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if managers.size() > 0:
		water_manager = managers[0]
	
	var mat = get_surface_override_material(0)
	if mat:
		# Fix Foam: Manually assign ViewportTexture to Shader
		_setup_foam_texture(mat)

func _update_colors():
	var mat = get_surface_override_material(0)
	if mat:
		mat.set_shader_parameter("surface_albedo", shallow_color)
		mat.set_shader_parameter("surface_bottom", deep_color)
		# N64 shader uses: surface_albedo (shallow), surface_bottom (deep/color)
		# mid_color not explicitly used in N64 intense shader, ignored for now.

func _setup_foam_texture(mat: ShaderMaterial):
	var foam_viewport = get_node_or_null("../FoamViewport")
	if foam_viewport and mat:
		foam_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		mat.set_shader_parameter("foam_mask", foam_viewport.get_texture())
		# N64 shader "foam_mask_size" defaults to 51.2, or custom
		mat.set_shader_parameter("foam_mask_size", float(foam_viewport.size.x) / 10.0)
		print("Foam Texture manually assigned via WaterController")

func _process(delta):
	var mat = get_surface_override_material(0)
	if not mat: return

	# 1. Drive Time in Shader
	var current_time: float
	if not Engine.is_editor_hint() and water_manager and water_manager._time != null:
		current_time = water_manager._time
	else:
		current_time = Time.get_ticks_msec() / 1000.0
	
	# N64 Shader usually uses TIME internally, but our modified one uses sync_time
	mat.set_shader_parameter("sync_time", current_time)
	
	# 2. Sync to WaterManager
	if water_manager:
		# Read values from Manager (Authority) and apply to Shader
		var h_scale = water_manager.height_scale
		# var w_speed = water_manager.wave_speed
		# var amp1 = water_manager.amplitude1
		# var amp2 = water_manager.amplitude2
		
		mat.set_shader_parameter("height_scale", h_scale)
		# mat.set_shader_parameter("wave_speed", w_speed)
		# mat.set_shader_parameter("amplitude1", amp1)
		# mat.set_shader_parameter("amplitude2", amp2)
		
		# Sync Waterspout
		mat.set_shader_parameter("waterspout_pos", water_manager.waterspout_pos)
		mat.set_shader_parameter("waterspout_radius", water_manager.waterspout_radius)
		mat.set_shader_parameter("waterspout_strength", water_manager.waterspout_strength)
		mat.set_shader_parameter("waterspout_spiral_strength", water_manager.waterspout_spiral_strength)
		mat.set_shader_parameter("waterspout_darkness_factor", water_manager.waterspout_darkness_factor)
