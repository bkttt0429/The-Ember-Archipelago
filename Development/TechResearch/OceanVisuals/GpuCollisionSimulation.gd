@tool
extends Node3D

# --- Configuration ---
@export_group("Simulation Settings")
@export var compute_shader: RDShaderFile
@export var texture_size: int = 256
@export var grid_size: float = 40.0
@export var drag: float = 0.05
@export var gravity: float = 9.8
@export var sub_steps: int = 4
@export var simulation_freq: float = 60.0
@export var time_scale: float = 1.0 # Global speed multiplier

@export_group("Debug & Visuals")
@export var material_to_update: ShaderMaterial
@export var wave_height_scale: float = 2.0
@export var start_pulse_strength: float = 20.0
@export var trigger_pulse: bool = false:
	set(v):
		if v: add_collision_emitter(Vector2(0, 0), 5.0, 20.0, true)
		trigger_pulse = false

@export_group("Data/C++ Verification")
@export var enable_verification: bool = true
@export var debug_print_interval: float = 1.0

# --- Internals ---
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

# Ping-Pong Buffers: [0]=A, [1]=B
var tex_sim: Array[RID] = [RID(), RID()] # Velocity/Height
var tex_conc: Array[RID] = [RID(), RID()] # Concentration (Color)
var tex_rds_sim: Array[Texture2DRD] = [null, null]
var tex_rds_conc: Array[Texture2DRD] = [null, null]

# Uniform Sets: [0] = Read A -> Write B, [1] = Read B -> Write A
var uniform_sets: Array[RID] = [RID(), RID()]

var buffer_params: RID
var buffer_interactions: RID

# State controls
var current_read_index: int = 0
var pending_interactions: Array[Dictionary] = []
var sim_time: float = 0.0
var debug_timer: float = 0.0
var has_started_pulse: bool = false
var is_ready: bool = false

var rng = RandomNumberGenerator.new()

func _ready():
	_init_gpu()

func _init_gpu():
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("GpuCollisionSimulation: No RenderingDevice.")
		return
		
	if not compute_shader:
		push_error("GpuCollisionSimulation: No shader file assigned.")
		return
		
	# 1. Compile Shader
	var spirv = compute_shader.get_spirv()
	if not spirv: return
	
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid(): return
	
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	
	# 2. Create Textures (A/B)
	var fmt = RDTextureFormat.new()
	fmt.width = texture_size
	fmt.height = texture_size
	# Using R32G32B32A32 Float for max precision
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	# Ensure SAMPLING bit is present!
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	# Initial clear to Zero (Black)
	var byte_data = PackedByteArray()
	byte_data.resize(texture_size * texture_size * 16) # 4 channels * 4 bytes = 16 bytes/pixel
	byte_data.fill(0)
	
	for i in range(2):
		# Create RIDs
		tex_sim[i] = rd.texture_create(fmt, RDTextureView.new(), [byte_data])
		tex_conc[i] = rd.texture_create(fmt, RDTextureView.new(), [byte_data])
		
		# Create Godot Texture Wrappers
		tex_rds_sim[i] = Texture2DRD.new()
		tex_rds_sim[i].texture_rd_rid = tex_sim[i]
		
		tex_rds_conc[i] = Texture2DRD.new()
		tex_rds_conc[i].texture_rd_rid = tex_conc[i]
		
	# 3. Create Buffers
	buffer_params = rd.storage_buffer_create(32) # Param struct
	buffer_interactions = rd.storage_buffer_create(16 + 16 * 32) # Interaction array
	
	# 4. Build Uniform Sets
	_build_uniform_sets()
	
	is_ready = true
	
	# --- Debug Checks & Auto-Fix ---
	if material_to_update == null:
		# FALLBACK: Try to find sibling SpheresVisualizer and grab its material
		var sibling = get_node_or_null("../SpheresVisualizer")
		if sibling and "visual_material" in sibling and sibling.visual_material:
			material_to_update = sibling.visual_material
			print("GpuCollisionSimulation: [AUTO-FIX] Found material on SpheresVisualizer.")
		else:
			push_error("CRITICAL: 'material_to_update' is NOT assigned in Inspector! Visuals will not work.")
	
	if material_to_update:
		print("GpuCollisionSimulation: Linked to Material: ", material_to_update)
		
	print("GpuCollisionSimulation: GPU Initialized. Ready for Verification.")

func _build_uniform_sets():
	# Layout in GLSL: 
	# 0: Sim In, 1: Conc In, 2: Sim Out, 3: Conc Out, 4: Params, 5: Interactions
	var u_params = RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_params.binding = 4
	u_params.add_id(buffer_params)
	
	var u_inter = RDUniform.new()
	u_inter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_inter.binding = 5
	u_inter.add_id(buffer_interactions)
	
	# Set 0: Read A(0), Write B(1)
	uniform_sets[0] = _create_set(tex_sim[0], tex_conc[0], tex_sim[1], tex_conc[1], u_params, u_inter)
	# Set 1: Read B(1), Write A(0)
	uniform_sets[1] = _create_set(tex_sim[1], tex_conc[1], tex_sim[0], tex_conc[0], u_params, u_inter)

func _create_set(r_sim, r_conc, w_sim, w_conc, u_p, u_i) -> RID:
	var u0 = _img_uniform(r_sim, 0)
	var u1 = _img_uniform(r_conc, 1)
	var u2 = _img_uniform(w_sim, 2)
	var u3 = _img_uniform(w_conc, 3)
	return rd.uniform_set_create([u0, u1, u2, u3, u_p, u_i], shader_rid, 0)

