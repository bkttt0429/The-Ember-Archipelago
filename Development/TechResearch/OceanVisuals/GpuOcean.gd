@tool
extends Node3D

@export var compute_shader: RDShaderFile
@export var material_to_update: ShaderMaterial
@export var texture_size: int = 256
@export var wind_speed: float = 10.0
@export var choppiness: float = 1.0

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID
var uniform_set_horizontal: RID
var uniform_set_vertical: RID
var texture_rid: RID
var h0_texture_rid: RID
var ping_pong_texture_rid: RID
var params_buffer_rid: RID

var time: float = 0.0

func _ready():
	if not compute_shader:
		return
		
	_init_compute()

func _init_compute():
	# Use Global RD to allow sharing texture with materials
	rd = RenderingServer.get_rendering_device()
	if not rd:
		return

	# 1. Load Shader
	var shader_spirv: RDShaderSPIRV = compute_shader.get_spirv()
	shader_rid = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader_rid)
	
	# 2. Create Output Texture (Image2D)
	var tf: RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	texture_rid = rd.texture_create(tf, RDTextureView.new(), [])
	
	# 2.1 Create Initial Spectrum Texture (H0) - Input
	var h0_data = _generate_test_spectrum_data(texture_size)
	# RDTextureFormat doesn't support duplicate(). Manually copy.
	var tf_input = RDTextureFormat.new()
	tf_input.format = tf.format
	tf_input.texture_type = tf.texture_type
	tf_input.width = tf.width
	tf_input.height = tf.height
	tf_input.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	h0_texture_rid = rd.texture_create(tf_input, RDTextureView.new(), [h0_data])

	# 3. Create Uniform Set
	# Binding 0: OceanParams (Uniform Buffer)
	var params_bytes = _get_params_bytes()
	params_buffer_rid = rd.uniform_buffer_create(params_bytes.size(), params_bytes)
	
	var params_uniform = RDUniform.new()
	params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	params_uniform.binding = 0
	params_uniform.add_id(params_buffer_rid)
	
	# Binding 1: Displacement Map (Image) - Output
	var texture_uniform = RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 1
	texture_uniform.add_id(texture_rid)
	
	# Binding 2: H0 Spectrum (Image) - Input for First Pass
	var h0_uniform = RDUniform.new()
	h0_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	h0_uniform.binding = 2
	h0_uniform.add_id(h0_texture_rid)
	
	# 2.2 Create Ping-Pong Texture (Intermediate)
	var tf_inter = RDTextureFormat.new()
	tf_inter.format = tf.format
	tf_inter.texture_type = tf.texture_type
	tf_inter.width = tf.width
	tf_inter.height = tf.height
	tf_inter.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	ping_pong_texture_rid = rd.texture_create(tf_inter, RDTextureView.new(), [])
	
	# Uniform Set 1: Horizontal Pass (Read H0, Write PingPong)
	# Binding 0: Params
	# Binding 1: Output -> PingPong
	# Binding 2: Input -> H0
	
	var u_ping_pong_out = RDUniform.new()
	u_ping_pong_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_ping_pong_out.binding = 1
	u_ping_pong_out.add_id(ping_pong_texture_rid)
	
	uniform_set_horizontal = rd.uniform_set_create([params_uniform, u_ping_pong_out, h0_uniform], shader_rid, 0)
	
	# Uniform Set 2: Vertical Pass (Read PingPong, Write Displacement)
	# Binding 0: Params
	# Binding 1: Output -> Displacement
	# Binding 2: Input -> PingPong
	
	var u_ping_pong_in = RDUniform.new()
	u_ping_pong_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_ping_pong_in.binding = 2
	u_ping_pong_in.add_id(ping_pong_texture_rid)
	
	var u_displacement_out = RDUniform.new()
	u_displacement_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_displacement_out.binding = 1
	u_displacement_out.add_id(texture_rid)
	
	uniform_set_vertical = rd.uniform_set_create([params_uniform, u_displacement_out, u_ping_pong_in], shader_rid, 0)
	
	# 4. Bind to Material
	if material_to_update:
		var tex_obj = Texture2DRD.new()
		tex_obj.texture_rd_rid = texture_rid
		material_to_update.set_shader_parameter("displacement_map", tex_obj)

func _generate_test_spectrum_data(size: int) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(size * size * 16) # 4 floats (16 bytes) per pixel
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = data
	
	for z in range(size):
		for x in range(size):
			# Mirror C++ logic: get_test_h0
			var real_kx = x if x <= int(size / 2.0) else x - size
			var real_kz = z if z <= int(size / 2.0) else z - size
			
			var re = 0.0
			var im = 0.0
			
			if real_kx == 1 and real_kz == 1:
				re = 100.0 # Standard Scale
				im = 0.0
			elif real_kx == 2 and real_kz == 0:
				re = 50.0
				im = 50.0
				
			buffer.put_float(re) # R
			buffer.put_float(im) # G
			buffer.put_float(0.0) # B
			buffer.put_float(0.0) # A
			
	return buffer.data_array

func _process(delta):
	if not rd or not shader_rid.is_valid():
		return
		
	time += delta
	
	# Update Params Buffer
	var params_bytes = _get_params_bytes()
	rd.buffer_update(params_buffer_rid, 0, params_bytes.size(), params_bytes)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Pass 1: Horizontal
	# Push Constant: Pass Mode (0 = Horizontal)
	var push_constant_hor = PackedInt32Array([0, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push_constant_hor, push_constant_hor.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_horizontal, 0)
	# Dispatch: 1 Group per Row. Y groups = texture_size
	rd.compute_list_dispatch(compute_list, 1, texture_size, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 2: Vertical
	# Push Constant: Pass Mode (1 = Vertical)
	var push_constant_ver = PackedInt32Array([1, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push_constant_ver, push_constant_ver.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_vertical, 0)
	# Dispatch: 1 Group per Column. Y groups = texture_size (Wait, standard logic is 1 per row/col)
	# Visualizing Transpose or direct addressing?
	# Usually easier to conceptually dispatch "texture_size" groups.
	rd.compute_list_dispatch(compute_list, 1, texture_size, 1)
	
	rd.compute_list_end()
	# Global RD submits automatically
	# rd.submit()

func _get_params_bytes() -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.resize(32) # Align to 16/32 bytes standard std140
	
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = bytes
	
	buffer.put_float(time)           # 0
	buffer.put_float(choppiness)     # 4
	buffer.put_float(wind_speed)     # 8
	buffer.put_float(0.0)            # 12 (wind_dir placeholder)
	buffer.put_32(texture_size)      # 16
	# Padding remaining...
	
	return buffer.data_array

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if texture_rid.is_valid(): rd.free_rid(texture_rid)
			if h0_texture_rid.is_valid(): rd.free_rid(h0_texture_rid)
			if shader_rid.is_valid(): rd.free_rid(shader_rid)
			# Do not free Global RD!
			# rd.free()
