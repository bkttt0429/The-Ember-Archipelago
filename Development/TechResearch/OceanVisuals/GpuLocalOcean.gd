@tool
extends Node3D
class_name GpuLocalOcean

@export var compute_shader: RDShaderFile
@export var material_to_update: ShaderMaterial:
	set(v):
		material_to_update = v
		if is_inside_tree() and material_to_update and texture_0_rid.is_valid():
			if not _swe_tex_obj:
				_swe_tex_obj = Texture2DRD.new()
			_swe_tex_obj.texture_rd_rid = texture_0_rid
			material_to_update.set_shader_parameter("swe_simulation_map", _swe_tex_obj)
@export var grid_size: float = 64.0
@export var texture_size: int = 256
@export var drag: float = 0.98
@export var gravity: float = 9.8
@export var sub_steps: int = 8

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

var texture_0_rid: RID
var texture_1_rid: RID
var params_buffer_rid: RID

var uniform_set_pass1: RID
var uniform_set_pass2: RID
var interactions_buffer_rid: RID

var _swe_tex_obj: Texture2DRD # Cached texture object for material
var pending_interactions: Array[Dictionary] = [] # {pos: Vector2, radius: float, strength: float, life: float}

var time: float = 0.0

@export var follow_target: Node3D
@export var debug_color_ripples: bool = true

@export_group("Diagnostics")
@export var capture_sim_texture: bool = false:
	set(v):
		if v: _save_texture_to_file()
		capture_sim_texture = false

var last_snapped_pos: Vector3 = Vector3.ZERO
var first_frame: bool = true
var uv_offset: Vector2 = Vector2.ZERO

func _ready():
	if not compute_shader:
		return
	_init_compute()

func _init_compute():
	rd = RenderingServer.get_rendering_device()
	if not rd: return

	# 1. Load Shader
	var shader_spirv: RDShaderSPIRV = compute_shader.get_spirv()
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader_rid)
	
	# 2. Create Textures
	var tf: RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var initial_data = _generate_empty_data(texture_size)
	texture_0_rid = rd.texture_create(tf, RDTextureView.new(), [initial_data])
	texture_1_rid = rd.texture_create(tf, RDTextureView.new(), [initial_data])
	
	# 3. Buffers
	var params_bytes = _get_params_bytes(0.016)
	params_buffer_rid = rd.uniform_buffer_create(params_bytes.size(), params_bytes)
	
	var interactions_bytes = _generate_empty_interactions()
	interactions_buffer_rid = rd.uniform_buffer_create(interactions_bytes.size(), interactions_bytes)
	
	# 4. Uniform Sets
	var sampler_state = RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	var sampler_rid = rd.sampler_create(sampler_state)
	
	# Set 1 (Read T0 -> Write T1)
	var u_params = RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 0
	u_params.add_id(params_buffer_rid)
	
	var u_tex0 = RDUniform.new()
	u_tex0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_tex0.binding = 1
	u_tex0.add_id(sampler_rid)
	u_tex0.add_id(texture_0_rid)
	
	var u_img1 = RDUniform.new()
	u_img1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_img1.binding = 2
	u_img1.add_id(texture_1_rid)
	
	var u_int = RDUniform.new()
	u_int.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_int.binding = 3
	u_int.add_id(interactions_buffer_rid)
	
	uniform_set_pass1 = rd.uniform_set_create([u_params, u_tex0, u_img1, u_int], shader_rid, 0)
	
	# Set 2 (Read T1 -> Write T0)
	var u_tex1 = RDUniform.new()
	u_tex1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_tex1.binding = 1
	u_tex1.add_id(sampler_rid)
	u_tex1.add_id(texture_1_rid)
	
	var u_img0 = RDUniform.new()
	u_img0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_img0.binding = 2
	u_img0.add_id(texture_0_rid)
	
	uniform_set_pass2 = rd.uniform_set_create([u_params, u_tex1, u_img0, u_int], shader_rid, 0)

	# Trigger parameter update to current material
	material_to_update = material_to_update


