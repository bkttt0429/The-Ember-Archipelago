@tool
class_name OceanWaterManager
extends Node3D

## WaterManager - Modular Interactive Water System (SWE + Gerstner)
## Manages GPU-based SWE simulation and provides height queries.

@export_group("Simulation Grid")
@export var grid_res: int = 128:
	set(v):
		grid_res = v
		_request_restart()
@export var sea_size: Vector2 = Vector2(80.0, 80.0):
	set(v):
		sea_size = v
		if has_node("WaterPlane"): $WaterPlane.mesh.size = sea_size
		_update_shader_params_deferred()
@export var propagation_speed: float = 20.0
@export var damping: float = 0.90
 
@export_group("Physical Interaction")
@export var interact_strength: float = 50.0
@export var interact_radius: float = 0.5
@export var swe_strength: float = 1.0

@export_group("Environmental Effects")
@export var rain_intensity: float = 0.0:
	set(v): rain_intensity = clamp(v, 0.0, 1.0)

@export_group("Wind & Wave Properties")
@export var wind_strength: float = 1.0:
	set(v): wind_strength = v; _update_shader_params_deferred()
@export var wind_direction: Vector2 = Vector2(1.0, 0.5):
	set(v): wind_direction = v; _update_shader_params_deferred()
@export var wave_steepness: float = 0.25:
	set(v): wave_steepness = v; _update_shader_params_deferred()
@export var wave_length: float = 20.0:
	set(v): wave_length = v; _update_shader_params_deferred()
@export var wave_chaos: float = 0.8:
	set(v): wave_chaos = v; _update_shader_params_deferred()

@export_group("Visual Style")
@export var color_deep: Color = Color(0.004, 0.016, 0.047): # Reference: godot4-oceanfft
	set(v): color_deep = v; _update_shader_params_deferred()
@export var color_shallow: Color = Color(0.0, 0.73, 0.99): # Reference: godot4-oceanfft
	set(v): color_shallow = v; _update_shader_params_deferred()
@export var color_foam: Color = Color(1.0, 1.0, 1.0):
	set(v): color_foam = v; _update_shader_params_deferred()
@export var foam_noise_tex: NoiseTexture2D:
	set(v): foam_noise_tex = v; _update_shader_params_deferred()

@export_subgroup("Reflections & PBR")
@export var metallic: float = 0.0:
	set(v): metallic = v; _update_shader_params_deferred()
@export var roughness: float = 0.05:
	set(v): roughness = v; _update_shader_params_deferred()
@export var specular: float = 0.5:
	set(v): specular = v; _update_shader_params_deferred()
@export var fresnel_strength: float = 1.0:
	set(v): fresnel_strength = v; _update_shader_params_deferred()

@export_subgroup("Foam Settings")
@export var foam_shore_spread: float = 0.5:
	set(v): foam_shore_spread = v; _update_shader_params_deferred()
@export var foam_shore_strength: float = 1.0:
	set(v): foam_shore_strength = v; _update_shader_params_deferred()
@export var foam_crest_spread: float = 0.2:
	set(v): foam_crest_spread = v; _update_shader_params_deferred()
@export var foam_crest_strength: float = 0.8:
	set(v): foam_crest_strength = v; _update_shader_params_deferred()
@export var foam_wake_strength: float = 1.5:
	set(v): foam_wake_strength = v; _update_shader_params_deferred()
@export var foam_jacobian_bias: float = 0.3:
	set(v): foam_jacobian_bias = v; _update_shader_params_deferred()

@export_subgroup("Caustics")
@export var caustics_texture: Texture2D:
	set(v): caustics_texture = v; _update_shader_params_deferred()
@export var caustics_strength: float = 1.0:
	set(v): caustics_strength = v; _update_shader_params_deferred()
@export var caustics_scale: float = 0.5:
	set(v): caustics_scale = v; _update_shader_params_deferred()
@export var caustics_speed: float = 0.1:
	set(v): caustics_speed = v; _update_shader_params_deferred()

@export_subgroup("Detail Normals")
@export var normal_map1: Texture2D:
	set(v): normal_map1 = v; _update_shader_params_deferred()
