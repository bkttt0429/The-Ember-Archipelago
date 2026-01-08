@tool
extends Node3D

# 🔧 调试开关
@export var debug_wireframe: bool = false:
	set(value):
		debug_wireframe = value
		_update_wireframe()

@export var debug_show_lod_colors: bool = false:
	set(value):
		debug_show_lod_colors = value
		_update_lod_colors()

# ✅ 新增：控制波浪网格可见性
@export var show_wave_grid: bool = false:
	set(value):
		show_wave_grid = value
		var grid_root = get_node_or_null("WaveDebugGrid")
		if grid_root:
			grid_root.visible = value

@export var skirt_depth_override: float = -1.0:
	set(value):
		skirt_depth_override = value
		var clipmap = get_node_or_null("OceanLOD")
		if clipmap and value >= 0:
			clipmap.skirt_depth = value
			if clipmap.has_method("_rebuild_clipmap"):
				clipmap._rebuild_clipmap()
			print("Skirt Depth Override: ", value)

@export var create_test_scene: bool = false:
	set(value):
		if value:
			_setup_scene()

@export var toggle_ripple_color: bool = false:
	set(value):
		toggle_ripple_color = value
		var local = get_node_or_null("LocalOceanSim")
		if local:
			local.debug_color_ripples = value
			local._update_snapping()

var ocean_generator: Node = null
var grid_probes: Array[Node3D] = []
var local_ocean_sim: Node3D = null
var physics_ball: Node3D = null

func _ready():
	if not Engine.is_editor_hint():
		_setup_scene()

func _setup_scene():
	if not is_inside_tree():
		return
		
	var tree = get_tree()
	if not tree:
		return

	grid_probes.clear()
	debug_show_lod_colors = false
	debug_wireframe = false
	
	var gd_ocean_class = ClassDB.class_exists("OceanWaveGenerator")
	if not gd_ocean_class:
		printerr("GDExtension 'OceanWaveGenerator' not found!")
		return

	var nodes_to_clean = ["OceanGenerator", "WaveDebugGrid", "PhysicsBall", "Spectator", "GlobalOceanSim", "LocalOceanSim", "MainCamera", "OceanLOD", "Sun", "WorldEnvironment"]
	for node_name in nodes_to_clean:
		if has_node(node_name):
			get_node(node_name).queue_free()

	await tree.process_frame
	
	var gen = ClassDB.instantiate("OceanWaveGenerator")
	if not gen:
		printerr("Failed to instantiate OceanWaveGenerator")
		return
		
	gen.name = "OceanGenerator"
	add_child(gen)
	gen.owner = tree.edited_scene_root
	ocean_generator = gen
	print("Created OceanWaveGenerator")

	# ✅ 修复：创建更小、更稀疏的调试网格
	var grid_root = Node3D.new()
	grid_root.name = "WaveDebugGrid"
	grid_root.visible = false  # 默认隐藏
	add_child(grid_root)
	grid_root.owner = tree.edited_scene_root
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.1  # ✅ 从 0.5 减小到 0.1
	sphere_mesh.height = 0.2  # ✅ 从 1.0 减小到 0.2
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.CYAN
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.7  # ✅ 半透明
	sphere_mesh.material = material

	# ✅ 从每4米改为每8米一个球体，减少数量
	for x in range(0, 64, 8):
		for z in range(0, 64, 8):
			var probe = MeshInstance3D.new()
			probe.mesh = sphere_mesh
			probe.position = Vector3(x, 0, z)
			grid_root.add_child(probe)
			grid_probes.append(probe)
			
	print("Created Visualization Grid (Hidden by default)")
	
	if ClassDB.class_exists("BuoyancyProbe3D"):
		var ball = ClassDB.instantiate("BuoyancyProbe3D")
		ball.name = "PhysicsBall"
		add_child(ball)
		ball.owner = tree.edited_scene_root
		ball.position = Vector3(100, 5, 0)  # ✅ 移到 spectator 附近
		physics_ball = ball
		
		var ball_mesh_inst = MeshInstance3D.new()
		var bmesh = SphereMesh.new()
		bmesh.radius = 1.0
		bmesh.height = 2.0
		ball_mesh_inst.mesh = bmesh
		var red_mat = StandardMaterial3D.new()
		red_mat.albedo_color = Color.RED
		ball_mesh_inst.material_override = red_mat
		ball.add_child(ball_mesh_inst)
		
		var relative_path = ball.get_path_to(gen)
		ball.set_ocean_node(relative_path)
		ball.set_buoyancy_force(20.0)
		ball.set_water_drag(1.0)
		
		print("Created Physics Buoyancy Ball")
	else:
		printerr("BuoyancyProbe3D class not found")

	var local_sim = _setup_local_ocean_test()
	local_ocean_sim = local_sim
	
	var spectator = Node3D.new()
	spectator.name = "Spectator"
	add_child(spectator)
	spectator.owner = tree.edited_scene_root
	spectator.position = Vector3(80, 5, -1)  # ✅ 从 (100,5,0) 改为场景中心附近
	
	var spec_mesh = MeshInstance3D.new()
	spec_mesh.mesh = BoxMesh.new()
	spectator.add_child(spec_mesh)
	
	if local_ocean_sim:
		local_ocean_sim.follow_target = spectator
	
	var clipmap = get_node_or_null("OceanLOD")
	if clipmap:
		clipmap.follow_target = spectator
	
	var cam = get_viewport().get_camera_3d()
	if not cam:
		cam = Camera3D.new()
		cam.name = "MainCamera"
		add_child(cam)
		cam.owner = get_tree().edited_scene_root
		cam.current = true
		print("Created MainCamera")
		
	if cam:
		# ✅ 调整相机位置以查看整个场景
		cam.position = Vector3(104, 13, 2)
		cam.look_at(Vector3(80, 0, -1), Vector3.UP)

	if not has_node("Sun"):
		var sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
		sun.owner = get_tree().edited_scene_root
		sun.position = Vector3(100, 50, 0)
		sun.look_at(Vector3(100, 0, 0), Vector3.LEFT)
		sun.shadow_enabled = true
		print("Created Sun")
		
	if not has_node("WorldEnvironment"):
		var env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		var env = Environment.new()
		env.background_mode = Environment.BG_SKY
		var sky = Sky.new()
		var sky_mat = ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.3, 0.5, 0.8)
		sky_mat.sky_horizon_color = Color(0.6, 0.7, 0.8)
		sky_mat.ground_bottom_color = Color(0.1, 0.2, 0.3)
		sky_mat.ground_horizon_color = Color(0.6, 0.7, 0.8)
		sky.sky_material = sky_mat
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env_node.environment = env
		add_child(env_node)
		env_node.owner = get_tree().edited_scene_root
		print("Created WorldEnvironment")
		
	print("✅ Scene Setup Complete")
	print("🔧 Debug Controls:")
	print("  - Toggle 'show_wave_grid' to see debug spheres")
	print("  - Toggle 'debug_wireframe' to see mesh topology")
	print("  - Press C to toggle ripple colors")
	print("  - Press SPACE to create splash")

