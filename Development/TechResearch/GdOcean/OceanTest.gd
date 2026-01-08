@tool
extends Node3D

# 這個腳本用於測試 GDExtension 的 OceanWaveGenerator 和 BuoyancyProbe3D
# 使用方法：
# 1. 在場景中建立一個 Node3D
# 2. 將此腳本掛載上去
# 3. 點擊 Inspector 中的 "Create Test Scene"

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
			local._update_snapping() # Force update parameters


var ocean_generator: Node = null
var grid_probes: Array[Node3D] = []
var local_ocean_sim: Node3D = null  # 修复：重命名避免变量遮蔽警告
var physics_ball: Node3D = null

func _ready():
	if not Engine.is_editor_hint():
		# Auto-start in game mode
		_setup_scene()


			
func _setup_scene():
	grid_probes.clear()
	
	var gd_ocean_class = ClassDB.class_exists("OceanWaveGenerator")
	if not gd_ocean_class:
		printerr("GDExtension 'OceanWaveGenerator' not found!")
		return

	# Cleanup old nodes to prevent duplicates
	var nodes_to_clean = ["OceanGenerator", "WaveDebugGrid", "PhysicsBall", "Spectator", "GlobalOceanSim", "LocalOceanSim", "MainCamera"]
	for node_name in nodes_to_clean:
		if has_node(node_name):
			get_node(node_name).queue_free()

	await get_tree().process_frame
	
	var gen = ClassDB.instantiate("OceanWaveGenerator")
	if not gen:
		printerr("Failed to instantiate OceanWaveGenerator")
		return
		
	gen.name = "OceanGenerator"
	add_child(gen)
	gen.owner = get_tree().edited_scene_root
	ocean_generator = gen
	print("Created OceanWaveGenerator")

	# 2. Create Debug Grid (Visualizer)
	var grid_root = Node3D.new()
	grid_root.name = "WaveDebugGrid"
	add_child(grid_root)
	grid_root.owner = get_tree().edited_scene_root
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.CYAN
	sphere_mesh.material = material

	for x in range(0, 64, 4):
		for z in range(0, 64, 4):
			var probe = MeshInstance3D.new()
			probe.mesh = sphere_mesh
			probe.position = Vector3(x, 0, z)
			grid_root.add_child(probe)
			grid_probes.append(probe)
			
	print("Created Visualization Grid")
	
	# 3. Create a Physics Test Ball (BuoyancyProbe3D)
	if ClassDB.class_exists("BuoyancyProbe3D"):
		var ball = ClassDB.instantiate("BuoyancyProbe3D")
		ball.name = "PhysicsBall"
		add_child(ball)
		ball.owner = get_tree().edited_scene_root
		ball.position = Vector3(32, 5, 32)
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
		
		# 修复：使用相对路径而不是绝对路径（避免编辑器内部节点路径）
		# 使用从 ball 到 gen 的相对路径（ball 和 gen 都是当前节点的子节点）
		# 由于 ball 和 gen 是兄弟节点，路径应该是 "../OceanGenerator"
		var relative_path = ball.get_path_to(gen)
		ball.set_ocean_node(relative_path)
		ball.set_buoyancy_force(20.0)
		ball.set_water_drag(1.0)
		
		print("Created Physics Buoyancy Ball")
	else:
		printerr("BuoyancyProbe3D class not found")

	# 4. Create Local SWE Ocean (Visual Test)
	var local_sim = _setup_local_ocean_test()
	local_ocean_sim = local_sim  # 修复：使用重命名后的变量
	
	# 5. Create Orbiting Spectator (Target for Snapping)
	var spectator = Node3D.new()
	spectator.name = "Spectator"
	add_child(spectator)
	spectator.owner = get_tree().edited_scene_root
	spectator.position = Vector3(100, 5, 0)
	
	# Add a visual marker to the spectator
	var spec_mesh = MeshInstance3D.new()
	spec_mesh.mesh = BoxMesh.new()
	spectator.add_child(spec_mesh)
	
	# Assign to Ocean
	if local_ocean_sim:
		local_ocean_sim.follow_target = spectator
	
	var clipmap = get_node_or_null("OceanLOD")
	if clipmap:
		clipmap.follow_target = spectator
	
	# 6. Setup Camera
	var cam = get_viewport().get_camera_3d()
	if not cam:
		cam = Camera3D.new()
		cam.name = "MainCamera"
		add_child(cam)
		cam.owner = get_tree().edited_scene_root
		cam.current = true # Make it active
		print("Created MainCamera")
		
	if cam:
		# Static Top-Down View
		cam.position = Vector3(100, 45, 0) 
		cam.look_at(Vector3(100, 0, 0), Vector3.FORWARD) # Use Forward as UP for top-down

	# 7. Setup Environment (Sun & Sky)
	if not has_node("Sun"):
		var sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
		sun.owner = get_tree().edited_scene_root
		sun.position = Vector3(100, 50, 0)
		sun.look_at(Vector3(100, 0, 0)) # Look at center
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
		
	print("Created Orbiting Spectator, Camera, and Environment")

@export var lock_camera: bool = false # Renamed conceptual usage to "Use Fixed Top-Down View" if true
@export var camera_distance: float = 15.0
@export var camera_height: float = 8.0
@export var track_target: bool = true

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
				# Trigger Splash at Spectator Position
				local_sim_node.add_interaction_world(spectator.global_position, 5.0, 10.0)
				print("Splash Triggered (Space) at ", spectator.global_position)
				
		elif event.keycode == KEY_C:
			var local_sim_node = get_node_or_null("LocalOceanSim")
			if local_sim_node:
				local_sim_node.debug_color_ripples = not local_sim_node.debug_color_ripples
				# Force update immediately
				local_sim_node._update_snapping() 
				print("Ripple Color Toggled (C): ", local_sim_node.debug_color_ripples)

