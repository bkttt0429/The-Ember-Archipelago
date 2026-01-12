@tool
extends Node3D

# SeaController - Interactive Sea Surface with Buoyancy & Wind
# Optimized for stability and cross-device rendering compatibility.

@export_group("Simulation Settings")
@export var grid_res: int = 128:
	set(v):
		grid_res = v
		if is_inside_tree():
			_cleanup()
			_setup_simulation()
@export var sea_size: Vector2 = Vector2(40.0, 40.0):
	set(v):
		sea_size = v
		if has_node("SeaPlane"): $SeaPlane.mesh.size = sea_size
@export var propagation_speed: float = 200.0
@export var damping: float = 0.98

@export_group("Visuals")
@export var foam_noise_tex: NoiseTexture2D
@export var absorb_dist: float = 2.0

@export_group("Wind & Waves")
@export var wind_strength: float = 1.0:
	set(v):
		wind_strength = v
		_update_shader_parameters()
@export var wind_direction: Vector2 = Vector2(1.0, 0.5):
	set(v):
		wind_direction = v
		_update_shader_parameters()
@export var wave_steepness: float = 0.2:
	set(v):
		wave_steepness = v
		_update_shader_parameters()
@export var wave_length: float = 10.0:
	set(v):
		wave_length = v
		_update_shader_parameters()
@export var wave_chaos: float = 0.5:
	set(v):
		wave_chaos = v
		_update_shader_parameters()
@export var swe_strength: float = 2.0:
	set(v):
		swe_strength = v
		_update_shader_parameters()
@export var debug_show_markers: bool = false:
	set(v):
		debug_show_markers = v
		_update_shader_parameters()

@export_group("Interaction")
@export var interact_strength: float = 5.0
@export var interact_radius: float = 0.05

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sim_texture: RID
var uniform_set: RID

var sim_image: Image
var visual_texture: ImageTexture
var has_submitted: bool = false

var is_interacting: bool = false
var interaction_uv: Vector2 = Vector2.ZERO

func _ready():
	_cleanup()
	_setup_simulation()
	
	# Auto-generate collision for Seabed_Slope if it lacks it (Fix for Raycast Baking)
	var seabed = get_node_or_null("../Seabed_Slope")
	if seabed and seabed is MeshInstance3D:
		if seabed.get_child_count() == 0:
			print("SeaController: Generating trimesh collision for Seabed_Slope")
			seabed.create_trimesh_collision()
	
	await get_tree().process_frame # Wait for physics to be ready
	_bake_obstacles()
	
	_setup_visuals()
	
	# Initialize Foam Noise if not provided in inspector
	if not foam_noise_tex:
		foam_noise_tex = NoiseTexture2D.new()
		foam_noise_tex.width = 256
		foam_noise_tex.height = 256
		foam_noise_tex.seamless = true
		var noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.frequency = 0.02
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		foam_noise_tex.noise = noise
	
	if has_node("SeaPlane"):
		var mat = $SeaPlane.get_surface_override_material(0)
		if mat:
			mat.set_shader_parameter("foam_noise", foam_noise_tex)

func _setup_simulation():
	rd = RenderingServer.create_local_rendering_device()
	if not rd: return
	
	var shader_file = FileAccess.open("res://Development/TechResearch/FluidSimulation/Shaders/sea_swe_solver.glsl", FileAccess.READ)
	if not shader_file: return
	
	var shader_src = RDShaderSource.new()
	shader_src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, shader_file.get_as_text())
	var shader_spirv = rd.shader_compile_spirv_from_source(shader_src)
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	
	var fmt = RDTextureFormat.new()
	fmt.width = grid_res
	fmt.height = grid_res
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var data = PackedByteArray()
	data.resize(grid_res * grid_res * 16)
	data.fill(0)
	sim_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(sim_texture)
	uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)
	
	# Initialize Images
	sim_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAF)
	sim_image.fill(Color(0, 0, 0, 1)) # Clear all channels
	visual_texture = ImageTexture.create_from_image(sim_image)
	
	# Initial clear of texture
	var initial_bytes = sim_image.get_data()
	rd.texture_update(sim_texture, 0, initial_bytes)

