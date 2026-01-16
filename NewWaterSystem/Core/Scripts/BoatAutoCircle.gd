class_name BoatAutoCircle
extends RigidBody3D

@export var active: bool = true
@export var forward_force: float = 8000.0
@export var turn_strength: float = 1500.0

func _ready():
	# Ensure damping is reasonable so it doesn't spin out of control
	linear_damp = 1.0
	angular_damp = 2.0

func _physics_process(_delta):
	if not active: return
	
	# Assuming X axis is forward (since Box length is 4 on X)
	var forward_dir = global_transform.basis.x
	
	# Apply Forward Drive
	apply_central_force(forward_dir * forward_force)
	
	# Apply Turning Torque (Y axis rotation)
	apply_torque(Vector3(0, turn_strength, 0))
