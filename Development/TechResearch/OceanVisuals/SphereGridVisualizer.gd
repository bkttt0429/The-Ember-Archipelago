@tool
extends Node3D

@export var grid_resolution: int = 64
@export var grid_size: float = 40.0
@export var sphere_mesh: Mesh
@export var visual_material: ShaderMaterial

var _multimesh_instance: MultiMeshInstance3D

func _ready():
	_rebuild()

func _rebuild():
	if _multimesh_instance:
		_multimesh_instance.queue_free()
	
	if not sphere_mesh:
		sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.15
		sphere_mesh.height = 0.3
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere_mesh
	mm.instance_count = grid_resolution * grid_resolution
	
	var spacing = grid_size / float(grid_resolution)
	var offset = grid_size * 0.5
	
	for z in range(grid_resolution):
		for x in range(grid_resolution):
			var idx = x + z * grid_resolution
			var pos = Vector3(x * spacing - offset, 0, z * spacing - offset)
			mm.set_instance_transform(idx, Transform3D(Basis(), pos))
			
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = mm
	if visual_material:
		_multimesh_instance.material_override = visual_material
	
	add_child(_multimesh_instance)

func _process(_delta):
	# The GpuSimulation script handles updating the visual_material parameters.
	# We just ensure the material is actually assigned to the MultiMesh.
	if _multimesh_instance and visual_material and _multimesh_instance.material_override != visual_material:
		_multimesh_instance.material_override = visual_material
