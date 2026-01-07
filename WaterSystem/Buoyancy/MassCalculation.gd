extends RigidBody3D

@export var buoyant_cells: Array[MeshInstance3D]
@export var drag_coef_axial: float = 0.15
@export var drag_coef_lateral: float = 1.0
@export var drag_coef_vertical: float = 1.0
@export var drag_coef_yaw: float = 100.0
@export var drag_coef_pitch: float = 100.0
@export var drag_coef_roll: float = 100.0

const WATER_MASS_DENSITY := 1000 # kg / m^3
const DRAG_SCALE: float = 1.0

func _ready() -> void:
	calculate_mass_properties()

func calculate_mass_properties():
	var prospective_mass = 0.0
	var bounds = Vector3.ZERO
	
	if buoyant_cells.size() == 0:
		# Auto-find child buoyant cells if not assigned
		for child in get_children():
			if child.has_method("mass"):
				buoyant_cells.append(child)
	
	if buoyant_cells.size() == 0:
		return

	for cell in buoyant_cells:
		if cell.mesh:
			bounds = bounds.max(abs(cell.position) + abs(0.5 * cell.mesh.size))
		prospective_mass += cell.mass()

	if prospective_mass > 0:
		mass = prospective_mass
		# Automatic inertia approximation
		inertia = Vector3(
			pow(bounds.y * bounds.z * 0.15, 2), 
			pow(bounds.x * bounds.z * 0.15, 2), 
			pow(bounds.x * bounds.y * 0.15, 2)
		) * mass

func _physics_process(_delta: float) -> void:
	if WaterManager.instance == null: return
	apply_drag()

func apply_drag() -> void:
	apply_drag_axial()
	apply_drag_lateral()
	apply_drag_vertical()
	
	apply_yaw_drag()
	apply_pitch_drag()
	apply_roll_drag()

func apply_yaw_drag() -> void:
	# Simplified drag calcs without mesh dependency if possible, or assume bounds
	# For now, relying on 'mesh' exported variable in original script which I omitted.
	# Let's try to use the first buoyant cell or bounds as reference if no main mesh.
	var ref_size = Vector3(2, 1, 5) # Default fallback
	# Ideally user assigns a main mesh mostly for size ref
	
	var area = ref_size.y * ref_size.x
	var length = ref_size.x
	var local_angular_velocity = angular_velocity.dot(global_transform.basis.y)
	var torque_magnitude = calculate_drag_torque(area, length, local_angular_velocity, drag_coef_yaw)
	var torque = torque_magnitude * basis.y
	apply_torque(torque)

func apply_roll_drag() -> void:
	var ref_size = Vector3(2, 1, 5)
	var area = ref_size.z * ref_size.x
	var length = ref_size.z
	var local_angular_velocity = angular_velocity.dot(global_transform.basis.x)
	var torque_magnitude = calculate_drag_torque(area, length, local_angular_velocity, drag_coef_roll)
	var torque = torque_magnitude * basis.x
	apply_torque(torque)

func apply_pitch_drag() -> void:
	var ref_size = Vector3(2, 1, 5)
	var area = ref_size.x * ref_size.z
	var length = ref_size.x
	var local_angular_velocity = angular_velocity.dot(global_transform.basis.z)
	var torque_magnitude = calculate_drag_torque(area, length, local_angular_velocity, drag_coef_pitch)
	var torque = torque_magnitude * basis.z
	apply_torque(torque)

func apply_drag_vertical() -> void:
	var ref_size = Vector3(2, 1, 5)
	var area = ref_size.x * ref_size.z
	var water_vel = WaterManager.instance.get_water_velocity(global_position)
	var relative_vel_vec = linear_velocity - water_vel
	
	var local_velocity = relative_vel_vec.dot(global_transform.basis.y)
	var vertical_drag = calculate_drag(area, local_velocity, drag_coef_vertical) * basis.y * DRAG_SCALE
	apply_central_force(vertical_drag)

func apply_drag_axial() -> void:
	var ref_size = Vector3(2, 1, 5)
	var area = ref_size.y * ref_size.z
	var water_vel = WaterManager.instance.get_water_velocity(global_position)
	var relative_vel_vec = linear_velocity - water_vel
	
	var local_velocity = relative_vel_vec.dot(global_transform.basis.x)
	var axial_drag = calculate_drag(area, local_velocity, drag_coef_axial) * basis.x * DRAG_SCALE
	apply_central_force(axial_drag)

func apply_drag_lateral() -> void:
	var ref_size = Vector3(2, 1, 5)
	var area = ref_size.y * ref_size.x
	var water_vel = WaterManager.instance.get_water_velocity(global_position)
	var relative_vel_vec = linear_velocity - water_vel
	
	var local_velocity = relative_vel_vec.dot(global_transform.basis.z)
	var lateral_drag = calculate_drag(area, local_velocity, drag_coef_lateral) * basis.z * DRAG_SCALE
	apply_central_force(lateral_drag)

func calculate_drag_torque(area, length, ang_vel, drag_coef) -> float:
	var torque_magnitude = (0.5 * WATER_MASS_DENSITY * ang_vel * ang_vel * area * drag_coef * length * 0.25)
	if ang_vel > 0:
		return - torque_magnitude
	else:
		return torque_magnitude

func calculate_drag(area, velocity, drag_coef) -> float:
	var drag_magnitude = (0.5 * WATER_MASS_DENSITY * velocity * velocity * area * drag_coef)
	if velocity > 0:
		return - drag_magnitude
	else:
		return drag_magnitude
