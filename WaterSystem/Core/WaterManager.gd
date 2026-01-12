@tool
class_name WaterSystemManager
extends Node3D

## WaterManager - Modular Interactive Water System
## Manages GPU-based SWE simulation and provides height queries for buoyancy.
## Objects to be detected as obstacles should be in the "WaterObstacles" group.

@export_group("Simulation Grid")
@export var grid_res: int = 128:
	set(v):
		grid_res = v
		_request_restart()
@export var sea_size: Vector2 = Vector2(80.0, 80.0):
	set(v):
		sea_size = v
		if has_node("WaterPlane"): $WaterPlane.mesh.size = sea_size
@export var propagation_speed: float = 20.0 # Reduced from 200 for stability
@export var damping: float = 0.93 # Reduced from 0.96 for faster decay
 
@export_group("Physical Interaction")
@export var interact_strength: float = 5.0 # Reduced from 25.0 to prevent wide whiteout
@export var interact_radius: float = 0.5 # Increased radius for smoother waves
@export var swe_strength: float = 1.0

@export_group("Wind & Wave Properties")
@export var wind_strength: float = 1.0: set = _set_shader_param
@export var wind_direction: Vector2 = Vector2(1.0, 0.5): set = _set_shader_param
@export var wave_steepness: float = 0.25: set = _set_shader_param
@export var wave_length: float = 20.0: set = _set_shader_param
@export var wave_chaos: float = 0.8: set = _set_shader_param

@export_group("Visual Style")
@export var color_deep: Color = Color(0.05, 0.15, 0.3)
@export var color_shallow: Color = Color(0.2, 0.6, 0.8)
@export var color_foam: Color = Color(1.0, 1.0, 1.0)
@export var foam_noise_tex: NoiseTexture2D

@export_subgroup("Reflections & PBR")
@export var metallic: float = 0.0: set = _set_shader_param
@export var roughness: float = 0.05: set = _set_shader_param
@export var specular: float = 0.5: set = _set_shader_param
@export var fresnel_strength: float = 1.0: set = _set_shader_param

@export_subgroup("Foam Settings")
@export var foam_shore_spread: float = 0.5: set = _set_shader_param
@export var foam_shore_strength: float = 1.0: set = _set_shader_param
@export var foam_crest_spread: float = 0.2: set = _set_shader_param
@export var foam_crest_strength: float = 0.8: set = _set_shader_param
@export var foam_wake_strength: float = 1.5: set = _set_shader_param
@export var foam_jacobian_bias: float = 0.3: set = _set_shader_param

@export_subgroup("Caustics")
@export var caustics_texture: Texture2D
@export var caustics_strength: float = 1.0: set = _set_shader_param
@export var caustics_scale: float = 0.5: set = _set_shader_param
@export var caustics_speed: float = 0.1: set = _set_shader_param

@export_subgroup("Detail Normals")
@export var normal_map1: Texture2D = preload("res://WaterSystem/VFX/textures/n_noise_1.tres")
@export var normal_map2: Texture2D = preload("res://WaterSystem/VFX/textures/n_noise_2.tres")
@export var normal_scale: float = 0.5: set = _set_shader_param
@export var normal_speed: float = 0.1: set = _set_shader_param
@export var normal_tile: float = 20.0: set = _set_shader_param
@export var debug_show_markers: bool = false: set = _set_shader_param

# Internal State
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sim_texture: RID
var interaction_buffer: RID
var uniform_set: RID

const MAX_INTERACTIONS = 64


var sim_image: Image
var visual_texture: ImageTexture
var has_submitted: bool = false

# External Interactions (List of dictionaries: {uv, strength, radius})
var interaction_points: Array = []

const SOLVER_PATH = "res://WaterSystem/Core/Shaders/WaterSolver.glsl"
const SURFACE_SHADER_PATH = "res://WaterSystem/Core/Shaders/WaterSurface.gdshader"

func _set_shader_param(_v):
	# Delay update to next frame to avoid setter recursion issues
	call_deferred("_update_shader_parameters")

func _request_restart():
	if is_inside_tree():
		_cleanup()
		_setup_simulation()
		_bake_obstacles()
		_setup_visuals()