func _process(delta):
	if not rd: return
	time += delta
	_update_snapping()
	
	# Update active interactions life
	var living_interactions: Array[Dictionary] = []
	for item in pending_interactions:
		item.life -= delta
		if item.life > 0:
			living_interactions.append(item)
	pending_interactions = living_interactions
	
	# Update Params
	var total_dt = min(delta, 1.0 / 30.0)
	var sub_dt = total_dt / float(sub_steps)
	var params_bytes = _get_params_bytes(sub_dt)
	rd.buffer_update(params_buffer_rid, 0, params_bytes.size(), params_bytes)
	
	# Update Interaction Buffer
	var int_bytes = _get_interactions_bytes()
	rd.buffer_update(interactions_buffer_rid, 0, int_bytes.size(), int_bytes)
	
	if Engine.get_frames_drawn() % 120 == 0:
		print("GpuLocalOcean: Sim Running. Interactions: ", pending_interactions.size(), " SubSteps: ", sub_steps)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	var groups = texture_size / 8
	for i in range(sub_steps):
		var apply_shift = 1 if i == 0 else 0
		# Pass 1: Vel
		rd.compute_list_set_push_constant(compute_list, PackedInt32Array([0, apply_shift, 0, 0]).to_byte_array(), 16)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_pass1, 0)
		rd.compute_list_dispatch(compute_list, groups, groups, 1)
		rd.compute_list_add_barrier(compute_list)
		
		# Pass 2: Height
		rd.compute_list_set_push_constant(compute_list, PackedInt32Array([1, 0, 0, 0]).to_byte_array(), 16)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set_pass2, 0)
		rd.compute_list_dispatch(compute_list, groups, groups, 1)
		rd.compute_list_add_barrier(compute_list)
	
	rd.compute_list_end()

func _update_snapping():
	var target_pos = Vector3.ZERO
	if follow_target:
		target_pos = follow_target.global_position
	else:
		var cam = get_viewport().get_camera_3d()
		if cam: target_pos = cam.global_position
		
	var snap_size = grid_size / float(texture_size)
	var snapped_x = round(target_pos.x / snap_size) * snap_size
	var snapped_z = round(target_pos.z / snap_size) * snap_size
	var current_snapped_pos = Vector3(snapped_x, target_pos.y, snapped_z)
	
	if first_frame:
		last_snapped_pos = current_snapped_pos
		first_frame = false
	
	global_position = current_snapped_pos
	var delta_pos = current_snapped_pos - last_snapped_pos
	uv_offset = Vector2(delta_pos.x / grid_size, delta_pos.z / grid_size)
	last_snapped_pos = current_snapped_pos

	if material_to_update:
		var min_pos = current_snapped_pos - Vector3(grid_size, 0, grid_size) * 0.5
		var area_vec = Vector4(min_pos.x, min_pos.z, grid_size, grid_size)
		material_to_update.set_shader_parameter("swe_area", area_vec)
		material_to_update.set_shader_parameter("swe_color_strength", 3.0 if debug_color_ripples else 0.0)

func add_interaction_world(pos: Vector3, radius: float, strength: float):
	var local_3d = pos - global_position
	pending_interactions.append({
		"pos": Vector2(local_3d.x, local_3d.z),
		"radius": radius,
		"strength": strength,
		"life": 0.5 # Apply force for 0.5 seconds
	})

func _get_params_bytes(dt: float) -> PackedByteArray:
	var buffer = StreamPeerBuffer.new()
	buffer.put_float(dt); buffer.put_float(grid_size); buffer.put_float(drag); buffer.put_float(gravity)
	buffer.put_32(texture_size); buffer.put_32(texture_size)
	buffer.put_32(0) # IMPORTANT: PAD for vec2 uv_offset alignment (8 bytes)
	buffer.put_float(uv_offset.x); buffer.put_float(uv_offset.y)
	return buffer.data_array

func _generate_empty_interactions() -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(272); return bytes

func _get_interactions_bytes() -> PackedByteArray:
	var buffer = StreamPeerBuffer.new()
	var count = min(pending_interactions.size(), 16)
	buffer.put_32(count); buffer.put_32(0); buffer.put_32(0); buffer.put_32(0)
	for i in range(16):
		if i < count:
			var it = pending_interactions[i]
			buffer.put_float(it.pos.x); buffer.put_float(it.pos.y); buffer.put_float(it.radius); buffer.put_float(it.strength)
		else:
			for j in range(4): buffer.put_float(0.0)
	return buffer.data_array

func _generate_empty_data(size: int) -> PackedByteArray:
	var data = PackedByteArray(); data.resize(size * size * 16); return data

func _save_texture_to_file():
	if not rd: return
	var data = rd.texture_get_data(texture_0_rid, 0)
	var img = Image.create_from_data(texture_size, texture_size, false, Image.FORMAT_RGBAF, data)
	img.save_png("user://swe_debug.png")
	print("SWE Debug Texture saved to user://swe_debug.png")

func _notification(what):
	if what == NOTIFICATION_PREDELETE and rd:
		for rid in [texture_0_rid, texture_1_rid, params_buffer_rid, interactions_buffer_rid, shader_rid]:
			if rid.is_valid(): rd.free_rid(rid)