@export var normal_map2: Texture2D:
	set(v): normal_map2 = v; _update_shader_params_deferred()
@export var normal_scale: float = 0.5:
	set(v): normal_scale = v; _update_shader_params_deferred()
@export var normal_speed: float = 0.1:
	set(v): normal_speed = v; _update_shader_params_deferred()
@export var normal_tile: float = 20.0:
	set(v): normal_tile = v; _update_shader_params_deferred()
@export var debug_show_markers: bool = false:
	set(v): debug_show_markers = v; _update_shader_params_deferred()

@export_group("Debug Tools")
@export var spawn_test_mover: bool = false:
	set(v):
		if v: spawn_debug_test_mover()

enum TestMoveMode {CIRCLE, LINEAR}
@export var test_movement_mode: TestMoveMode = TestMoveMode.LINEAR
@export var test_object_radius: float = 12.0
@export var test_object_speed: float = 2.0

@export_group("Debug Actions")
@export var restart_simulation: bool = false:
	set(v): _request_restart()

# Legacy & Global Compatibility
var _time: float = 0.0
@export var height_scale: float = 1.0
@export_group("Waterspout (Legacy)")
@export var waterspout_pos: Vector3 = Vector3.ZERO
@export var waterspout_radius: float = 1.0
@export var waterspout_strength: float = 1.0
@export var waterspout_spiral_strength: float = 1.0
@export var waterspout_darkness_factor: float = 1.0

# Internal State
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sim_texture_A: RID
var sim_texture_B: RID
var interaction_buffer: RID
var uniform_set_A: RID
var uniform_set_B: RID
var current_sim_idx: int = 0
var has_submitted: bool = false
var sim_image: Image
var visual_texture: ImageTexture

const MAX_INTERACTIONS = 128

# External Interactions (List of dictionaries: {uv, strength, radius})
var interaction_points: Array = []

# Updated Paths for NewStructure
# Updated Paths for NewStructure
const SOLVER_PATH = "res://NewWaterSystem/shaders/compute/water_interaction.glsl"
const SURFACE_SHADER_PATH = "res://NewWaterSystem/shaders/surface/ocean_surface.gdshader"
const VORTEX_SHADER_PATH = "res://NewWaterSystem/shaders/compute/Vortex.glsl"
const WATERSPOUT_SHADER_PATH = "res://NewWaterSystem/shaders/compute/Waterspout.glsl"

# Weather System RIDs
var weather_texture: RID
var weather_image: Image
var weather_visual_tex: ImageTexture
var vortex_shader_rid: RID
var vortex_pipeline_rid: RID
var waterspout_shader_rid: RID
var waterspout_pipeline_rid: RID
var vortex_params_buffer: RID
var waterspout_params_buffer: RID
var weather_uniform_set: RID

# Active Skills State
var active_vortex = null # {position: Vector2, radius: float, intensity: float, speed: float, depth: float}
var active_waterspout = null # {position: Vector2, radius: float, intensity: float, speed: float}

var _is_initialized: bool = false
var active_weather_events = [] # Placeholder for future weather system

func _update_shader_params_deferred():
	if is_inside_tree():
		call_deferred("_update_shader_parameters")

func _request_restart():
	print("[WaterManager] Requesting simulation restart...")
	_cleanup()
	_setup_simulation()
	_bake_obstacles()
	_setup_visuals()
	_update_shader_parameters()
	interaction_points.clear()
	print("[WaterManager] Restart complete.")

func _ready():
	_is_initialized = false
	add_to_group("WaterSystem_Managers")
	_cleanup()
	_setup_simulation()
	
	await get_tree().process_frame
	_bake_obstacles()
	_setup_visuals()
	
	_init_foam_noise()
	_init_caustics_noise()
	_init_default_normals()
	
	if foam_noise_tex: await foam_noise_tex.changed
	if caustics_texture and caustics_texture is NoiseTexture2D: await caustics_texture.changed
	if normal_map1 and normal_map1 is NoiseTexture2D: await normal_map1.changed
	if normal_map2 and normal_map2 is NoiseTexture2D: await normal_map2.changed
	
	_update_shader_parameters()
	_is_initialized = true

