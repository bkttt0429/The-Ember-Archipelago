@tool
extends Node3D
class_name GpuLocalOcean

@export var compute_shader: RDShaderFile
@export var material_to_update: ShaderMaterial
@export var grid_size: float = 64.0
@export var texture_size: int = 256
@export var drag: float = 0.99
@export var gravity: float = 9.8

var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID

var texture_0_rid: RID
var texture_1_rid: RID
var params_buffer_rid: RID

var uniform_set_pass1: RID
var uniform_set_pass2: RID
var interactions_buffer_rid: RID

var pending_interactions: Array[Dictionary] = [] # {pos: Vector2, radius: float, strength: float}

var time: float = 0.0

func _ready():
	if not compute_shader:
		return
		
	# In editor, we might not want to run full sim always, 
	# but for debugging it's useful.
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
	
	# 2. Create Textures (Double Buffering)
	var tf: RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	# Initial Data (Zeroed)
	var initial_data = _generate_empty_data(texture_size)
	
	texture_0_rid = rd.texture_create(tf, RDTextureView.new(), [initial_data])
	texture_1_rid = rd.texture_create(tf, RDTextureView.new(), [initial_data])
	
	# 3. Create Uniform Buffer (Params)
	var params_bytes = _get_params_bytes(0.016)
	params_buffer_rid = rd.uniform_buffer_create(params_bytes.size(), params_bytes)
	
	var u_params = RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 0
	u_params.add_id(params_buffer_rid)
	
	# 3.b Create Interactions Buffer
	# Size: 16 + 256 bytes = 272 bytes
	var interactions_bytes = _generate_empty_interactions()
	interactions_buffer_rid = rd.uniform_buffer_create(interactions_bytes.size(), interactions_bytes)
	
	var u_interactions = RDUniform.new()
	u_interactions.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_interactions.binding = 3
	u_interactions.add_id(interactions_buffer_rid)
	
	# 4. Create Uniform Sets for Ping-Pong
	# Set 1: Read T0 -> Write T1 (Advection)
	var u_tex_input_0 = RDUniform.new()
	u_tex_input_0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE # Wait, shader uses simple sampler2D?
	# In Godot RD, sampler2D usually needs a Sampler state + Texture.
	# But `uniform_set_create` with UNIFORM_TYPE_SAMPLER_WITH_TEXTURE takes a sampler and a texture?
	# Actually, simpler to separate Sampler and Texture if shader allows, or use UNIFORM_TYPE_SAMPLER_WITH_TEXTURE.
	# Let's check shader: layout(set = 0, binding = 1) uniform sampler2D prev_state;
	# This implies Combined Image Sampler.
	
	var sampler_state = RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var sampler_rid = rd.sampler_create(sampler_state)
	
	var u_input_t0 = RDUniform.new()
	u_input_t0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_input_t0.binding = 1
	u_input_t0.add_id(sampler_rid)
	u_input_t0.add_id(texture_0_rid)
	
	var u_output_t1 = RDUniform.new()
	u_output_t1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output_t1.binding = 2
	u_output_t1.add_id(texture_1_rid)
	
	uniform_set_pass1 = rd.uniform_set_create([u_params, u_input_t0, u_output_t1, u_interactions], shader_rid, 0)
	
	# Set 2: Read T1 -> Write T0 (Update)
	var u_input_t1 = RDUniform.new()
	u_input_t1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_input_t1.binding = 1
	u_input_t1.add_id(sampler_rid)
	u_input_t1.add_id(texture_1_rid)
	
	var u_output_t0 = RDUniform.new()
	u_output_t0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_output_t0.binding = 2
	u_output_t0.add_id(texture_0_rid)
	
	uniform_set_pass2 = rd.uniform_set_create([u_params, u_input_t1, u_output_t0, u_interactions], shader_rid, 0)
	
	# 5. Bind Output to Material
	if material_to_update:
		var tex_obj = Texture2DRD.new()
		tex_obj.texture_rd_rid = texture_0_rid
		material_to_update.set_shader_parameter("swe_simulation_map", tex_obj)

@export var follow_target: Node3D
@export var debug_color_ripples: bool = false


var last_snapped_pos: Vector3 = Vector3.ZERO
var uv_offset: Vector2 = Vector2.ZERO