func _bake_obstacles():
	# Raycast from sky to detect land
	var space_state = get_world_3d().direct_space_state
	var pixel_size = sea_size / float(grid_res)
	var obstacles_hit = 0
	
	# We write to the Blue channel of sim_image (R=Height, G=Vel, B=Obstacle, A=1)
	for y in range(grid_res):
		for x in range(grid_res):
			var uv = Vector2(x, y) / float(grid_res)
			var local_x = (uv.x - 0.5) * sea_size.x
			var local_z = (uv.y - 0.5) * sea_size.y
			var world_pos = to_global(Vector3(local_x, 100.0, local_z)) # Cast from high up
			
			var query = PhysicsRayQueryParameters3D.create(world_pos, world_pos + Vector3.DOWN * 200.0)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			
			var result = space_state.intersect_ray(query)
			if result:
				# Only block waves if land is close to surface or above (avoid marking deep seabed)
				if result.position.y > global_position.y - 2.0:
					# Mark as obstacle
					var col = sim_image.get_pixel(x, y)
					col.b = 1.0 # Obstacle Flag
					sim_image.set_pixel(x, y, col)
					obstacles_hit += 1
	
	print("SeaController: Baked obstacles. Hit count: ", obstacles_hit)
	
	# Upload initial state with obstacles to GPU
	var bytes = sim_image.get_data()
	rd.texture_update(sim_texture, 0, bytes)
	visual_texture.update(sim_image)

func _setup_visuals():
	if has_node("SeaPlane"):
		$SeaPlane.mesh.size = sea_size
		_update_shader_parameters()
		return
		
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "SeaPlane"
	var mesh = PlaneMesh.new()
	mesh.size = sea_size
	mesh.subdivide_depth = 64
	mesh.subdivide_width = 64
	mesh_instance.mesh = mesh
	
	var mat = ShaderMaterial.new()
	mat.shader = load("res://Development/TechResearch/FluidSimulation/Shaders/sea_surface.gdshader")
	mesh_instance.set_surface_override_material(0, mat)
	add_child(mesh_instance)

func _update_shader_parameters():
	if not has_node("SeaPlane"): return
	var mat = $SeaPlane.get_surface_override_material(0)
	if mat:
		mat.set_shader_parameter("swe_texture", visual_texture)
		mat.set_shader_parameter("sea_size", sea_size)
		mat.set_shader_parameter("wind_strength", wind_strength)
		mat.set_shader_parameter("wind_dir", wind_direction)
		mat.set_shader_parameter("wave_steepness", wave_steepness)
		mat.set_shader_parameter("wave_length", wave_length)
		mat.set_shader_parameter("wave_chaos", wave_chaos)
		mat.set_shader_parameter("swe_strength", swe_strength)
		mat.set_shader_parameter("debug_show_markers", debug_show_markers)
		# foam_noise is now set once in _ready

func _process(delta):
	if not rd or not pipeline_rid.is_valid():
		return
	
	# 1. Sync & Readback
	if has_submitted:
		rd.sync ()
		has_submitted = false
		
		# Transfer GPU data to CPU and Visual Texture
		var bytes = rd.texture_get_data(sim_texture, 0)
		if not bytes.is_empty():
			if not sim_image:
				sim_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAF)
			sim_image.set_data(grid_res, grid_res, false, Image.FORMAT_RGBAF, bytes)
			
			if not visual_texture:
				visual_texture = ImageTexture.create_from_image(sim_image)
			else:
				visual_texture.update(sim_image)
			
			if has_node("SeaPlane"):
				var mat = $SeaPlane.get_surface_override_material(0)
				if mat:
					mat.set_shader_parameter("visual_texture", visual_texture)
		
	# 2. Handle Input
	_handle_input()
	
	# 3. New Compute Dispatch
	_run_compute(delta)
	
	# 4. Update Uniforms (Redundant if set() works, but safe for editor)
	_update_shader_parameters()

