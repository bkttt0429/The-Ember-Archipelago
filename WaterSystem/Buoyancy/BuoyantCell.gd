extends MeshInstance3D

@export var cell_density_kg_per_m3: float = 500 # 500 is about right for solid wood
@export var calc_f_gravity: bool = false # True if this should simulate gravity on this cell
@export var active: bool = true

var fluid_density_kg_per_m3: float = 1000

# Access global WaterManager
var water_manager = null

func _ready():
	# Find WaterManager safely
	if has_node("/root/WaterManager"):
		water_manager = get_node("/root/WaterManager")

func _physics_process(delta: float) -> void:
	if !active:
		return
		
	if water_manager == null:
		if has_node("/root/WaterManager"):
			water_manager = get_node("/root/WaterManager")
		else:
			return

	apply_force_on_cell(delta)

func mass() -> float:
	if mesh == null: return 0.0
	var size = mesh.size
	var volume: float = size.x * size.y * size.z
	return cell_density_kg_per_m3 * volume

func apply_force_on_cell(delta: float) -> void:
	if mesh == null: return
	
	var parent_body = get_parent()
	if not (parent_body is RigidBody3D):
		return

	var size = mesh.size
	var volume: float = size.x * size.y * size.z
	
	# Get height from WaterManager
	var wave_height = water_manager.get_wave_height(global_position)
	var depth: float = wave_height - global_position.y
	
	var gravity_vec = ProjectSettings.get_setting("physics/3d/default_gravity_vector") 
	var gravity = gravity_vec * ProjectSettings.get_setting("physics/3d/default_gravity")
	
	# Calculate submerged fraction
	var submerged_fraction = clampf((depth + 0.5 * size.y) / size.y, 0.0, 1.0)
	
	if submerged_fraction > 0:
		var displaced_mass = fluid_density_kg_per_m3 * volume * submerged_fraction
		var f_buoyancy: Vector3 = displaced_mass * -gravity
		
		# Apply Buoyancy
		var force_location = parent_body.global_transform.basis * position
		parent_body.apply_force(f_buoyancy, force_location)
		
	# Apply Gravity (if enabled per cell)
	if calc_f_gravity:
		var f_gravity = mass() * gravity
		var force_location = parent_body.global_transform.basis * position
		parent_body.apply_force(f_gravity, force_location)
