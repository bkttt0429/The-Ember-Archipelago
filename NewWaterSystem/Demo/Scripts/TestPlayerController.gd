extends CharacterBody3D
## Simple WASD movement controller for ripple testing

@export var move_speed: float = 8.0
@export var vertical_speed: float = 5.0 ## Speed for Q/E vertical movement
@export var swim_height: float = 0.0 # Y position when in water

func _physics_process(delta: float) -> void:
	# Get input direction
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	
	# WASD alternative
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S): input_dir.y += 1
	
	input_dir = input_dir.normalized()
	
	# Apply movement on XZ plane
	velocity.x = input_dir.x * move_speed
	velocity.z = input_dir.y * move_speed
	
	# Q/E for vertical movement (testing ripples at different heights)
	if Input.is_key_pressed(KEY_Q):
		position.y -= vertical_speed * delta
	if Input.is_key_pressed(KEY_E):
		position.y += vertical_speed * delta
	
	move_and_slide()