func _ready():
	add_to_group("WaterSystem_Managers")
	_cleanup()
	_setup_simulation()
	
	# Wait for objects in "WaterObstacles" group to be ready
	await get_tree().process_frame
	_bake_obstacles()
	_setup_visuals()
	
	_init_foam_noise()
	_init_caustics_noise()
	_init_default_normals()
	
	# 等待所有噪聲紋理生成完成，防止 Shader 採樣空數據
	if foam_noise_tex: await foam_noise_tex.changed
	if caustics_texture and caustics_texture is NoiseTexture2D: await caustics_texture.changed
	if normal_map1 and normal_map1 is NoiseTexture2D: await normal_map1.changed
	if normal_map2 and normal_map2 is NoiseTexture2D: await normal_map2.changed
	
	_update_shader_parameters()

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
	sim_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(sim_texture)
	
	# Create Interaction Buffer
	var buffer_size = MAX_INTERACTIONS * 16 # 16 bytes per interaction (vec4)
	interaction_buffer = rd.storage_buffer_create(buffer_size)
	
	var uniform_interact = RDUniform.new()
	uniform_interact.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_interact.binding = 1
	uniform_interact.add_id(interaction_buffer)
	
	uniform_set = rd.uniform_set_create([uniform, uniform_interact], shader_rid, 0)
	
	sim_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAF)
	sim_image.fill(Color(0, 0, 0, 1))
	visual_texture = ImageTexture.create_from_image(sim_image)
	rd.texture_update(sim_texture, 0, sim_image.get_data())

func _bake_obstacles():
	var space_state = get_world_3d().direct_space_state
	var obstacles_hit = 0
	
	# Clear previous obstacle flags
	for y in range(grid_res):
		for x in range(grid_res):
			var col = sim_image.get_pixel(x, y)
			col.b = 0.0
			sim_image.set_pixel(x, y, col)
	
	# Raycast baking
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
					col.b = 1.0 # Obstacle
					sim_image.set_pixel(x, y, col)
					obstacles_hit += 1
	
	rd.texture_update(sim_texture, 0, sim_image.get_data())
	visual_texture.update(sim_image)
	print("[WaterManager] Obstacles baked: ", obstacles_hit)

func _setup_visuals():
	var mesh_inst = get_node_or_null("WaterPlane")
	if not mesh_inst:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "WaterPlane"
		var mesh = PlaneMesh.new()
		mesh.size = sea_size
		mesh.subdivide_depth = grid_res / 2.0
		mesh.subdivide_width = grid_res / 2.0
		mesh_inst.mesh = mesh
		add_child(mesh_inst)
		
	var mat = mesh_inst.get_surface_override_material(0)
	if not mat or not mat is ShaderMaterial:
		mat = ShaderMaterial.new()
		mat.shader = load(SURFACE_SHADER_PATH)
		mesh_inst.set_surface_override_material(0, mat)

func _update_shader_parameters():
	var mesh_inst = get_node_or_null("WaterPlane")
	if not mesh_inst: return
	var mat = mesh_inst.get_surface_override_material(0)
	if not mat: return
	
	mat.set_shader_parameter("swe_texture", visual_texture)
	mat.set_shader_parameter("sea_size", sea_size)
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
	if not rd: return
	
	if has_submitted:
		rd.sync ()
		has_submitted = false
		var data = rd.texture_get_data(sim_texture, 0)
		if not data.is_empty():
			sim_image.set_data(grid_res, grid_res, false, Image.FORMAT_RGBAF, data)
			visual_texture.update(sim_image)
	
	_handle_input()
	_run_compute(delta)
	interaction_points.clear() # Clear for next frame

func trigger_ripple(world_pos: Vector3, strength: float = 1.0, radius: float = 0.05):
	var lp = to_local(world_pos)
	var uv = (Vector2(lp.x, lp.z) / sea_size) + Vector2(0.5, 0.5)
	# Fix: Convert world radius to UV space radius (assuming square sea or using X)
	var uv_radius = radius / max(sea_size.x, 1.0)
	
	# Fix: Ensure radius covers at least 2 pixels to avoid sampling misses
	var min_radius = 2.0 / float(grid_res)
	uv_radius = max(uv_radius, min_radius)
	
	interaction_points.append({"uv": uv, "strength": strength, "radius": uv_radius})

