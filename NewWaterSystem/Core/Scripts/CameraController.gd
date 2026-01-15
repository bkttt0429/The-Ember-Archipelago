extends Camera3D

@export var speed = 50.0
@export var sensitivity = 0.3

func _process(delta):
	# WASD 移动
	var input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var move = Vector3(input.x, 0, input.y) * speed * delta
	global_position += global_transform.basis * move
	
	# QE 上下
	if Input.is_key_pressed(KEY_Q):
		global_position.y -= speed * delta
	if Input.is_key_pressed(KEY_E):
		global_position.y += speed * delta

func _input(event):
	# 右键拖拽旋转视角
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation.y -= event.relative.x * sensitivity * 0.01
		rotation.x -= event.relative.y * sensitivity * 0.01
		rotation.x = clamp(rotation.x, -PI / 2, PI / 2)