func _init_default_normals():
	if not normal_map1:
		var noise1 = FastNoiseLite.new()
		noise1.seed = 12345
		noise1.frequency = 0.05
		var tex1 = NoiseTexture2D.new()
		tex1.width = 512
		tex1.height = 512
		tex1.seamless = true
		tex1.as_normal_map = true
		tex1.noise = noise1
		normal_map1 = tex1

	if not normal_map2:
		var noise2 = FastNoiseLite.new()
		noise2.seed = 67890
		noise2.frequency = 0.08
		var tex2 = NoiseTexture2D.new()
		tex2.width = 512
		tex2.height = 512
		tex2.seamless = true
		tex2.as_normal_map = true
		tex2.noise = noise2
		normal_map2 = tex2

func _init_caustics_noise():
	if not caustics_texture:
		var noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.frequency = 0.05
		
		var tex = NoiseTexture2D.new()
		tex.width = 512
		tex.height = 512
		tex.seamless = true
		tex.as_normal_map = false
		tex.noise = noise
		caustics_texture = tex

func _init_foam_noise():
	if not foam_noise_tex:
		foam_noise_tex = NoiseTexture2D.new()
		foam_noise_tex.width = 256
		foam_noise_tex.height = 256
		foam_noise_tex.seamless = true
		var noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.frequency = 0.05
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		foam_noise_tex.noise = noise

func _setup_simulation():
	rd = RenderingServer.create_local_rendering_device()
	if not rd: return
	
	if not FileAccess.file_exists(SOLVER_PATH):
		print("[WaterManager] Warning: Compute shader not found at ", SOLVER_PATH)
		return
		
	var shader_file = FileAccess.open(SOLVER_PATH, FileAccess.READ)
	if not shader_file: return
	
	var shader_src = RDShaderSource.new()
	shader_src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, shader_file.get_as_text())
	var shader_spirv = rd.shader_compile_spirv_from_source(shader_src)
	if shader_spirv.compile_error_compute != "":
		push_error("[WaterManager] Shader Compile Error: " + shader_spirv.compile_error_compute)
		return
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
	sim_texture_A = rd.texture_create(fmt, RDTextureView.new(), [data])
	sim_texture_B = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	var buffer_size = MAX_INTERACTIONS * 16
	interaction_buffer = rd.storage_buffer_create(buffer_size)

	var u_in_A = RDUniform.new()
	u_in_A.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_in_A.binding = 0
	u_in_A.add_id(sim_texture_A)
	
	var u_out_B = RDUniform.new()
	u_out_B.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out_B.binding = 1
	u_out_B.add_id(sim_texture_B)
	
	var u_buffer = RDUniform.new()
	u_buffer.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_buffer.binding = 2
	u_buffer.add_id(interaction_buffer)
	
	uniform_set_A = rd.uniform_set_create([u_in_A, u_out_B, u_buffer], shader_rid, 0)
	
	var u_in_B = RDUniform.new()
	u_in_B.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_in_B.binding = 0
	u_in_B.add_id(sim_texture_B)
	
	var u_out_A = RDUniform.new()
	u_out_A.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out_A.binding = 1
	u_out_A.add_id(sim_texture_A)
	
	uniform_set_B = rd.uniform_set_create([u_in_B, u_out_A, u_buffer], shader_rid, 0)
	
	sim_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAF)
	sim_image.fill(Color(0, 0, 0, 1))
	visual_texture = ImageTexture.create_from_image(sim_image)
	rd.texture_update(sim_texture_A, 0, sim_image.get_data())
	rd.texture_update(sim_texture_B, 0, sim_image.get_data())

