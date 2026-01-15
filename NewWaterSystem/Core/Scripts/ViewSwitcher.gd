extends Node

@export var free_camera_path: NodePath
@export var boat_camera_path: NodePath

var free_camera: Camera3D
var boat_camera: Camera3D

func _ready():
	if not free_camera_path.is_empty():
		free_camera = get_node_or_null(free_camera_path) as Camera3D
	
	if not boat_camera_path.is_empty():
		boat_camera = get_node_or_null(boat_camera_path) as Camera3D
		
	# Start with free camera
	if free_camera:
		free_camera.make_current()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		if free_camera and free_camera.current:
			if boat_camera: boat_camera.make_current()
		elif free_camera:
			free_camera.make_current()