func _img_uniform(rid: RID, binding: int) -> RDUniform:
	var u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func _process(delta):
	if not is_ready: return
	
	sim_time += delta
	debug_timer += delta
	
	# --- Start Pulse Logic ---
	if not has_started_pulse and sim_time > 0.5:
		has_started_pulse = true
		add_collision_emitter(Vector2(0, 0), 6.0, start_pulse_strength, true)
		print("GpuCollisionSimulation: Start Pulse - Triggered!")
	
	if Input.is_action_just_pressed("ui_accept"):
		add_collision_emitter(Vector2(randf_range(-10, 10), randf_range(-10, 10)), 5.0, 20.0, rng.randf() > 0.5)
		print("User Pulse Triggered")
	
	var dt = (1.0 / simulation_freq) * time_scale
	_run_sim_step(dt)
	
	# --- Visual Synchronization ---
	if material_to_update:
		var valid_idx = current_read_index
		
		# Explicitly updating the texture parameter
		material_to_update.set_shader_parameter("sim_texture", tex_rds_sim[valid_idx])
		material_to_update.set_shader_parameter("conc_texture", tex_rds_conc[valid_idx])
		material_to_update.set_shader_parameter("grid_size", grid_size)
		material_to_update.set_shader_parameter("uv_offset", Vector2(global_position.x, global_position.z))
		material_to_update.set_shader_parameter("wave_height_scale", wave_height_scale)
		# Force update to ensure Godot refreshes usage?
		# material_to_update.property_list_changed_notify() # Only for editor
	else:
		if debug_timer > 3.0: # Periodic error
			push_warning("GpuCollisionSimulation: Material is missing, visual updates skipped.")

	# --- Verification ---
	if enable_verification and debug_timer > debug_print_interval:
		debug_timer = 0.0
		verify_gpu_data()

func _run_sim_step(dt: float):
	var sub_dt = dt / float(sub_steps)
	
	# Update Buffers
	_update_params_buffer()
	_update_interactions_buffer()
	
	# Dispatch Substeps
	for i in range(sub_steps):
		# Pass 0: Velocity/Collision
		_dispatch(0, sub_dt)
		current_read_index = 1 - current_read_index # Swap
		
		# Pass 1: Height/Advection
		_dispatch(1, sub_dt)
		current_read_index = 1 - current_read_index # Swap
	
	pending_interactions.clear()

func verify_gpu_data():
	var idx = current_read_index
	# We perform a download of the 'conc' texture
	var bytes = rd.texture_get_data(tex_conc[idx], 0)
	if bytes.size() == 0: return

	# Check center pixel
	# Format R32G32B32A32 = 16 bytes per pixel
	var center_x = int(texture_size / 2)
	var center_y = int(texture_size / 2)
	var offset = (center_y * texture_size + center_x) * 16
	
	if offset + 16 <= bytes.size():
		var r = bytes.decode_float(offset + 0) # ConcA
		var g = bytes.decode_float(offset + 4) # ConcB
		
		print("[Verify GPU] Center Pixel: R=%.4f G=%.4f" % [r, g])

func _update_params_buffer():
	var buf = PackedByteArray()
	buf.resize(32)
	buf.encode_float(0, grid_size)
	buf.encode_float(4, drag)
	buf.encode_float(8, gravity)
	buf.encode_float(12, 0.0)
	buf.encode_float(16, float(texture_size))
	buf.encode_float(20, float(texture_size))
	buf.encode_float(24, global_position.x)
	buf.encode_float(28, global_position.z)
	rd.buffer_update(buffer_params, 0, 32, buf)

func _update_interactions_buffer():
	var buf = PackedByteArray()
	var max_inter = 16
	buf.resize(16 + max_inter * 32)
	
	var count = min(pending_interactions.size(), max_inter)
	buf.encode_u32(0, count)
	
	var struct_offset = 16
	for k in range(max_inter):
		if k < count:
			var item = pending_interactions[k]
			buf.encode_float(struct_offset + 0, item.pos.x)
			buf.encode_float(struct_offset + 4, item.pos.y)
			buf.encode_float(struct_offset + 8, item.radius)
			buf.encode_float(struct_offset + 12, item.strength)
			buf.encode_float(struct_offset + 16, item.color.x)
			buf.encode_float(struct_offset + 20, item.color.y)
		struct_offset += 32
	
	rd.buffer_update(buffer_interactions, 0, buf.size(), buf)

func _dispatch(mode: int, step_dt: float):
	var pc = PackedByteArray()
	pc.resize(16)
	pc.encode_u32(0, mode)
	pc.encode_float(4, step_dt)
	
	var set_rid = uniform_sets[current_read_index]
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, set_rid, 0)
	rd.compute_list_set_push_constant(cl, pc, pc.size())
	
	var groups = int(ceil(float(texture_size) / 8.0))
	rd.compute_list_dispatch(cl, groups, groups, 1)
	rd.compute_list_end()

func add_collision_emitter(pos: Vector2, radius: float, strength: float, is_red: bool):
	pending_interactions.append({
		"pos": pos,
		"radius": radius,
		"strength": strength,
		"color": Vector2(5.0, 0.0) if is_red else Vector2(0.0, 5.0)
	})

func _exit_tree():
	if rd:
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		for u in uniform_sets:
			if u.is_valid(): rd.free_rid(u)
		for t in tex_sim:
			if t.is_valid(): rd.free_rid(t)
		for t in tex_conc:
			if t.is_valid(): rd.free_rid(t)
		if buffer_params.is_valid(): rd.free_rid(buffer_params)
		if buffer_interactions.is_valid(): rd.free_rid(buffer_interactions)