func _process(delta):
	if not rd or not shader_rid.is_valid():
		return
		
	time += delta
	
	# Pixel Snapping Logic
	_update_snapping()
	
	# Update Params
	var params_bytes = _get_params_bytes(delta)
	rd.buffer_update(params_buffer_rid, 0, params_bytes.size(), params_bytes)
	
	# Update Interactions
	if not pending_interactions.is_empty():
		var int_bytes = _get_interactions_bytes()
		rd.buffer_update(interactions_buffer_rid, 0, int_bytes.size(), int_bytes)
		pending_interactions.clear()
	else:
		# Maybe clear interactions if persistent? 
		# If shader processes them every frame, we need to clear them.
		# But buffer_update partial? 
		# We should just upload "count=0" if no interactions.
		# Note: The shader reads 'count'. So we MUST reset count to 0.
		var empty_bytes = PackedByteArray()
		empty_bytes.resize(4) # Just int count = 0
		empty_bytes.encode_s32(0, 0)
		rd.buffer_update(interactions_buffer_rid, 0, 4, empty_bytes)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Grid Groups
	var x_groups = int(texture_size / 8)
	var y_groups = int(texture_size / 8)
	
	# Pass 1: Advection (Read T0 -> Write T1)
	var push_advect = PackedInt32Array([0, 0, 0, 0]).to_byte_array() # Mode 0
	rd.compute_list_set_push_constant(compute_list, push_advect, push_advect.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_pass1, 0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 2: Update (Read T1 -> Write T0)
	var push_update = PackedInt32Array([1, 0, 0, 0]).to_byte_array() # Mode 1
	rd.compute_list_set_push_constant(compute_list, push_update, push_update.size())
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_pass2, 0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	rd.compute_list_end()
	# Global RD submits automatically. Manual submit/sync is for local RD only.

func _update_snapping():
	var target_pos = Vector3.ZERO
	if follow_target:
		target_pos = follow_target.global_position
		
	var snap_size = grid_size / float(texture_size)
	
	# Snap X and Z
	var snapped_x = round(target_pos.x / snap_size) * snap_size
	var snapped_z = round(target_pos.z / snap_size) * snap_size
	
	var current_snapped_pos = Vector3(snapped_x, target_pos.y, snapped_z) # Keep Y (height)
	
	# Move the grid mesh to follow
	global_position = current_snapped_pos
	
	# Calculate delta for shader scrolling
	var delta_pos = current_snapped_pos - last_snapped_pos
	
	# Convert to UV space (0-1)
	# Delta X in world space -> UV U
	# Delta Z in world space -> UV V
	# UV = World / GridSize
	uv_offset = Vector2(delta_pos.x / grid_size, delta_pos.z / grid_size)
	
	last_snapped_pos = current_snapped_pos

	# UPDATE MATERIAL UNIFORMS FOR BLENDING
	if material_to_update:
		# transform vec4: min_x, min_z, size_x, size_z
		# global_position is center. min = center - size/2
		var min_pos = current_snapped_pos - Vector3(grid_size, 0, grid_size) * 0.5
		var area_vec = Vector4(min_pos.x, min_pos.z, grid_size, grid_size)
		material_to_update.set_shader_parameter("swe_area", area_vec)
		material_to_update.set_shader_parameter("swe_color_strength", 1.0 if debug_color_ripples else 0.0)

func _get_params_bytes(dt: float) -> PackedByteArray:
	var buffer = StreamPeerBuffer.new()
	buffer.put_float(dt)
	buffer.put_float(grid_size)
	buffer.put_float(drag)
	buffer.put_float(gravity)
	buffer.put_32(texture_size)
	buffer.put_32(texture_size)
	
	# Align to 16 bytes. Current: 4*4 + 4*2 = 24 bytes.
	# Next is vec2 uv_offset (8 bytes). 
	# GLSL std430/std140 alignment rules can be tricky.
	# Safest: Pack floats then pad.  
	# Let's check struct layout in GLSL:
	# struct Params {
	#   float delta_time;
	#   float grid_size;
	#   float drag;
	#   float gravity;
	#   ivec2 texture_size;
	#   vec2 offset;   <-- NEW
	# };
	
	buffer.put_float(uv_offset.x)
	buffer.put_float(uv_offset.y)
	
	return buffer.data_array

func _generate_empty_data(size: int) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(size * size * 16)
	
	var buffer = StreamPeerBuffer.new()
	buffer.data_array = data
	
	var center = float(size) / 2.0
	var radius = float(size) / 10.0
	
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			var h = 0.0
			
			# Gaussian Splash
			if dist < radius * 2.0:
				h = 5.0 * exp(-(dist * dist) / (radius * radius))
				
			buffer.put_float(h)   # R: Height
			buffer.put_float(0.0) # G: Vel X
			buffer.put_float(0.0) # B: Vel Z
			buffer.put_float(0.0) # A: Foam
			
	return buffer.data_array

func create_splash(uv_pos: Vector2, radius: float, strength: float):
	# UV (0..1) to Local Meters (-size/2 .. size/2)
	# But interactions are defined in Local Meters in Shader.
	# uv_pos here is likely Local Meters or UV?
	# "create_splash" name implies UV usually?
	# Let's assume input is WORLD POSITION for ease of use?
	# Or Local Position (relative to this node)?
	# Let's assume Local Position (Meters).
	
	# The input arguments say "uv_pos". If it's UV, convert to meters.
	# But caller often has World Pos.
	# Let's change signature or assume UV and convert.
	# uv_pos (0,0 is top-left, 1,1 is bottom-right).
	# Center is 0.5, 0.5.
	
	var local_x = (uv_pos.x - 0.5) * grid_size
	var local_z = (uv_pos.y - 0.5) * grid_size
	
	pending_interactions.append({
		"pos": Vector2(local_x, local_z),
		"radius": radius,
		"strength": strength
	})

func add_interaction_world(world_pos: Vector3, radius: float, strength: float):
	var local_3d = world_pos - global_position
	# global_position is the center of the grid surface
	pending_interactions.append({
		"pos": Vector2(local_3d.x, local_3d.z),
		"radius": radius,
		"strength": strength
	})

func _generate_empty_interactions() -> PackedByteArray:
	var buffer = StreamPeerBuffer.new()
	buffer.put_32(0) # count
	buffer.put_32(0) # pad
	buffer.put_32(0) # pad
	buffer.put_32(0) # pad
	
	# 16 items * 16 bytes (vec4)
	for i in range(16 * 4): # 16 vec4 = 64 floats
		buffer.put_float(0.0)
		
	return buffer.data_array

func _get_interactions_bytes() -> PackedByteArray:
	var buffer = StreamPeerBuffer.new()
	
	var count = min(pending_interactions.size(), 16)
	buffer.put_32(count)
	buffer.put_32(0)
	buffer.put_32(0)
	buffer.put_32(0)
	
	for i in range(16):
		if i < count:
			var item = pending_interactions[i]
			buffer.put_float(item.pos.x)
			buffer.put_float(item.pos.y)
			buffer.put_float(item.radius)
			buffer.put_float(item.strength)
		else:
			buffer.put_float(0.0)
			buffer.put_float(0.0)
			buffer.put_float(0.0)
			buffer.put_float(0.0)
			
	return buffer.data_array
	
@export var trigger_splash: bool = false : set = _set_trigger_splash

func _set_trigger_splash(val):
	if val and rd:
		reset_sim()
	trigger_splash = false

func reset_sim():
	if not rd: return
	# Re-create initial data with splash
	var initial_data = _generate_empty_data(texture_size)
	if texture_0_rid.is_valid():
		rd.texture_update(texture_0_rid, 0, initial_data)
	if texture_1_rid.is_valid():
		rd.texture_update(texture_1_rid, 0, initial_data)
	print("SWE Simulation Reset with Splash")

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if texture_0_rid.is_valid(): rd.free_rid(texture_0_rid)
			if texture_1_rid.is_valid(): rd.free_rid(texture_1_rid)
			if params_buffer_rid.is_valid(): rd.free_rid(params_buffer_rid)
			if interactions_buffer_rid.is_valid(): rd.free_rid(interactions_buffer_rid)
			if shader_rid.is_valid(): rd.free_rid(shader_rid)
			# Do not free Global RD!
			# rd.free()