func _bake_obstacles():
	var space_state = get_world_3d().direct_space_state
	var obstacles_hit = 0
	
	for y in range(grid_res):
		for x in range(grid_res):
			var col = sim_image.get_pixel(x, y)
			col.b = 0.0
			sim_image.set_pixel(x, y, col)
	
	for y in range(grid_res):
		for x in range(grid_res):
			var uv = Vector2(x, y) / float(grid_res)
			var local_pos = Vector3((uv.x - 0.5) * sea_size.x, 100.0, (uv.y - 0.5) * sea_size.y)
			var world_pos = to_global(local_pos)
			
			var query = PhysicsRayQueryParameters3D.create(world_pos, world_pos + Vector3.DOWN * 200.0)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			
			var result = space_state.intersect_ray(query)
			if result:
				if result.position.y > global_position.y - 2.0:
					var col = sim_image.get_pixel(x, y)
					col.b = 1.0
					sim_image.set_pixel(x, y, col)
					obstacles_hit += 1
	
	if rd:
		rd.texture_update(sim_texture_A, 0, sim_image.get_data())
		rd.texture_update(sim_texture_B, 0, sim_image.get_data())
	visual_texture.update(sim_image)
	
	_setup_weather_pipeline()
	
	print("[WaterManager] Obstacles baked: ", obstacles_hit)

func _setup_weather_pipeline():
	if not rd: return
	
	# 1. Weather Influence Texture (RGBA16F)
	var fmt = RDTextureFormat.new()
	fmt.width = grid_res
	fmt.height = grid_res
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var data = PackedByteArray()
	data.resize(grid_res * grid_res * 8) # 2 bytes per channel * 4 channels
	data.fill(0)
	weather_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	weather_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAH)
	weather_visual_tex = ImageTexture.create_from_image(weather_image)
	
	# 2. Compile Vortex Shader
	if FileAccess.file_exists(VORTEX_SHADER_PATH):
		vortex_shader_rid = _load_compute_shader(VORTEX_SHADER_PATH)
		if vortex_shader_rid.is_valid():
			vortex_pipeline_rid = rd.compute_pipeline_create(vortex_shader_rid)
			vortex_params_buffer = rd.storage_buffer_create(64) # Buffer for VortexParams
			
	# 3. Compile Waterspout Shader
	if FileAccess.file_exists(WATERSPOUT_SHADER_PATH):
		waterspout_shader_rid = _load_compute_shader(WATERSPOUT_SHADER_PATH)
		if waterspout_shader_rid.is_valid():
			waterspout_pipeline_rid = rd.compute_pipeline_create(waterspout_shader_rid)
			waterspout_params_buffer = rd.storage_buffer_create(64) # Buffer for WaterspoutParams

func _load_compute_shader(path: String) -> RID:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f: return RID()
	var src = RDShaderSource.new()
	src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, f.get_as_text())
	var spirv = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("[WaterManager] Shader Error (%s): %s" % [path, spirv.compile_error_compute])
		return RID()
	return rd.shader_create_from_spirv(spirv)

func _setup_visuals():
	var mesh_inst = get_node_or_null("WaterPlane")
	if not mesh_inst:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "WaterPlane"
		var mesh = PlaneMesh.new()
		mesh.size = sea_size
		mesh.subdivide_depth = grid_res * 2 - 1
		mesh.subdivide_width = grid_res * 2 - 1
		mesh_inst.mesh = mesh
		add_child(mesh_inst)
		
	var mat = mesh_inst.get_surface_override_material(0)
	if not mat or not mat is ShaderMaterial:
		mat = ShaderMaterial.new()
		if FileAccess.file_exists(SURFACE_SHADER_PATH):
			mat.shader = load(SURFACE_SHADER_PATH)
		else:
			print("[WaterManager] Warning: Surface shader not found at ", SURFACE_SHADER_PATH)
		mesh_inst.set_surface_override_material(0, mat)

