@tool
class_name OceanLODManager
extends Node3D

## OceanLODManager - Hierarchical Cascaded Grid System
## Manages multiple levels of water mesh centered near the camera.

@export var water_manager: OceanWaterManager
@export var levels: int = 4
@export var base_resolution: int = 64
@export var base_size: float = 40.0
@export var layer_scale: float = 2.0

var cascades: Array[MeshInstance3D] = []

func _ready():
	if not water_manager:
		water_manager = get_parent() as OceanWaterManager
	call_deferred("_initialize_cascades")

func _process(_delta):
	if not Engine.is_editor_hint() or true: # Also run in editor for preview
		_update_cascade_positions()

func _initialize_cascades():
	# Clear existing
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()
	cascades.clear()
	
	var current_size = base_size
	
	for i in range(levels):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Cascade_%d" % i
		
		var mesh = PlaneMesh.new()
		mesh.size = Vector2(current_size, current_size)
		# Use WaterManager's grid_res if available, otherwise fallback to local base_resolution
		var res = water_manager.grid_res if water_manager else base_resolution
		mesh.subdivide_depth = res - 1
		mesh.subdivide_width = res - 1
		
		mesh_inst.mesh = mesh
		add_child(mesh_inst)
		cascades.append(mesh_inst)
		
		# Set material (shared from WaterManager)
		if water_manager:
			_apply_material_to_cascade(mesh_inst)
		
		current_size *= layer_scale

func _apply_material_to_cascade(cascade: MeshInstance3D):
	# Wait for WaterManager visual setup if needed
	var plane = water_manager.get_node_or_null("WaterPlane")
	if plane:
		cascade.set_surface_override_material(0, plane.get_surface_override_material(0))

func _update_cascade_positions():
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	var cam_pos = cam.global_position
	# Snap to grid to avoid shimmering/jittering aliasing
	var snap = base_size / float(base_resolution)
	var target_pos = Vector3(
		floor(cam_pos.x / snap) * snap,
		water_manager.global_position.y if water_manager else 0.0,
		floor(cam_pos.z / snap) * snap
	)
	
	global_position = target_pos
	
	# Optional: Offset individual cascades if using a cross-grid approach
	# For simplicity, we just keep them centered for now.

func rebuild():
	_initialize_cascades()
