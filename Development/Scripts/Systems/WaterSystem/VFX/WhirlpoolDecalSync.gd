extends MeshInstance3D

@export var center_offset: Vector3 = Vector3.ZERO
@export var shader_parameter: StringName = "center_world"

func _process(_delta: float) -> void:
	if not mesh:
		return
	var material = mesh.surface_get_material(0)
	if material is ShaderMaterial:
		material.set_shader_parameter(shader_parameter, global_position + center_offset)
