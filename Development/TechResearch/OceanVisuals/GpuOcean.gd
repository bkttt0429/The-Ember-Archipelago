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
var uniform_set_update: RID
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
	
	# 3. Create Uniform Sets for the 3-Pass Sequence
	# Pass 0 (Update): H0 -> Texture
	# Pass 1 (Horiz): Texture -> PingPong
	# Pass 2 (Vert): PingPong -> Texture
	
	# -- Uniforms for Texture --
	var u_texture_out = RDUniform.new()
	u_texture_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_texture_out.binding = 1
	u_texture_out.add_id(texture_rid)
	
	var u_texture_in = RDUniform.new()
	u_texture_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_texture_in.binding = 2
	u_texture_in.add_id(texture_rid)
	
	# -- Uniforms for PingPong --
	var u_pingpong_out = RDUniform.new()
	u_pingpong_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_pingpong_out.binding = 1
	u_pingpong_out.add_id(ping_pong_texture_rid)
	
	var u_pingpong_in = RDUniform.new()
	u_pingpong_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_pingpong_in.binding = 2
	u_pingpong_in.add_id(ping_pong_texture_rid)

	# -- Assign Uniform Sets --
	# US_Update: Output=Texture, Input=H0
	uniform_set_update = rd.uniform_set_create([params_uniform, u_texture_out, h0_uniform], shader_rid, 0)
	
	# US_Horizontal: Output=PingPong, Input=Texture
	uniform_set_horizontal = rd.uniform_set_create([params_uniform, u_pingpong_out, u_texture_in], shader_rid, 0)
	
	# US_Vertical: Output=Texture, Input=PingPong (Final height in Texture/displacement_map)
	uniform_set_vertical = rd.uniform_set_create([params_uniform, u_texture_out, u_pingpong_in], shader_rid, 0)
	
	# 4. Bind to Material
	if material_to_update:
		var tex_obj = Texture2DRD.new()
		tex_obj.texture_rd_rid = texture_rid
		material_to_update.set_shader_parameter("displacement_map", tex_obj)
		# Set texture_scale to match FFT texture's world space scale
		# FFT texture covers 64x64 world units (matching OceanWaveGenerator's size)
		material_to_update.set_shader_parameter("texture_scale", 64.0)

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
				re = 1000.0 # Standard Scale (Increased for visibility)
				im = 0.0
			elif real_kx == 2 and real_kz == 0:
				re = 500.0
				im = 500.0
				
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
	
	# Pass 0: Update Spectrum (Texture size x texture size)
	var push_constant_upd = PackedInt32Array([0, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push_constant_upd, push_constant_upd.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_update, 0)
	rd.compute_list_dispatch(compute_list, 1, texture_size, 1) # Full 2D update
	
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 1: Horizontal
	var push_constant_hor = PackedInt32Array([1, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push_constant_hor, push_constant_hor.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_horizontal, 0)
	rd.compute_list_dispatch(compute_list, 1, texture_size, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 2: Vertical
	var push_constant_ver = PackedInt32Array([2, 0, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(compute_list, push_constant_ver, push_constant_ver.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_vertical, 0)
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
