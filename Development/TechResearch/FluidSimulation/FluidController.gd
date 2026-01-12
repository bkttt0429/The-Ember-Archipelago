@tool
extends Node3D

# FLIP Fluid Controller - Cleaned Version
# Manages RenderingDevice, Buffers, and Compute Dispatch

@export var particle_count: int = 15000
@export var grid_res: Vector3i = Vector3i(32, 32, 32)
@export var box_size: Vector3 = Vector3(8.0, 8.0, 8.0)

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

var particle_buffer: RID
var grid_buffer: RID
var pressure_buffer_rid: RID
var divergence_buffer_rid: RID
var orig_grid_buffer_rid: RID

var uniform_set: RID

var multimesh_instance: MultiMeshInstance3D

@export_enum("Rain", "Collision") var scenario: int = 0
@export var interact_radius: float = 1.5
@export var interact_strength: float = 15.0

var interaction_pos: Vector3 = Vector3.ZERO
var is_interacting: bool = false

var initialization_status: bool = false

func _ready():
	_setup_compute()
	_setup_visualization()

func _setup_compute():
	if rd:
		_cleanup_rd()
		
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		printerr("FATAL: Failed to create RenderingDevice")
		return
	
	# Load Shader
	var shader_file_access = FileAccess.open("res://Development/TechResearch/FluidSimulation/Shaders/flip_fluid.glsl", FileAccess.READ)
	if not shader_file_access:
		printerr("FATAL: Could not find shader file")
		return
		
	var shader_code = shader_file_access.get_as_text()
	shader_code = shader_code.replace("#[compute]", "")
	
	var shader_source = RDShaderSource.new()
	shader_source.source_compute = shader_code
	
	var shader_spirv = rd.shader_compile_spirv_from_source(shader_source)
	if shader_spirv.compile_error_compute != "":
		printerr("Shader Compile Error: ", shader_spirv.compile_error_compute)
		return
		
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	
	# 1. Particle Buffer
	var p_data = PackedFloat32Array()
	p_data.resize(particle_count * 12)
	p_data.fill(0.0)
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	if scenario == 0: # Rain
		for i in range(particle_count):
			var offset = i * 12
			p_data[offset + 0] = rng.randf_range(0.0, box_size.x)
			p_data[offset + 1] = rng.randf_range(box_size.y * 0.5, box_size.y)
			p_data[offset + 2] = rng.randf_range(0.0, box_size.z)
			p_data[offset + 4] = rng.randf_range(-1.0, 1.0)
			p_data[offset + 6] = rng.randf_range(-1.0, 1.0)
			p_data[offset + 8] = 0.2; p_data[offset + 9] = 0.5; p_data[offset + 10] = 1.0; p_data[offset + 11] = 1.0
			
	elif scenario == 1: # Collision
		for i in range(particle_count):
			var offset = i * 12
			var is_left = i < particle_count / 2.0
			if is_left:
				p_data[offset + 0] = rng.randf_range(0.0, box_size.x * 0.3)
				p_data[offset + 4] = 5.0
			else:
				p_data[offset + 0] = rng.randf_range(box_size.x * 0.7, box_size.x)
				p_data[offset + 4] = -5.0
			p_data[offset + 1] = rng.randf_range(0.0, box_size.y * 0.5)
			p_data[offset + 2] = rng.randf_range(0.0, box_size.z)

	var p_bytes = p_data.to_byte_array()
	particle_buffer = rd.storage_buffer_create(p_bytes.size(), p_bytes)
	var grid_cells = grid_res.x * grid_res.y * grid_res.z
	var grid_bytes_size = grid_cells * 4 * 4
	var zero_bytes = PackedByteArray()
	zero_bytes.resize(grid_bytes_size)
	zero_bytes.fill(0)
	
	grid_buffer = rd.storage_buffer_create(grid_bytes_size, zero_bytes)
	
	var p_zero = PackedByteArray(); p_zero.resize(grid_cells * 2 * 4); p_zero.fill(0)
	pressure_buffer_rid = rd.storage_buffer_create(grid_cells * 2 * 4, p_zero)
	
	var d_zero = PackedByteArray(); d_zero.resize(grid_cells * 4); d_zero.fill(0)
	divergence_buffer_rid = rd.storage_buffer_create(grid_cells * 4, d_zero)
	
	orig_grid_buffer_rid = rd.storage_buffer_create(grid_bytes_size, zero_bytes)
	
	var uniform_params = [
		_create_uniform(particle_buffer, 0),
		_create_uniform(grid_buffer, 1),
		_create_uniform(pressure_buffer_rid, 2),
		_create_uniform(divergence_buffer_rid, 3),
		_create_uniform(orig_grid_buffer_rid, 4)
	]
	
	uniform_set = rd.uniform_set_create(uniform_params, shader_rid, 0)
	if uniform_set.is_valid():
		initialization_status = true
		print("Fluid Simulation: GPU Uniforms Initialized Successfully.")
	else:
		printerr("FATAL: Failed to create Uniform Set")