@export var lock_camera: bool = false
@export var camera_distance: float = 15.0
@export var camera_height: float = 8.0
@export var track_target: bool = false  # ✅ 默认关闭跟踪

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = max(5.0, camera_distance - 2.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = min(50.0, camera_distance + 2.0)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			var local_sim_node = get_node_or_null("LocalOceanSim")
			var spectator = get_node_or_null("Spectator")
			if local_sim_node and spectator:
				local_sim_node.add_interaction_world(spectator.global_position, 5.0, 10.0)
				print("Splash Triggered at ", spectator.global_position)
				
		elif event.keycode == KEY_C:
			var local_sim_node = get_node_or_null("LocalOceanSim")
			if local_sim_node:
				local_sim_node.debug_color_ripples = not local_sim_node.debug_color_ripples
				local_sim_node._update_snapping() 
				print("Ripple Color Toggled: ", local_sim_node.debug_color_ripples)
				
		elif event.keycode == KEY_W:
			debug_wireframe = not debug_wireframe
			print("Wireframe Mode: ", debug_wireframe)
			
		elif event.keycode == KEY_G:
			show_wave_grid = not show_wave_grid
			print("Wave Grid Visible: ", show_wave_grid)

var time_elapsed = 0.0
func _process(_delta: float):
	var spectator = get_node_or_null("Spectator")
	
	# ✅ 只在显示时更新波浪网格
	if show_wave_grid and ocean_generator and not grid_probes.is_empty() and spectator:
		var center_x = floor(spectator.global_position.x / 8.0) * 8.0
		var center_z = floor(spectator.global_position.z / 8.0) * 8.0
		var i = 0
		for x_off in range(-32, 32, 8):
			for z_off in range(-32, 32, 8):
				if i < grid_probes.size():
					var probe = grid_probes[i]
					if is_instance_valid(probe):
						var world_x = center_x + x_off
						var world_z = center_z + z_off
						var h = ocean_generator.get_wave_height(world_x, world_z)
						probe.global_position = Vector3(world_x, h, world_z)
				i += 1
				
	if physics_ball and local_ocean_sim:
		var center = Vector3(80, 5, -1)  # ✅ 匹配新的场景中心
		var radius = 15.0
		var ball_speed = 1.3
		var bx = center.x + cos(-time_elapsed * ball_speed + PI) * radius
		var bz = center.z + sin(-time_elapsed * ball_speed + PI) * radius
		physics_ball.position = Vector3(bx, 5, bz)
		local_ocean_sim.add_interaction_world(physics_ball.global_position, 2.0, 5.0)
				
	time_elapsed += _delta
	
	# 更新 spectator 位置
	if spectator:
		var center = Vector3(80, 5, -1)
		var radius = 20.0
		var speed = 1.0 
		var x = center.x + cos(time_elapsed * speed) * radius
		var z = center.z + sin(time_elapsed * speed) * radius
		spectator.position = Vector3(x, 5, z)

	var cam = get_viewport().get_camera_3d()
	if cam:
		if lock_camera:
			cam.position = Vector3(104, 13, 2)
			cam.look_at(Vector3(80, 0, -1), Vector3.UP)
		elif track_target and physics_ball:
			var target_pos = physics_ball.position
			var offset = Vector3(0, camera_height, camera_distance)
			var desired_pos = target_pos + offset
			cam.position = cam.position.lerp(desired_pos, _delta * 3.0)
			cam.look_at(target_pos)

func _setup_local_ocean_test() -> Node3D:
	print("Setting up Hybrid Ocean Simulation...")
	
	var local_ocean_script = load("res://Development/TechResearch/OceanVisuals/GpuLocalOcean.gd")
	var global_ocean_script = load("res://Development/TechResearch/OceanVisuals/GpuOcean.gd")
	var clipmap_script = load("res://Development/TechResearch/OceanVisuals/OceanClipmap.gd")
	
	if not local_ocean_script or not global_ocean_script:
		printerr("Scripts not found")
		return null

	var swe_shader = load("res://Development/TechResearch/OceanVisuals/swe_ocean.glsl")
	var fft_shader = load("res://Development/TechResearch/OceanVisuals/Shaders/fft_ocean.glsl")
	var water_shader = load("res://Development/TechResearch/OceanVisuals/Shaders/water_lowpoly.gdshader")
	
	if not swe_shader or not fft_shader or not water_shader:
		printerr("Shaders not found")
		return null
	
	var water_mat = ShaderMaterial.new()
	water_mat.shader = water_shader
	water_mat.set_shader_parameter("albedo", Color(0.0, 0.2, 0.5))
	water_mat.set_shader_parameter("height_scale", 2.0) 
	water_mat.set_shader_parameter("choppiness", 0.0) 
	water_mat.set_shader_parameter("texture_scale", 64.0) 
	water_mat.set_shader_parameter("foam_threshold", 0.1) 
	water_mat.set_shader_parameter("debug_show_swe_area", false)
	water_mat.set_shader_parameter("debug_show_blend", false)
	water_mat.set_shader_parameter("swe_color_strength", 0.0)

	# 1. Global Ocean (FFT)
	var global_ocean = Node3D.new()
	global_ocean.set_script(global_ocean_script)
	global_ocean.name = "GlobalOceanSim"
	global_ocean.compute_shader = fft_shader
	global_ocean.texture_size = 256
	global_ocean.material_to_update = water_mat
	add_child(global_ocean)
	global_ocean.owner = get_tree().edited_scene_root
	global_ocean._init_compute()

	# 2. Local Ocean (SWE)
	var local_ocean = Node3D.new()
	local_ocean.set_script(local_ocean_script)
	local_ocean.name = "LocalOceanSim"
	local_ocean.compute_shader = swe_shader
	local_ocean.texture_size = 256
	local_ocean.grid_size = 64.0
	local_ocean.material_to_update = water_mat
	add_child(local_ocean)
	local_ocean.owner = get_tree().edited_scene_root
	local_ocean.position = Vector3(80, 0, -1)
	local_ocean._init_compute()

	# 3. Clipmap (LOD)
	var clipmap = Node3D.new()
	if clipmap_script:
		clipmap.set_script(clipmap_script)
		clipmap.name = "OceanLOD"
		clipmap.clipmap_levels = 6
		clipmap.base_grid_size = 64.0
		clipmap.base_subdivisions = 32
		clipmap.skirt_depth = 2.0
		
		add_child(clipmap)
		clipmap.owner = get_tree().edited_scene_root
		
		clipmap.set_material(water_mat)
	
	print("✅ Hybrid Ocean Created")
	return local_ocean

# 🔧 调试功能
func _update_wireframe():
	var clipmap = get_node_or_null("OceanLOD")
	if not clipmap:
		return
		
	for child in clipmap.get_children():
		if child is MeshInstance3D:
			if debug_wireframe:
				var wire_mat = StandardMaterial3D.new()
				wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				wire_mat.albedo_color = Color.WHITE
				wire_mat.no_depth_test = true
				wire_mat.render_priority = 10
				wire_mat.wireframe = true
				child.material_override = wire_mat
			else:
				child.material_override = null

func _update_lod_colors():
	var clipmap = get_node_or_null("OceanLOD")
	if not clipmap:
		return
		
	var colors = [
		Color.RED, Color.GREEN, Color.BLUE,
		Color.YELLOW, Color.MAGENTA, Color.CYAN
	]
	
	var idx = 0
	for child in clipmap.get_children():
		if child is MeshInstance3D:
			if debug_show_lod_colors:
				var debug_mat = StandardMaterial3D.new()
				debug_mat.albedo_color = colors[idx % colors.size()]
				debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				child.material_override = debug_mat
			else:
				child.material_override = null
			idx += 1
