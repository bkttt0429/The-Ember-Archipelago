extends Node
class_name MassCalculation

## 自动质量计算系统
## 根据 BuoyantCell 数组自动计算 RigidBody3D 的质量和惯性张量

@export var buoyant_cells: Array[MeshInstance3D] = []
@export var auto_calculate_on_ready: bool = true
@export var debug: bool = false

var parent_body: RigidBody3D = null

func _ready():
	# 尝试查找 RigidBody3D（可以是直接父节点或向上查找）
	parent_body = _find_rigid_body_parent()
	if not parent_body:
		push_warning("MassCalculation (" + str(get_path()) + ") must be a child of RigidBody3D. 质量计算将被跳过。")
		return
	
	if auto_calculate_on_ready:
		calculate_mass_and_inertia()

## 向上查找 RigidBody3D 父节点
func _find_rigid_body_parent() -> RigidBody3D:
	var current = get_parent()
	while current:
		if current is RigidBody3D:
			return current as RigidBody3D
		current = current.get_parent()
	return null

## 根据 BuoyantCell 数组计算总质量和惯性张量
func calculate_mass_and_inertia():
	if not parent_body:
		return
	
	var total_mass = 0.0
	var bounds = Vector3.ZERO
	
	# 收集所有 BuoyantCell
	var cells: Array[MeshInstance3D] = []
	if buoyant_cells.size() > 0:
		cells = buoyant_cells
	else:
		# 自动查找所有 BuoyantCell
		for child in parent_body.get_children():
			if child is MeshInstance3D and child.has_method("mass"):
				cells.append(child)
	
	# 计算总质量和边界
	for cell in cells:
		if cell.mesh:
			var size = cell.mesh.size
			# 更新边界（考虑位置偏移）
			var cell_bounds = abs(cell.position) + abs(0.5 * size)
			bounds = bounds.max(cell_bounds)
			
			# 累加质量
			if cell.has_method("mass"):
				total_mass += cell.mass()
	
	if total_mass > 0:
		parent_body.mass = total_mass
		
		# 计算简化的惯性张量（基于边界框）
		# 公式：I = m * (size² * 0.15)²
		# 0.15 是经验系数，适用于大多数形状
		var inertia_x = max(0.1, pow(bounds.y * bounds.z * 0.15, 2) * total_mass)
		var inertia_y = max(0.1, pow(bounds.x * bounds.z * 0.15, 2) * total_mass)
		var inertia_z = max(0.1, pow(bounds.x * bounds.y * 0.15, 2) * total_mass)
		
		parent_body.inertia = Vector3(inertia_x, inertia_y, inertia_z)
		
		if debug:
			print("---- ", parent_body.name, " Mass Calculation ----")
			print("Total Mass: ", total_mass)
			print("Bounds: ", bounds)
			print("Inertia: ", parent_body.inertia)
			print("Cell Count: ", cells.size())
	else:
		push_warning("MassCalculation: No cells found or total mass is 0")

## 手动触发重新计算（用于运行时修改）
func recalculate():
	calculate_mass_and_inertia()
