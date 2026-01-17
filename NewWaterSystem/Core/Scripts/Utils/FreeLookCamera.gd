class_name FreeLookCamera
extends Camera3D

@export var move_speed: float = 20.0
@export var boost_speed_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.3
@export var smooth_movement: bool = true
@export var smooth_speed: float = 10.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _target_velocity: Vector3 = Vector3.ZERO
var _current_velocity: Vector3 = Vector3.ZERO
var _look_enabled: bool = false

func _ready():
	_yaw = rotation_degrees.y
	_pitch = rotation_degrees.x

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look_enabled = event.pressed
			if _look_enabled:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseMotion and _look_enabled:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clamp(_pitch, -90, 90)
		rotation_degrees = Vector3(_pitch, _yaw, 0)

func _process(delta):
	var direction = Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		direction -= transform.basis.y
	if Input.is_key_pressed(KEY_E):
		direction += transform.basis.y
		
	direction = direction.normalized()
	
	var speed = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_speed_multiplier
		
	_target_velocity = direction * speed
	
	if smooth_movement:
		_current_velocity = _current_velocity.lerp(_target_velocity, delta * smooth_speed)
	else:
		_current_velocity = _target_velocity
		
	global_position += _current_velocity * delta
