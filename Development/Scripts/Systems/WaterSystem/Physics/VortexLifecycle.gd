extends Node

@export var force_field_path: NodePath
@export var visuals_path: NodePath
@export var decal_path: NodePath

@export var autoplay: bool = true
@export var spawn_time: float = 1.5
@export var sustain_time: float = 5.0
@export var despawn_time: float = 2.0

@export var target_radius_multiplier: float = 1.0
@export var target_strength_multiplier: float = 1.0
@export var target_visual_multiplier: float = 1.0

var _force_field: Node
var _visuals: Node3D
var _decal: MeshInstance3D
var _decal_material: ShaderMaterial
var _base_decal_radius: float
var _base_decal_depth: float
var _base_visual_scale: Vector3

var _visual_multiplier: float = 0.0

var visual_multiplier: float:
	get:
		return _visual_multiplier
	set(value):
		_visual_multiplier = value
		_update_visuals()

func _ready() -> void:
	_force_field = get_node_or_null(force_field_path)
	_visuals = get_node_or_null(visuals_path)
	_decal = get_node_or_null(decal_path)
	
	if _visuals:
		_base_visual_scale = _visuals.scale
	
	if _decal:
		var material = _decal.mesh.surface_get_material(0)
		if material is ShaderMaterial:
			_decal_material = material
			_base_decal_radius = _decal_material.get_shader_parameter("radius")
			_base_decal_depth = _decal_material.get_shader_parameter("depth")
	
	if autoplay:
		play_lifecycle()

func play_lifecycle() -> void:
	if not _force_field:
		return
	
	_force_field.active = true
	_force_field.radius_multiplier = 0.0
	_force_field.strength_multiplier = 0.0
	visual_multiplier = 0.0
	
	var tween = create_tween()
	tween.tween_property(_force_field, "radius_multiplier", target_radius_multiplier, spawn_time)
	tween.parallel().tween_property(_force_field, "strength_multiplier", target_strength_multiplier, spawn_time)
	tween.parallel().tween_property(self, "visual_multiplier", target_visual_multiplier, spawn_time)
	
	tween.tween_interval(sustain_time)
	
	tween.tween_property(_force_field, "radius_multiplier", 0.0, despawn_time)
	tween.parallel().tween_property(_force_field, "strength_multiplier", 0.0, despawn_time)
	tween.parallel().tween_property(self, "visual_multiplier", 0.0, despawn_time)
	
	tween.tween_callback(func():
		_force_field.active = false
	)

func _update_visuals() -> void:
	if _visuals:
		_visuals.scale = _base_visual_scale * _visual_multiplier
	
	if _decal_material:
		_decal_material.set_shader_parameter("radius", _base_decal_radius * _visual_multiplier)
		_decal_material.set_shader_parameter("depth", _base_decal_depth * _visual_multiplier)