func _create_uniform(buffer_rid: RID, binding: int) -> RDUniform:
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buffer_rid)
	return u

func _setup_visualization():
	if not multimesh_instance:
		multimesh_instance = MultiMeshInstance3D.new()
		add_child(multimesh_instance)
		multimesh_instance.multimesh = MultiMesh.new()
	
	var mm = multimesh_instance.multimesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = particle_count
	
	var mesh = SphereMesh.new()
	mesh.radius = 0.25 # Increased for cohesive surface look
	mesh.height = 0.5
	
	var water_shader = load("res://Development/TechResearch/FluidSimulation/Shaders/fluid_liquid_surface.gdshader")
	var particle_mat = ShaderMaterial.new()
	particle_mat.shader = water_shader
	
	mesh.material = particle_mat
	mm.mesh = mesh
	
	if not get_node_or_null("DebugMarker"):
		var marker = MeshInstance3D.new()
		marker.name = "DebugMarker"
		marker.mesh = SphereMesh.new()
		marker.mesh.radius = 0.5
		marker.mesh.height = 1.0
		var debug_mat = StandardMaterial3D.new()
		debug_mat.albedo_color = Color(1, 0, 0, 0.5)
		debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		marker.mesh.material = debug_mat
		add_child(marker)

func _process(delta):
	if not initialization_status: return
	
	var camera = get_viewport().get_camera_3d()
	var marker = get_node_or_null("DebugMarker")
	if camera:
		var mouse_pos = get_viewport().get_mouse_position()
		var from = camera.project_ray_origin(mouse_pos)
		var to = from + camera.project_ray_normal(mouse_pos) * 100.0
		var global_plane = Plane(Vector3.UP, 0.5)
		var intersect = global_plane.intersects_ray(from, to)
		is_interacting = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if intersect:
			interaction_pos = to_local(intersect)
			if marker:
				marker.visible = true
				marker.global_position = intersect
		else:
			if marker: marker.visible = false
	
	run_simulation(delta)
	update_visuals()

func run_simulation(dt: float):
	var total_dt = min(dt, 0.02)
	var sub_steps = 8 # Doubled sub-steps to handle higher energy (0.95 FLIP)
	var step_dt = total_dt / float(sub_steps)
	for step in range(sub_steps):
		_do_simulation_step(step_dt)