func _update_shader_parameters():
	var mesh_inst = get_node_or_null("WaterPlane")
	if not mesh_inst: return
	var mat = mesh_inst.get_surface_override_material(0)
	if not mat: return
	
	mat.set_shader_parameter("swe_texture", visual_texture)
	mat.set_shader_parameter("weather_influence", weather_visual_tex)
	mat.set_shader_parameter("sea_size", sea_size)
	mat.set_shader_parameter("manager_world_pos", global_position)
	
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("wind_dir", wind_direction)
	mat.set_shader_parameter("wave_steepness", wave_steepness)
	mat.set_shader_parameter("wave_length", wave_length)
	mat.set_shader_parameter("wave_chaos", wave_chaos)
	mat.set_shader_parameter("swe_strength", swe_strength)
	mat.set_shader_parameter("debug_show_markers", debug_show_markers)
	mat.set_shader_parameter("color_deep", color_deep)
	mat.set_shader_parameter("color_shallow", color_shallow)
	mat.set_shader_parameter("color_foam", color_foam)
	mat.set_shader_parameter("foam_noise", foam_noise_tex)
	
	mat.set_shader_parameter("metallic", metallic)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("specular", specular)
	mat.set_shader_parameter("fresnel_strength", fresnel_strength)
	
	mat.set_shader_parameter("foam_shore_spread", foam_shore_spread)
	mat.set_shader_parameter("foam_shore_strength", foam_shore_strength)
	mat.set_shader_parameter("foam_crest_spread", foam_crest_spread)
	mat.set_shader_parameter("foam_crest_strength", foam_crest_strength)
	mat.set_shader_parameter("foam_wake_strength", foam_wake_strength)
	mat.set_shader_parameter("foam_jacobian_bias", foam_jacobian_bias)
	
	mat.set_shader_parameter("caustics_texture", caustics_texture)
	mat.set_shader_parameter("caustics_strength", caustics_strength)
	mat.set_shader_parameter("caustics_scale", caustics_scale)
	mat.set_shader_parameter("caustics_speed", caustics_speed)
	
	mat.set_shader_parameter("normal_map1", normal_map1)
	mat.set_shader_parameter("normal_map2", normal_map2)
	mat.set_shader_parameter("normal_scale", normal_scale)
	mat.set_shader_parameter("normal_speed", normal_speed)
	mat.set_shader_parameter("normal_tile", normal_tile)

func _process(delta):
	if not rd or not _is_initialized: return
	
	_time = Time.get_ticks_msec() / 1000.0
	
	var plane = get_node_or_null("WaterPlane")
	if plane:
		var mat = plane.get_surface_override_material(0)
		if mat:
			mat.set_shader_parameter("manager_world_pos", global_position)
	
	if has_submitted:
		rd.sync ()
		has_submitted = false
		
		# Update SWE Texture
		var result_texture = sim_texture_A if current_sim_idx == 0 else sim_texture_B
		var data = rd.texture_get_data(result_texture, 0)
		if not data.is_empty():
			sim_image.set_data(grid_res, grid_res, false, Image.FORMAT_RGBAF, data)
			visual_texture.update(sim_image)
			
		# Update Weather Texture (Visual only for foam/color modulation)
		var w_data = rd.texture_get_data(weather_texture, 0)
		if not w_data.is_empty():
			weather_image.set_data(grid_res, grid_res, false, Image.FORMAT_RGBAH, w_data)
			weather_visual_tex.update(weather_image)
	
	var sim_delta = min(delta, 0.033)
	_run_compute(sim_delta)
	interaction_points.clear()

func trigger_ripple(world_pos: Vector3, strength: float = 1.0, radius: float = 0.05):
	var lp = to_local(world_pos)
	var uv = (Vector2(lp.x, lp.z) / sea_size) + Vector2(0.5, 0.5)
	var uv_radius = radius / max(sea_size.x, 1.0)
	var min_radius = 2.0 / float(grid_res)
	uv_radius = max(uv_radius, min_radius)
	interaction_points.append({"uv": uv, "strength": strength, "radius": uv_radius})

func trigger_vortex(world_pos: Vector3, radius: float = 10.0, intensity: float = 1.0, speed: float = 2.0, depth: float = 5.0):
	var lp = to_local(world_pos)
	active_vortex = {
		"position": Vector2(lp.x, lp.z),
		"radius": radius,
		"intensity": intensity,
		"speed": speed,
		"depth": depth
	}

func trigger_waterspout(world_pos: Vector3, radius: float = 8.0, intensity: float = 1.0, speed: float = 5.0):
	var lp = to_local(world_pos)
	active_waterspout = {
		"position": Vector2(lp.x, lp.z),
		"radius": radius,
		"intensity": intensity,
		"speed": speed
	}

