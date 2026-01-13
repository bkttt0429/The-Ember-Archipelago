@tool
extends Node3D

## WaterTestSpawner - Spawns a moving test object with WaterInteractor3D.
## Attach this to the scene root or WaterManager.

@export var movement_mode: int = 0 # 0: Circle, 1: Ping-Pong
@export var test_object_radius: float = 12.0
@export var test_object_speed: float = 1.5

func _ready():
	# Wait a frame to ensure WaterManager is ready
	await get_tree().process_frame
	
	spawn_test_object()

func spawn_test_object():
	var obj = Node3D.new() # Use Node3D for simpler test movement
	obj.name = "WaterTestObject"
	add_child(obj)
	
	# Add Visuals
	var mesh_inst = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 2.0
	mesh_inst.mesh = mesh
	obj.add_child(mesh_inst)
	
	# Add a visible material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0) # Orange for visibility
	mesh_inst.material_override = mat
	
	# VERY IMPORTANT: Set owner for editor visibility
	if Engine.is_editor_hint():
		obj.owner = get_tree().edited_scene_root
		mesh_inst.owner = get_tree().edited_scene_root
	
	# Add Mover Script
	var mover_script = load("res://WaterSystem/Core/WaterTestMover.gd")
	obj.set_script(mover_script)
	obj.mode = movement_mode
	obj.radius = test_object_radius
	obj.speed = test_object_speed
	
	# Add WaterInteractor3D
	var interactor_script = load("res://WaterSystem/Components/WaterInteractor3D.gd")
	var interactor = Node3D.new()
	interactor.name = "WaterInteractor3D"
	interactor.set_script(interactor_script)
	obj.add_child(interactor)
	
	if Engine.is_editor_hint():
		interactor.owner = get_tree().edited_scene_root
	
	# Find WaterManager
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if not managers.is_empty():
		interactor.water_manager = managers[0]
	
	print("[DEBUG] Spawned Water Test Object at: ", obj.global_position)
