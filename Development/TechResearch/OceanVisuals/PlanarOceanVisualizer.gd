@tool
extends Node3D
class_name PlanarOceanVisualizer

@export_group("Grid Settings")
@export var grid_resolution: int = 127:
	set(v):
		grid_resolution = v
		if is_inside_tree(): _rebuild_all()
@export var coverage_radius: float = 60.0:
	set(v):
		coverage_radius = v
		_update_materials()

@export_group("Visuals")
@export var sphere_radius: float = 0.5:
	set(v):
		sphere_radius = v
		_update_materials()
@export var sphere_mesh: Mesh = SphereMesh.new()
@export var visual_material: ShaderMaterial
@export var wave_height_scale: float = 2.5:
	set(v):
		wave_height_scale = v
		_update_materials()
@export var crest_softness: float = 0.5:
	set(v):
		crest_softness = v
		_update_materials()

@export var lod_levels: int = 4:
	set(v):
		lod_levels = v
		if is_inside_tree(): _rebuild_all()
@export var radial_bias: float = 2.0:
	set(v):
		radial_bias = v
		_update_materials()
@export var base_coverage: float = 64.0:
	set(v):
		base_coverage = v
		if is_inside_tree(): _rebuild_all()
@export var follow_target: Node3D

@export var color_deep: Color = Color(0.0, 0.27, 0.73):
	set(v):
		color_deep = v
		_update_materials()
@export var color_shallow: Color = Color(0.1, 0.9, 1.0):
	set(v):
		color_shallow = v
		_update_materials()
@export var color_ripple: Color = Color(1.0, 0.0, 0.0):
	set(v):
		color_ripple = v
		_update_materials()
@export var refraction_strength: float = 0.05:
	set(v):
		refraction_strength = v
		_update_materials()

@export_group("Simulation Links")
@export var gpu_ocean: Node3D # GpuOcean
@export var gpu_local_ocean: Node3D # GpuLocalOcean

@export_group("Debug")
@export var debug_lod: bool = false:
	set(v):
		debug_lod = v
		_update_materials()
@export var debug_wireframe: bool = false:
	set(v):
		debug_wireframe = v
		_update_materials()
@export var debug_normals: bool = false:
	set(v):
		debug_normals = v
		_update_materials()
@export var test_wave: bool = false:
	set(v):
		test_wave = v
		_update_materials()
@export var test_wave_amplitude: float = 2.0:
	set(v):
		test_wave_amplitude = v
		_update_materials()

var _meshes: Array[MeshInstance3D] = []
var _shader_mat: ShaderMaterial
var _plane_mesh: ArrayMesh 

func _ready():
	print("PlanarOceanVisualizer: Ready. Building grids...")
	_rebuild_all()

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_L:
			debug_lod = !debug_lod
			print("Ocean LOD Debug: ", debug_lod)
		if event.keycode == KEY_W:
			debug_wireframe = !debug_wireframe
			print("Ocean Wireframe Debug: ", debug_wireframe)
		if event.keycode == KEY_N:
			debug_normals = !debug_normals
			print("Ocean Normals Debug: ", debug_normals)
		if event.keycode == KEY_T:
			test_wave = !test_wave
			print("Ocean Test Wave: ", test_wave)
		if event.keycode == KEY_C:
			trigger_collision_waves()
			print("Triggered Collision Waves Debug")
			trigger_collision_waves()
			print("Triggered Collision Waves Debug")
		_update_materials()

@export var force_trigger_waves: bool = false:
	set(v):
		if v:
			trigger_collision_waves()
			print("Manual Force Trigger: Collision Waves dispatched!")
		force_trigger_waves = false # Reset immediately logic button behavior

func trigger_collision_waves():
	if not gpu_local_ocean: return
	
	var base_pos = Vector3.ZERO
	if follow_target: base_pos = follow_target.global_position
	
	# Spawn two opposing waves
	var pos_left = base_pos + Vector3(-20, 0, 0)
	var pos_right = base_pos + Vector3(20, 0, 0)
	
	# Add interaction (Massive strength 200, radius 10)
	gpu_local_ocean.add_interaction_world(pos_left, 10.0, 200.0)
	gpu_local_ocean.add_interaction_world(pos_right, 10.0, 200.0)
	print("PlanarOceanVisualizer: Dispatched Massive Collision Waves at ", base_pos)