var time_elapsed = 0.0
func _process(_delta: float):
	# Update visualization grid
	if ocean_generator and not grid_probes.is_empty():
		for probe in grid_probes:
			if is_instance_valid(probe):
				var h = ocean_generator.get_wave_height(probe.position.x, probe.position.z)
				probe.position.y = h
				
	# Animate Physics Ball and Create Wake
	if physics_ball and local_ocean_sim:
		var center = Vector3(100, 5, 0)
		var radius = 15.0
		var ball_speed = 1.3
		var bx = center.x + cos(-time_elapsed * ball_speed + PI) * radius
		var bz = center.z + sin(-time_elapsed * ball_speed + PI) * radius
		physics_ball.position = Vector3(bx, 5, bz)
		
		# Add continuous interaction (Wake/Drag)
		# Using a slightly larger radius and strength for visibility
		local_ocean_sim.add_interaction_world(physics_ball.global_position, 2.0, 5.0)
				
				
	# Orbit Logic
	time_elapsed += _delta
	var spectator = get_node_or_null("Spectator")
	if spectator:
		var center = Vector3(100, 5, 0)
		var radius = 20.0
		var speed = 1.0 
		var x = center.x + cos(time_elapsed * speed) * radius
		var z = center.z + sin(time_elapsed * speed) * radius
		spectator.position = Vector3(x, 5, z)

	# Camera Logic
	var cam = get_viewport().get_camera_3d()
	if cam:
		if lock_camera:
			# Static Top-Down
			cam.position = Vector3(100, 45, 0)
			cam.look_at(Vector3(100, 0, 0), Vector3.FORWARD)
		elif track_target and physics_ball:
			# Chase Logic
			var target_pos = physics_ball.position
			# Offset camera behind/above. 
			# Simple approach: Keep same relative direction or just fixed offset
			# Let's do a fixed offset relative to world for stability, but follow position
			var offset = Vector3(0, camera_height, camera_distance)
			
			# Smooth follow?
			var desired_pos = target_pos + offset
			cam.position = cam.position.lerp(desired_pos, _delta * 5.0)
			cam.look_at(target_pos)

func _setup_local_ocean_test() -> Node3D:
	print("Setting up Hybrid Ocean Simulation...")
	
	# Load Scripts
	var local_ocean_script = load("res://Development/TechResearch/OceanVisuals/GpuLocalOcean.gd")
	var global_ocean_script = load("res://Development/TechResearch/OceanVisuals/GpuOcean.gd")
	var clipmap_script = load("res://Development/TechResearch/OceanVisuals/OceanClipmap.gd")
	
	if not local_ocean_script or not global_ocean_script:
		printerr("Scripts not found")
		return null

	# Load Shaders
	var swe_shader = load("res://Development/TechResearch/OceanVisuals/swe_ocean.glsl")
	var fft_shader = load("res://Development/TechResearch/OceanVisuals/Shaders/fft_ocean.glsl")
	var water_shader = load("res://Development/TechResearch/OceanVisuals/Shaders/water_lowpoly.gdshader") # Blended Shader
	
	if not swe_shader or not fft_shader or not water_shader:
		printerr("Shaders not found")
		return null
	
	# Create Shared Material
	var water_mat = ShaderMaterial.new()
	water_mat.shader = water_shader
	# Set some defaults
	water_mat.set_shader_parameter("albedo", Color(0.0, 0.4, 0.8))
	water_mat.set_shader_parameter("roughness", 0.2)

	# 1. Create Global Ocean (FFT)
	var global_ocean = Node3D.new()
	global_ocean.set_script(global_ocean_script)
	global_ocean.name = "GlobalOceanSim"
	global_ocean.compute_shader = fft_shader
	global_ocean.texture_size = 256
	global_ocean.material_to_update = water_mat # Will set 'displacement_map'
	
	add_child(global_ocean)
	global_ocean.owner = get_tree().edited_scene_root
	global_ocean._init_compute()

	# 2. Create Local Ocean (SWE)
	var local_ocean = Node3D.new()
	local_ocean.set_script(local_ocean_script)
	local_ocean.name = "LocalOceanSim"
	local_ocean.compute_shader = swe_shader
	local_ocean.texture_size = 256
	local_ocean.grid_size = 64.0
	local_ocean.material_to_update = water_mat # Will set 'swe_simulation_map' & 'swe_area'
	
	add_child(local_ocean)
	local_ocean.owner = get_tree().edited_scene_root
	local_ocean.position = Vector3(100, 0, 0)
	
	# 3. Create Clipmap LOD System (Infinite Ocean Mesh)
	var clipmap = Node3D.new()
	if clipmap_script:
		clipmap.set_script(clipmap_script)
		clipmap.name = "OceanLOD"
		clipmap.clipmap_levels = 5 # 64, 128, 256, 512, 1024 meters
		clipmap.base_grid_size = 64
		clipmap.base_subdivisions = 64
		
		add_child(clipmap) # Add to root
		clipmap.owner = get_tree().edited_scene_root
		
		# Setup
		clipmap.set_material(water_mat)
		# Will assign follow target below
		
	# 3. Create Clipmap LOD System (Infinite Ocean Mesh)
	# ... (Clipmap setup code remains above)
		
	local_ocean._init_compute()
	
	print("Created Hybrid Ocean Test with Blended Shader")
	return local_ocean