func _handle_input():
	# 避免與相機捕獲模式衝突
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# print_rich("[color=yellow]Mouse captured, skipping water input[/color]")
		return

	var vp = get_viewport()
	var cam = vp.get_camera_3d() if vp else null
	if not cam: return
	
	var mpos = vp.get_mouse_position()
	var from = cam.project_ray_origin(mpos)
	var dir = cam.project_ray_normal(mpos)
	
	# Create plane at water height
	var plane = Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(from, dir)
	
	if hit:
		var lp = to_local(hit)
		var uv = (Vector2(lp.x, lp.z) / sea_size) + Vector2(0.5, 0.5)
		
		# Debug click
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			print("Water Hit at: ", hit, " UV: ", uv)
			trigger_ripple(hit, interact_strength, interact_radius)

	if Input.is_key_pressed(KEY_R):
		_request_restart()


func _run_compute(dt):
	var interact_count = min(interaction_points.size(), MAX_INTERACTIONS)
	
	if interact_count > 0:
		var buffer_data = PackedByteArray()
		buffer_data.resize(MAX_INTERACTIONS * 16)
		# Use StreamPeerBuffer for safety, or direct PackedFloat32Array
		var floats = PackedFloat32Array()
		floats.resize(MAX_INTERACTIONS * 4)
		
		# Fill buffer
		for i in range(interact_count):
			var p = interaction_points[i]
			var idx = i * 4
			floats[idx + 0] = p.uv.x
			floats[idx + 1] = p.uv.y
			floats[idx + 2] = p.strength
			floats[idx + 3] = p.radius
			
		var data_bytes = floats.to_byte_array()
		rd.buffer_update(interaction_buffer, 0, data_bytes.size(), data_bytes)
	
	var safe_dt = min(dt, 0.02) # Stricter clamp to ensure stability with higher speeds
	var pc = StreamPeerBuffer.new()
	pc.put_float(safe_dt)
	pc.put_float(damping)
	pc.put_float(propagation_speed)
	pc.put_32(interact_count)
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, grid_res / 8.0, grid_res / 8.0, 1)
	rd.compute_list_end()
	rd.submit()
	has_submitted = true

# Height Queries
func get_water_height_at(world_pos: Vector3) -> float:
	var lp = to_local(world_pos)
	var uv = (Vector2(lp.x, lp.z) / sea_size) + Vector2(0.5, 0.5)
	
	var swe_h = 0.0
	if sim_image:
		var px = clamp(int(uv.x * grid_res), 0, grid_res - 1)
		var py = clamp(int(uv.y * grid_res), 0, grid_res - 1)
		swe_h = sim_image.get_pixel(px, py).r
	
	# CPU Wave Logic (Must match WaterWaves.gdshaderinc)
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
		wave_h += _calc_gerstner_h(pos_xz, t, d, w_len, w_steep, w_speed)
	
	# Noise
	var noise = sin(pos_xz.x * 2.0 + t) * cos(pos_xz.y * 2.0 - t * 0.5) * 0.2
	wave_h += noise * wind_strength * wave_chaos
	
	return global_position.y + swe_h * swe_strength + wave_h

func _calc_gerstner_h(pos: Vector2, t: float, d: Vector2, l: float, s: float, speed: float) -> float:
	var k = 2.0 * PI / l
	var c = sqrt(9.81 / k) * speed
	var f = k * (d.dot(pos) - c * t)
	return (s / k) * sin(f)

func _cleanup():
	if rd:
		if has_submitted: rd.sync()
		if uniform_set.is_valid(): rd.free_rid(uniform_set)
		if pipeline_rid.is_valid(): rd.free_rid(pipeline_rid)
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		if sim_texture.is_valid(): rd.free_rid(sim_texture)
		if interaction_buffer.is_valid(): rd.free_rid(interaction_buffer)
		rd.free()
		rd = null
	uniform_set = RID(); pipeline_rid = RID(); shader_rid = RID(); sim_texture = RID(); interaction_buffer = RID()

func _notification(what):
	if what == NOTIFICATION_PREDELETE: _cleanup()
