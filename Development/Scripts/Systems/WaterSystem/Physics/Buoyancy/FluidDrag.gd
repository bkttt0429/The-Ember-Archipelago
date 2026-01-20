extends Node
class_name FluidDrag

## 流体动力学阻力系统
## 为 RigidBody3D 提供水中阻力计算，包括线性和角阻力

@export_group("Linear Drag Coefficients")
@export var drag_coef_axial: float = 0.15    # 前进方向（通常最小）
@export var drag_coef_lateral: float = 1.0    # 侧向
@export var drag_coef_vertical: float = 1.0   # 垂直

@export_group("Angular Drag Coefficients")
@export var drag_coef_yaw: float = 100        # 偏航（绕 Y 轴）
@export var drag_coef_pitch: float = 100      # 俯仰（绕 Z 轴）
@export var drag_coef_roll: float = 100       # 翻滚（绕 X 轴）

@export_group("Settings")
@export var enabled: bool = true
@export var drag_scale: float = 1.0  # 全局阻力缩放

const WATER_MASS_DENSITY := 1000.0  # kg/m³

var parent_body: RigidBody3D = null

func _ready():
	parent_body = get_parent() as RigidBody3D
	if not parent_body:
		push_error("FluidDrag must be a child of RigidBody3D")

func _physics_process(delta: float):
	if not enabled or not parent_body:
		return
	
	# Global Safety Check: If parent velocity is insane, reset it or skip
	if not parent_body.linear_velocity.is_finite() or not parent_body.angular_velocity.is_finite():
		push_warning("FluidDrag: Parent body velocity invalid (NaN/Inf). Resetting.")
		parent_body.linear_velocity = Vector3.ZERO
		parent_body.angular_velocity = Vector3.ZERO
		return

	apply_linear_drag()
	apply_angular_drag()

func apply_linear_drag():
	# 轴向阻力（前进方向）
	apply_drag_axial()
	# 侧向阻力
	apply_drag_lateral()
	# 垂直阻力
	apply_drag_vertical()

func apply_drag_axial():
	var area = estimate_cross_section(parent_body, parent_body.global_transform.basis.x)
	var local_velocity = parent_body.linear_velocity.dot(parent_body.global_transform.basis.x)
	var drag_magnitude = calculate_drag(area, local_velocity, drag_coef_axial)
	var drag_force = -parent_body.global_transform.basis.x * drag_magnitude * drag_scale
	parent_body.apply_central_force(drag_force)

func apply_drag_lateral():
	var area = estimate_cross_section(parent_body, parent_body.global_transform.basis.z)
	var local_velocity = parent_body.linear_velocity.dot(parent_body.global_transform.basis.z)
	var drag_magnitude = calculate_drag(area, local_velocity, drag_coef_lateral)
	var drag_force = -parent_body.global_transform.basis.z * drag_magnitude * drag_scale
	parent_body.apply_central_force(drag_force)

func apply_drag_vertical():
	var area = estimate_cross_section(parent_body, parent_body.global_transform.basis.y)
	var local_velocity = parent_body.linear_velocity.dot(parent_body.global_transform.basis.y)
	var drag_magnitude = calculate_drag(area, local_velocity, drag_coef_vertical)
	var drag_force = -parent_body.global_transform.basis.y * drag_magnitude * drag_scale
	parent_body.apply_central_force(drag_force)

func apply_angular_drag():
	apply_yaw_drag()
	apply_pitch_drag()
	apply_roll_drag()

func apply_yaw_drag():
	# 偏航阻力（绕 Y 轴）
	var mesh_inst = _find_mesh_instance()
	if not mesh_inst or not mesh_inst.mesh:
		return
	
	var length = mesh_inst.mesh.size.x  # 长轴
	var area = mesh_inst.mesh.size.y * mesh_inst.mesh.size.z
	var local_angular_velocity = parent_body.angular_velocity.dot(parent_body.global_transform.basis.y)
	var torque_magnitude = calculate_drag_torque(area, length, local_angular_velocity, drag_coef_yaw)
	var torque = -parent_body.global_transform.basis.y * torque_magnitude * drag_scale
	parent_body.apply_torque(torque)

func apply_pitch_drag():
	# 俯仰阻力（绕 Z 轴）
	var mesh_inst = _find_mesh_instance()
	if not mesh_inst or not mesh_inst.mesh:
		return
	
	var length = mesh_inst.mesh.size.x
	var area = mesh_inst.mesh.size.x * mesh_inst.mesh.size.z
	var local_angular_velocity = parent_body.angular_velocity.dot(parent_body.global_transform.basis.z)
	var torque_magnitude = calculate_drag_torque(area, length, local_angular_velocity, drag_coef_pitch)
	var torque = -parent_body.global_transform.basis.z * torque_magnitude * drag_scale
	parent_body.apply_torque(torque)

func apply_roll_drag():
	# 翻滚阻力（绕 X 轴）
	var mesh_inst = _find_mesh_instance()
	if not mesh_inst or not mesh_inst.mesh:
		return
	
	var length = mesh_inst.mesh.size.z
	var area = mesh_inst.mesh.size.z * mesh_inst.mesh.size.x
	var local_angular_velocity = parent_body.angular_velocity.dot(parent_body.global_transform.basis.x)
	var torque_magnitude = calculate_drag_torque(area, length, local_angular_velocity, drag_coef_roll)
	var torque = -parent_body.global_transform.basis.x * torque_magnitude * drag_scale
	parent_body.apply_torque(torque)

func calculate_drag(area: float, velocity: float, drag_coef: float) -> float:
	# 阻力公式：F = 0.5 * ρ * v² * A * Cd
	if not is_finite(velocity):
		return 0.0
	
	var drag_magnitude = 0.5 * WATER_MASS_DENSITY * velocity * abs(velocity) * area * drag_coef
	
	# Clamp to reasonable maximum (e.g. 100,000 N) to prevent explosions
	return clamp(drag_magnitude, -100000.0, 100000.0)

func calculate_drag_torque(area: float, length: float, angular_velocity: float, drag_coef: float) -> float:
	# 角阻力：T = 0.5 * ρ * ω² * A * L * 0.25 * Cd
	# 0.25 是平均力臂系数
	if not is_finite(angular_velocity):
		return 0.0
		
	var torque_magnitude = 0.5 * WATER_MASS_DENSITY * angular_velocity * abs(angular_velocity) * area * drag_coef * length * 0.25
	
	# Clamp torque
	return clamp(torque_magnitude, -50000.0, 50000.0)

func estimate_cross_section(body: RigidBody3D, direction: Vector3) -> float:
	# 估算物体在给定方向上的横截面积
	# 简化方法：查找 MeshInstance3D 并使用其边界框估算
	var mesh_inst = _find_mesh_instance()
	if mesh_inst and mesh_inst.mesh:
		var size = mesh_inst.mesh.size
		# 根据方向估算横截面积
		var abs_dir = direction.abs()
		if abs_dir.x > abs_dir.y and abs_dir.x > abs_dir.z:
			# X 方向最大，横截面是 YZ 平面
			return size.y * size.z
		elif abs_dir.y > abs_dir.z:
			# Y 方向最大，横截面是 XZ 平面
			return size.x * size.z
		else:
			# Z 方向最大，横截面是 XY 平面
			return size.x * size.y
	
	# 默认值（如果找不到 mesh）
	return 1.0

func _find_mesh_instance() -> MeshInstance3D:
	# 查找父节点下的 MeshInstance3D
	if parent_body:
		for child in parent_body.get_children():
			if child is MeshInstance3D:
				return child as MeshInstance3D
	return null
