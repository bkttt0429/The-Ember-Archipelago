@tool
extends MeshInstance3D

func _ready():
	var mat = get_surface_override_material(0)
	if mat:
		# Sync Noises with WaterManager to ensure Physics matches Visuals
		var tex1 = mat.get_shader_parameter("vertex_noise_big")
		var tex2 = mat.get_shader_parameter("vertex_noise_big2")
		
		if WaterManager:
			if tex1 is NoiseTexture2D and tex1.noise:
				# Use set allowing type mismatch if noise is not exactly FastNoiseLite but compatible
				WaterManager.set("noise1", tex1.noise)
				# Update settings
				WaterManager.v_noise_tile = mat.get_shader_parameter("v_noise_tile")
				WaterManager.amplitude1 = mat.get_shader_parameter("amplitude1")
				
			if tex2 is NoiseTexture2D and tex2.noise:
				WaterManager.set("noise2", tex2.noise)
				WaterManager.amplitude2 = mat.get_shader_parameter("amplitude2")
				
			WaterManager.height_scale = mat.get_shader_parameter("height_scale")
			WaterManager.wave_speed = mat.get_shader_parameter("wave_speed")

	# Fix Foam: Manually assign ViewportTexture to Shader
	_setup_foam_texture(mat)

func _setup_foam_texture(mat: ShaderMaterial):
	var foam_viewport = get_node_or_null("../FoamViewport")
	if foam_viewport and mat:
		# Force update
		foam_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# Assign texture
		mat.set_shader_parameter("foam_mask", foam_viewport.get_texture())
		# Set mapping parameters to match viewport size
		mat.set_shader_parameter("foam_mask_size", float(foam_viewport.size.x) / 10.0) # Approx scaling, user can tune
		print("Foam Texture manually assigned via WaterController")




func _process(delta):
	var mat = get_surface_override_material(0)
	if mat:
		if not Engine.is_editor_hint() and WaterManager:
			# GAME RUNTIME: Sync with Physics Manager
			mat.set_shader_parameter("sync_time", WaterManager._time)
			if Engine.get_frames_drawn() % 60 == 0:
				print("Water Synced. Time: ", WaterManager._time)
		else:
			# EDITOR MODE: Simulate time locally
			# WaterManager doesn't tick in Editor, so we must drive it manually to see waves
			var t = Time.get_ticks_msec() / 1000.0
			mat.set_shader_parameter("sync_time", t)
