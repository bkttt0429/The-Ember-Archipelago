@tool
extends Node3D
class_name SphericalOceanNodes

@export_category("Grid Settings")
@export var grid_resolution: int = 127 : set = _set_resolution
@export var planet_radius: float = 500.0 : set = _set_planet_radius
@export var base_coverage: float = 64.0 : set = _set_base_coverage

@export_category("LOD Settings")
@export var lod_levels: int = 4 : set = _set_lod_levels
@export var radial_bias: float = 2.0 : set = _set_radial_bias
@export var skirt_depth: float = 5.0 : set = _set_skirt_depth

@export_category("Wave Integration")
@export var fft_source: Node3D # Expecting GpuOcean
@export var ripple_source: Node3D # Expecting GpuLocalOcean
@export var wave_height_scale: float = 2.0

@export_category("Visuals")
@export var color_deep: Color = Color(0.01, 0.05, 0.15) : set = _set_color_deep
@export var color_shallow: Color = Color(0.05, 0.4, 0.6) : set = _set_color_shallow
@export var color_ripple: Color = Color(0.1, 1.0, 0.8) : set = _set_color_ripple
@export var refraction_strength: float = 0.05 : set = _set_refraction
@export var fft_texture_scale: float = 128.0 : set = _set_fft_scale

@export_category("Target")
@export var follow_camera: Camera3D
@export var manual_target: Node3D

var _meshes: Array[MeshInstance3D] = []
var _shader_mat: ShaderMaterial
var _plane_mesh: PlaneMesh

func _ready():
	_rebuild_all()

func _set_color_deep(val):
	color_deep = val
	if _shader_mat: _shader_mat.set_shader_parameter("color_deep", color_deep)

func _set_color_shallow(val):
	color_shallow = val
	if _shader_mat: _shader_mat.set_shader_parameter("color_shallow", color_shallow)

func _set_color_ripple(val):
	color_ripple = val
	if _shader_mat: _shader_mat.set_shader_parameter("color_ripple", color_ripple)

func _set_refraction(val):
	refraction_strength = val
	if _shader_mat: _shader_mat.set_shader_parameter("refraction_strength", refraction_strength)

func _set_fft_scale(val):
	fft_texture_scale = val
	if _shader_mat: _shader_mat.set_shader_parameter("texture_scale", fft_texture_scale)

func _set_resolution(val):
	grid_resolution = val
	_rebuild_all()

func _set_planet_radius(val):
	planet_radius = val
	_update_shader_params()

func _set_base_coverage(val):
	base_coverage = val
	_rebuild_all()

func _set_lod_levels(val):
	lod_levels = val
	_rebuild_all()

func _set_radial_bias(val):
	radial_bias = val
	_update_shader_params()

func _set_skirt_depth(val):
	skirt_depth = val
	_update_shader_params()

func _rebuild_all():
	if not is_inside_tree(): return
	
	# 1. Cleanup
	for m in _meshes:
		if m: m.queue_free()
	_meshes.clear()
	
	# 2. Shared Plane Mesh (Carrier)
	_plane_mesh = PlaneMesh.new()
	_plane_mesh.size = Vector2(2, 2)
	_plane_mesh.subdivide_depth = grid_resolution - 1
	_plane_mesh.subdivide_width = grid_resolution - 1
	
	# 3. Setup Material
	var shader = load("res://Development/TechResearch/OceanVisuals/Shaders/spherical_nodes.gdshader")
	if shader:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = shader
	else:
		push_error("Failed to load ocean shader!")
		return
	
	# 4. Create LOD Layers
	var current_coverage = base_coverage
	for i in range(lod_levels):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "LOD_Level_" + str(i)
		mesh_inst.mesh = _plane_mesh
		mesh_inst.material_override = _shader_mat
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Set instance uniforms
		mesh_inst.set_instance_shader_parameter("level_coverage", current_coverage)
		mesh_inst.set_instance_shader_parameter("level_index", float(i))
		
		# Set enormous AABB to prevent culling issues with spheres
		mesh_inst.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
		
		add_child(mesh_inst)
		_meshes.append(mesh_inst)
		
		# Double coverage for next level
		current_coverage *= 2.0
	
	_update_shader_params()
	print("Spherical Ocean LOD Rebuilt: ", lod_levels, " levels, Grid: ", grid_resolution)

func _process(_delta):
	_update_target_pos()
	_update_wave_linkage()

func _update_target_pos():
	if not _shader_mat: return
	
	var target_pos = Vector3(0, planet_radius + 50, 0)
	if manual_target:
		target_pos = manual_target.global_position
	elif follow_camera:
		target_pos = follow_camera.global_position
	elif get_viewport() and get_viewport().get_camera_3d():
		target_pos = get_viewport().get_camera_3d().global_position
		
	# World-space snapping to prevent vertex jitter
	# We want the grid to "snap" to its own resolution spacing
	# Level 0 spacing = (base_coverage * 2) / (grid_resolution - 1)
	var base_spacing = (base_coverage * 2.0) / (grid_resolution - 1.0)
	
	# We keep the logical system at 0,0,0
	global_position = Vector3.ZERO 
	
	# Pass the raw target pos and the snapped version (or the offset)
	_shader_mat.set_shader_parameter("player_pos", target_pos)
	_shader_mat.set_shader_parameter("base_spacing", base_spacing)

func _update_shader_params():
	if not _shader_mat: return
	_shader_mat.set_shader_parameter("grid_resolution", float(grid_resolution))
	_shader_mat.set_shader_parameter("planet_radius", planet_radius)
	_shader_mat.set_shader_parameter("radial_bias", radial_bias)
	_shader_mat.set_shader_parameter("skirt_depth", skirt_depth)
	_shader_mat.set_shader_parameter("wave_height_scale", wave_height_scale)
	
	# Sync Visuals
	_shader_mat.set_shader_parameter("color_deep", color_deep)
	_shader_mat.set_shader_parameter("color_shallow", color_shallow)
	_shader_mat.set_shader_parameter("color_ripple", color_ripple)
	_shader_mat.set_shader_parameter("refraction_strength", refraction_strength)
	_shader_mat.set_shader_parameter("texture_scale", fft_texture_scale)

func _update_wave_linkage():
	if not _shader_mat: return
	
	var fft_node = fft_source
	if fft_node:
		if fft_node.get("material_to_update") != _shader_mat:
			fft_node.material_to_update = _shader_mat
			_shader_mat.set_shader_parameter("texture_scale", 128.0) # Larger scale for planet scale

	var ripple_node = ripple_source
	if ripple_node:
		if ripple_node.get("material_to_update") != _shader_mat:
			ripple_node.material_to_update = _shader_mat
			
			if "grid_size" in ripple_node:
				var half_size = ripple_node.grid_size * 0.5
				var area = Vector4(-half_size, -half_size, ripple_node.grid_size, ripple_node.grid_size)
				_shader_mat.set_shader_parameter("swe_area", area)