func _do_simulation_step(step_dt: float):
	var push_data = PackedByteArray()
	push_data.resize(96)
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = push_data
	
	var g_res_v = Vector3(grid_res)
	var grav = Vector3(0, -9.8, 0)
	var f_ratio = 0.40 # 40% FLIP / 60% PIC for smooth surface cohesion
	
	var params_list = []
	for mode in range(8):
		buffer.seek(0)
		buffer.put_32(mode)
		buffer.put_float(step_dt)
		buffer.seek(16)
		buffer.put_float(g_res_v.x); buffer.put_float(g_res_v.y); buffer.put_float(g_res_v.z)
		buffer.seek(32)
		buffer.put_float(box_size.x); buffer.put_float(box_size.y); buffer.put_float(box_size.z)
		buffer.seek(48)
		buffer.put_float(grav.x); buffer.put_float(grav.y); buffer.put_float(grav.z)
		buffer.seek(60); buffer.put_float(f_ratio)
		buffer.seek(64)
		buffer.put_float(float(interaction_pos.x)); buffer.put_float(float(interaction_pos.y)); buffer.put_float(float(interaction_pos.z))
		buffer.seek(76); buffer.put_float(float(interact_radius))
		buffer.seek(80); buffer.put_float(float(interact_strength))
		var interact_flag = 1 if is_interacting else 0
		if mode == 5: interact_flag = 0
		buffer.seek(84); buffer.put_32(interact_flag)
		params_list.append(buffer.data_array.duplicate())
		
	var jacobi_ping_params = params_list[5].duplicate()
	var jacobi_pong_params = params_list[5].duplicate()
	var b_ping = StreamPeerBuffer.new(); b_ping.data_array = jacobi_ping_params; b_ping.seek(84); b_ping.put_32(0); jacobi_ping_params = b_ping.data_array
	var b_pong = StreamPeerBuffer.new(); b_pong.data_array = jacobi_pong_params; b_pong.seek(84); b_pong.put_32(1); jacobi_pong_params = b_pong.data_array

	var groups_grid = ceil((grid_res.x * grid_res.y * grid_res.z) / 64.0)
	var groups_p = ceil(particle_count / 64.0)
	var groups_grid_x4 = ceil((grid_res.x * grid_res.y * grid_res.z * 4) / 64.0)
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	
	# 0. Reset (Expects Cell ID)
	rd.compute_list_set_push_constant(cl, params_list[0], params_list[0].size())
	rd.compute_list_dispatch(cl, int(groups_grid), 1, 1)
	rd.compute_list_add_barrier(cl)
	# 1. P2G
	rd.compute_list_set_push_constant(cl, params_list[1], params_list[1].size())
	rd.compute_list_dispatch(cl, int(groups_p), 1, 1)
	rd.compute_list_add_barrier(cl)
	# 7. Copy Grid
	rd.compute_list_set_push_constant(cl, params_list[7], params_list[7].size())
	rd.compute_list_dispatch(cl, int(groups_grid_x4), 1, 1)
	rd.compute_list_add_barrier(cl)
	# 2. Grid Update
	rd.compute_list_set_push_constant(cl, params_list[2], params_list[2].size())
	rd.compute_list_dispatch(cl, int(groups_grid), 1, 1)
	rd.compute_list_add_barrier(cl)
	# 4. Div
	rd.compute_list_set_push_constant(cl, params_list[4], params_list[4].size())
	rd.compute_list_dispatch(cl, int(groups_grid), 1, 1)
	rd.compute_list_add_barrier(cl)
	# 5. Jacobi
	for i in range(120):
		var p = jacobi_ping_params if (i % 2 == 0) else jacobi_pong_params
		rd.compute_list_set_push_constant(cl, p, p.size())
		rd.compute_list_dispatch(cl, int(groups_grid), 1, 1)
		rd.compute_list_add_barrier(cl)
	# 6. Project
	rd.compute_list_set_push_constant(cl, params_list[6], params_list[6].size())
	rd.compute_list_dispatch(cl, int(groups_grid), 1, 1)
	rd.compute_list_add_barrier(cl)
	# 3. G2P
	rd.compute_list_set_push_constant(cl, params_list[3], params_list[3].size())
	rd.compute_list_dispatch(cl, int(groups_p), 1, 1)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync ()

func update_visuals():
	if not particle_buffer.is_valid(): return
	var p_data = rd.buffer_get_data(particle_buffer).to_float32_array()
	var mm = multimesh_instance.multimesh
	for i in range(particle_count):
		var offset = i * 12
		var t = Transform3D()
		t.origin = Vector3(p_data[offset + 0], p_data[offset + 1], p_data[offset + 2])
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(p_data[offset + 8], p_data[offset + 9], p_data[offset + 10], 1.0))

func _cleanup_rd():
	if rd:
		rd.free()
		rd = null
