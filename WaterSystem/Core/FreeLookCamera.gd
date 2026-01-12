extends Camera3D

## FreeLookCamera - Simple flying camera for debugging and demos.
## Controls:
## - Mouse: Rotate camera
## - W/S: Forward/Backward
## - A/D: Left/Right
## - Q/E or Shift/Space: Down/Up
## - Right Click: Capture/Release mouse

@export var move_speed: float = 10.0
@export var look_sensitivity: float = 0.2
@export var acceleration: float = 10.0
@export var velocity: Vector3 = Vector3.ZERO

func _input(event):
	# Mouse look when mouse is captured
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * look_sensitivity))
		
		var changev = - event.relative.y * look_sensitivity
		if rotation_degrees.x + changev < 89 and rotation_degrees.x + changev > -89:
			rotate_object_local(Vector3(1, 0, 0), deg_to_rad(changev))

	# Toggle mouse capture
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta):
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		return

	var direction = Vector3.ZERO
	
	# Horizontal movement
	if Input.is_key_pressed(KEY_W): direction -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S): direction += global_transform.basis.z
	if Input.is_key_pressed(KEY_A): direction -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D): direction += global_transform.basis.x
	
	# Vertical movement (Up/Down)
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_SHIFT):
		direction -= Vector3.UP
	
	direction = direction.normalized()
	
	# Smoothing and movement
	var target_vel = direction * move_speed
	velocity = velocity.lerp(target_vel, acceleration * delta)
	global_position += velocity * delta