func _handle_input():
	var viewport = get_viewport()
	if not viewport: return
	var camera = viewport.get_camera_3d()
	if not camera: return
	
	var mouse_pos = viewport.get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var plane = Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(from, from + dir * 200.0)
	
	if hit:
		var local_hit = to_local(hit)
		interaction_uv = (Vector2(local_hit.x, local_hit.z) / sea_size) + Vector2(0.5, 0.5)
		is_interacting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	else:
		is_interacting = false

func _run_compute(dt):
	if not rd or not pipeline_rid.is_valid(): return
	
	var pc = StreamPeerBuffer.new()
	pc.put_float(dt)
	pc.put_float(damping)
	pc.put_float(propagation_speed)
	pc.put_32(1 if is_interacting else 0)
	pc.put_float(interaction_uv.x)
	pc.put_float(interaction_uv.y)
	pc.put_float(interact_strength)
	pc.put_float(interact_radius)
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()
	rd.submit()
	has_submitted = true

# Public API for Buoyancy (Read from sim_image updated in _process)
func get_water_height_at(global_pos: Vector3) -> float:
	var local_pos = to_local(global_pos)
	var uv = (Vector2(local_pos.x, local_pos.z) / sea_size) + Vector2(0.5, 0.5)
	
	var swe_h = 0.0
	if sim_image:
		var px = clamp(int(uv.x * grid_res), 0, grid_res - 1)
		var py = clamp(int(uv.y * grid_res), 0, grid_res - 1)
		swe_h = sim_image.get_pixel(px, py).r
	
	# Match GPU Chaotic Wave Logic (8 Layers)
	var t = Time.get_ticks_msec() / 1000.0
	var pos_xz = Vector2(local_pos.x, local_pos.z)
	var base_angle = atan2(wind_direction.y, wind_direction.x)
	
	var wave_h = 0.0
	var wave_data = [
		[wave_length, wave_steepness, 1.0, 0.0],
		[wave_length * 0.7, wave_steepness * 0.8, 1.2, 1.2],
		[wave_length * 0.4, wave_steepness * 0.6, 1.8, 2.5],
		[wave_length * 1.5, wave_steepness * 0.4, 0.9, -0.5],
		[wave_length * 0.2, wave_steepness * 0.3, 2.5, 4.1],
		[wave_length * 2.5, wave_steepness * 0.2, 0.7, 0.8],
		[wave_length * 0.5, wave_steepness * 0.5, 1.5, -1.8],
		[wave_length * 0.1, wave_steepness * 0.2, 3.2, 3.1]
	]

	for i in range(8):
		var w_len = wave_data[i][0]
		var w_steep = wave_data[i][1] * wind_strength
		var w_speed = wave_data[i][2]
		var w_angle = base_angle + wave_data[i][3] * wave_chaos
		
		var d = Vector2(cos(w_angle), sin(w_angle))
		wave_h += _calculate_gerstner_h(pos_xz, t, d, w_len, w_steep, w_speed)
	
	# Extra Micro-Chaos Noise (Match GPU)
	var noise = sin(pos_xz.x * 2.0 + t) * cos(pos_xz.y * 2.0 - t * 0.5) * 0.2
	wave_h += noise * wind_strength * wave_chaos
	
	return global_position.y + swe_h * swe_strength + wave_h

func _calculate_gerstner_h(pos: Vector2, time: float, dir: Vector2, length: float, steepness: float, speed: float) -> float:
	var k = 2.0 * PI / length
	var c = sqrt(9.81 / k) * speed
	var d = dir.normalized()
	var f = k * (d.dot(pos) - c * time)
	var a = steepness / k
	return a * sin(f)

func _cleanup():
	if rd:
		if has_submitted:
			rd.sync ()
			has_submitted = false
		if uniform_set.is_valid(): rd.free_rid(uniform_set)
		if pipeline_rid.is_valid(): rd.free_rid(pipeline_rid)
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		if sim_texture.is_valid(): rd.free_rid(sim_texture)
		rd.free()
		rd = null
	
	uniform_set = RID()
	pipeline_rid = RID()
	shader_rid = RID()
	sim_texture = RID()

func _notification(what):
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_cleanup()