func _rebuild_all():
	if not is_inside_tree(): return
	
	# Clean up
	for m in _meshes:
		if m: m.queue_free()
	_meshes.clear()
	
	# Generate a "Dummy" mesh that has N*N vertices for our Data-less shader
	# We use ArrayMesh to precisely control vertex count for VERTEX_ID
	_plane_mesh = ArrayMesh.new()
	var verts = PackedVector3Array()
	var indices = PackedInt32Array()
	
	# Create a grid of neutral vertices (0,0,0)
	# Shader will move them based on VERTEX_ID
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			verts.append(Vector3.ZERO)
			
	for z in range(grid_resolution - 1):
		for x in range(grid_resolution - 1):
			var i0 = x + z * grid_resolution
			var i1 = (x + 1) + z * grid_resolution
			var i2 = x + (z + 1) * grid_resolution
			var i3 = (x + 1) + (z + 1) * grid_resolution
			
			# Triangle 1
			indices.append(i0)
			indices.append(i1)
			indices.append(i2)
			# Triangle 2
			indices.append(i1)
			indices.append(i3)
			indices.append(i2)
			
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	_plane_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Load Shader
	var shader = load("res://Development/TechResearch/OceanVisuals/Shaders/water_planar_surface.gdshader")
	if shader:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = shader
	
	# Create LOD Layers
	var current_coverage = base_coverage
	for i in range(lod_levels):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Ocean_LOD_" + str(i)
		mesh_inst.mesh = _plane_mesh
		mesh_inst.material_override = _shader_mat
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Instance params
		mesh_inst.set_instance_shader_parameter("level_coverage", current_coverage)
		mesh_inst.set_instance_shader_parameter("level_index", float(i))
		
		# Prevent culling
		mesh_inst.custom_aabb = AABB(Vector3(-500, -100, -500), Vector3(1000, 200, 1000))
		
		add_child(mesh_inst)
		_meshes.append(mesh_inst)
		current_coverage *= 2.0

	_update_materials()

var _auto_fire_timer = 0.0

func _process(delta):
	# Tool script hot-reload safety
	if _auto_fire_timer == null: 
		_auto_fire_timer = 0.0
		
	_auto_fire_timer += delta
	if _auto_fire_timer > 2.0:
		_auto_fire_timer = 0.0
		trigger_collision_waves()
		print("Auto-Triggering Collision Waves...")
		
	_update_materials()

func _update_materials():
	if not _shader_mat: return
	
	var target_pos = Vector3.ZERO
	if follow_target:
		target_pos = follow_target.global_position
	else:
		var cam = get_viewport().get_camera_3d()
		if cam: target_pos = cam.global_position
		
	var base_spacing = (base_coverage * 2.0) / (grid_resolution - 1.0)
	
	_shader_mat.set_shader_parameter("player_pos", target_pos)
	_shader_mat.set_shader_parameter("grid_resolution", float(grid_resolution))
	_shader_mat.set_shader_parameter("radial_bias", radial_bias)
	_shader_mat.set_shader_parameter("base_spacing", base_spacing)
	_shader_mat.set_shader_parameter("debug_lod", debug_lod)
	_shader_mat.set_shader_parameter("debug_wireframe", debug_wireframe)
	_shader_mat.set_shader_parameter("debug_normals", debug_normals)
	_shader_mat.set_shader_parameter("test_wave", test_wave)
	_shader_mat.set_shader_parameter("test_wave_amplitude", test_wave_amplitude)
	_shader_mat.set_shader_parameter("wave_height_scale", wave_height_scale)
	_shader_mat.set_shader_parameter("crest_softness", crest_softness)
	
	# Visuals
	_shader_mat.set_shader_parameter("color_deep", color_deep)
	_shader_mat.set_shader_parameter("color_shallow", color_shallow)
	_shader_mat.set_shader_parameter("color_ripple", color_ripple)
	_shader_mat.set_shader_parameter("refraction_strength", refraction_strength)

	# Wave Links
	if gpu_ocean:
		gpu_ocean.material_to_update = _shader_mat
		_shader_mat.set_shader_parameter("texture_scale", gpu_ocean.get("texture_scale"))
		_shader_mat.set_shader_parameter("height_scale", gpu_ocean.get("height_scale"))

	if gpu_local_ocean:
		gpu_local_ocean.material_to_update = _shader_mat
		_shader_mat.set_shader_parameter("swe_height_scale", 1.0)
		_shader_mat.set_shader_parameter("swe_color_strength", 3.0) # Force high visibility for debug
		# swe_area is managed by GpuLocalOcean itself (handles snapping)
