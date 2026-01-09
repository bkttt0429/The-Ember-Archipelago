extends Camera3D

@export var speed: float = 20.0
@export var mouse_sensitivity: float = 0.002

func _ready():
	# Look at the "Player" position (approx ocean surface)
	look_at(Vector3(0, 500, 0), Vector3.UP)

func _input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3(1, 0, 0), -event.relative.y * mouse_sensitivity)

func _process(delta):
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if Input.is_key_pressed(KEY_E):
		move_dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move_dir += Vector3.DOWN
		
	if Input.is_key_pressed(KEY_SHIFT):
		move_dir *= 2.0
		
	global_position += move_dir * speed * delta