func clear_skills():
	active_vortex = null
	active_waterspout = null
	# Reset weather texture
	if rd and weather_texture.is_valid():
		var data = PackedByteArray()
		data.resize(grid_res * grid_res * 8)
		data.fill(0)
		rd.texture_update(weather_texture, 0, data)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var vp = get_viewport()
		var cam = vp.get_camera_3d() if vp else null
		if not cam: return
		
		var mpos = event.position
		var from = cam.project_ray_origin(mpos)
		var dir = cam.project_ray_normal(mpos)
		
		var plane = Plane(Vector3.UP, global_position.y)
		var hit = plane.intersects_ray(from, dir)
		
		if hit:
			trigger_ripple(hit, interact_strength, interact_radius)

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_request_restart()

func _run_compute(dt):
	# 1. SWE Solver (Standard Interactions & Rain)
	var interact_count = min(interaction_points.size(), MAX_INTERACTIONS)
	if interact_count > 0:
		var floats = PackedFloat32Array()
		floats.resize(MAX_INTERACTIONS * 4)
		for i in range(interact_count):
			var p = interaction_points[i]
			var idx = i * 4
			floats[idx + 0] = p.uv.x
			floats[idx + 1] = p.uv.y
			floats[idx + 2] = p.strength
			floats[idx + 3] = p.radius
		var data_bytes = floats.to_byte_array()
		rd.buffer_update(interaction_buffer, 0, data_bytes.size(), data_bytes)
	
	var safe_dt = min(dt, 0.02)
	var pc = StreamPeerBuffer.new()
	pc.put_float(safe_dt)
	pc.put_float(damping)
	pc.put_float(propagation_speed)
	pc.put_32(interact_count)
	pc.put_float(rain_intensity)
	pc.put_float(_time)
	pc.put_float(sea_size.x)
	pc.put_float(sea_size.y)
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	var active_set = uniform_set_A if current_sim_idx == 0 else uniform_set_B
	rd.compute_list_bind_uniform_set(cl, active_set, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()
	
	# 2. Specialized Skills (Vortex/Waterspout)
	var current_swe = sim_texture_B if current_sim_idx == 0 else sim_texture_A # The one just written by SWE
	
	if active_vortex:
		_dispatch_vortex(current_swe)
	
	if active_waterspout:
		_dispatch_waterspout(current_swe)
		
	rd.submit()
	has_submitted = true
	current_sim_idx = 1 - current_sim_idx

func _dispatch_vortex(swe_tex: RID):
	if not vortex_pipeline_rid.is_valid(): return
	
	# Update Params
	var params = PackedFloat32Array([
		active_vortex.position.x, active_vortex.position.y,
		active_vortex.radius, active_vortex.intensity,
		active_vortex.speed, active_vortex.depth,
		_time, sea_size.x
	])
	rd.buffer_update(vortex_params_buffer, 0, params.size() * 4, params.to_byte_array())
	
	var u_swe = RDUniform.new()
	u_swe.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_swe.binding = 0
	u_swe.add_id(swe_tex)
	
	var u_weather = RDUniform.new()
	u_weather.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_weather.binding = 1
	u_weather.add_id(weather_texture)
	
	var u_params = RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_params.binding = 2
	u_params.add_id(vortex_params_buffer)
	
	var uniform_set = rd.uniform_set_create([u_swe, u_weather, u_params], vortex_shader_rid, 0)
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, vortex_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()
	# Note: Uniform set will be freed by Godot's internal tracking if not stored, 
	# but for compute it's better to keep it or free it properly.
	# rd.free_rid(set) # Can't free immediately if submitted

func _dispatch_waterspout(swe_tex: RID):
	if not waterspout_pipeline_rid.is_valid(): return
	
	# Update Params
	var params = PackedFloat32Array([
		active_waterspout.position.x, active_waterspout.position.y,
		active_waterspout.radius, active_waterspout.intensity,
		active_waterspout.speed, _time,
		sea_size.x, 0.0 # Padding
	])
	rd.buffer_update(waterspout_params_buffer, 0, params.size() * 4, params.to_byte_array())
	
	var u_swe = RDUniform.new()
	u_swe.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_swe.binding = 0
	u_swe.add_id(swe_tex)
	
	var u_weather = RDUniform.new()
	u_weather.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_weather.binding = 1
	u_weather.add_id(weather_texture)
	
	var u_params = RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_params.binding = 2
	u_params.add_id(waterspout_params_buffer)
	
	var uniform_set = rd.uniform_set_create([u_swe, u_weather, u_params], waterspout_shader_rid, 0)
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, waterspout_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()

func spawn_debug_test_mover():
	# Placeholder for debug spawning if needed, stripped of old implementation
	pass

func get_wave_height_at(world_pos: Vector3) -> float:
	var lp = to_local(world_pos)
	var uv = (Vector2(lp.x, lp.z) / sea_size) + Vector2(0.5, 0.5)
	
	var swe_h = 0.0
	if sim_image:
		var px = clamp(int(uv.x * grid_res), 0, grid_res - 1)
		var py = clamp(int(uv.y * grid_res), 0, grid_res - 1)
		swe_h = sim_image.get_pixel(px, py).r
	
	var t = Time.get_ticks_msec() / 1000.0
	var pos_xz = Vector2(lp.x, lp.z)
	var base_angle = atan2(wind_direction.y, wind_direction.x)
	
	var wave_h = 0.0
	var wave_scales = [1.0, 1.3, 0.6, 0.3, 2.1, 0.8, 0.45, 1.7]
	var steep_scales = [1.0, 0.7, 0.9, 1.2, 0.4, 0.8, 1.0, 0.3]
	var speeds = [1.0, 0.8, 1.5, 2.1, 0.6, 1.3, 1.9, 0.5]
	var angles = [0.0, 1.1, 2.4, -0.6, 4.3, -1.2, 5.2, 0.7]

	for i in range(8):
		var w_len = wave_length * wave_scales[i]
		var w_steep = (wave_steepness * steep_scales[i]) * wind_strength
		var w_speed = speeds[i]
		var w_angle = base_angle + angles[i] * wave_chaos
		
		var d = Vector2(cos(w_angle), sin(w_angle))
		var k = 2.0 * PI / w_len
		var c = sqrt(9.81 / k) * w_speed
		var f = k * (d.dot(pos_xz) - c * t)
		wave_h += (w_steep / k) * sin(f)
	
	var noise = sin(pos_xz.x * 2.0 + t) * cos(pos_xz.y * 2.0 - t * 0.5) * 0.2
	wave_h += noise * wind_strength * wave_chaos
	
	return global_position.y + swe_h * swe_strength + wave_h

func _cleanup():
	if rd:
		if has_submitted:
			rd.sync ()
		if uniform_set_A.is_valid(): rd.free_rid(uniform_set_A)
		if uniform_set_B.is_valid(): rd.free_rid(uniform_set_B)
		if pipeline_rid.is_valid(): rd.free_rid(pipeline_rid)
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		if vortex_pipeline_rid.is_valid(): rd.free_rid(vortex_pipeline_rid)
		if vortex_shader_rid.is_valid(): rd.free_rid(vortex_shader_rid)
		if waterspout_pipeline_rid.is_valid(): rd.free_rid(waterspout_pipeline_rid)
		if waterspout_shader_rid.is_valid(): rd.free_rid(waterspout_shader_rid)
		if sim_texture_A.is_valid(): rd.free_rid(sim_texture_A)
		if sim_texture_B.is_valid(): rd.free_rid(sim_texture_B)
		if weather_texture.is_valid(): rd.free_rid(weather_texture)
		if vortex_params_buffer.is_valid(): rd.free_rid(vortex_params_buffer)
		if waterspout_params_buffer.is_valid(): rd.free_rid(waterspout_params_buffer)
		if interaction_buffer.is_valid(): rd.free_rid(interaction_buffer)
		rd.free()
		rd = null
	
	has_submitted = false
	current_sim_idx = 0
	uniform_set_A = RID(); uniform_set_B = RID(); pipeline_rid = RID(); shader_rid = RID()
	vortex_shader_rid = RID(); vortex_pipeline_rid = RID()
	waterspout_shader_rid = RID(); waterspout_pipeline_rid = RID()
	sim_texture_A = RID(); sim_texture_B = RID(); weather_texture = RID()
	vortex_params_buffer = RID(); waterspout_params_buffer = RID()
	interaction_buffer = RID()

func _notification(what):
	if what == NOTIFICATION_PREDELETE: _cleanup()