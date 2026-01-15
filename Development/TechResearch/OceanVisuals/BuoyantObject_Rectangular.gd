extends Node3D
class_name BuoyantObject_Rectangular

## BuoyantObject_Rectangular.gd
## 使用 4 點採樣（矩形）來模擬更穩定的船體浮力。
## 相比於 3 點採樣，這能更好與長型物體（如船隻）互動，減少單點支撐的搖晃感。

@export_group("Buoyancy")
@export var float_force: float = 25.0
@export var water_drag: float = 1.0 # 線性阻尼係數 (Linear Drag)
@export var angular_drag: float = 2.0 # 角速度阻尼

@export_group("Dimensions")
@export var width: float = 2.0 # 船寬
@export var length: float = 4.0 # 船長

@export_group("Interaction")
@export var ripple_strength: float = 5.0
@export var ripple_radius: float = 2.0

var velocity: Vector3 = Vector3.ZERO
var gpu_local_ocean: GpuLocalOcean
var water_manager: WaterSystemManager

# 4個採樣點相對於中心的偏移
var _offsets: Array[Vector3] = []

func _ready():
	gpu_local_ocean = get_tree().root.find_child("GpuLocalOcean_SWE", true, false)
	
	# 設定 4 個角落的偏移量 (本地空間)
	# FL, FR, BL, BR
	_offsets.append(Vector3(-width / 2.0, 0, length / 2.0))
	_offsets.append(Vector3(width / 2.0, 0, length / 2.0))
	_offsets.append(Vector3(-width / 2.0, 0, -length / 2.0))
	_offsets.append(Vector3(width / 2.0, 0, -length / 2.0))
	
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if managers.size() > 0:
		water_manager = managers[0]

func _physics_process(delta):
	if not water_manager: return

	var total_force_y = 0.0
	var avg_wave_height = 0.0
	var avg_normal = Vector3.ZERO
	
	# 1. 採樣 4 個點 (更穩定的做法：只使用 Y軸旋轉 (Yaw) 來計算採樣點，忽略船身傾斜)
	# 這樣即使船翻了，採樣點依然保持在水平面上撐住船
	var points_underwater = 0
	
	# 取得只包含 Yaw 的旋轉基底
	var yaw_rotation = Transform3D.IDENTITY.rotated(Vector3.UP, global_rotation.y)
	
	for offset in _offsets:
		# 使用平面的 offset (只旋轉 Yaw)
		var world_offset = yaw_rotation * offset
		var sampling_pos = global_position + world_offset
		
		# 讀取波浪高度
		var wave_h = water_manager.get_water_height_at(sampling_pos)
		
		# 這裡的 Depth 計算要用「船身該點的世界高度」來比對
		# 但為了更強的穩定性，我們假設這些點是「浮筒」，掛在船的水平面上
		# 如果要精確物理，要用 to_global(offset).y，但那樣會導致上述的翻船問題
		# 這裡我們採用「虛擬穩定浮筒」：
		# 浮筒高度 = 船中心高度 + 原始 Offset.y (通常是0)
		# 這樣船傾斜時，浮力會把它「拉」回水平
		
		# 修正：為了讓傾斜有回復力，我們需要知道「這點如果跟隨船傾斜亦會在哪」
		# 但為了防止採樣點重疊，Sampling Pos 維持水平展開。
		# 為了計算「入水深」，我们需要船上該點的真實高度。
		var real_point_world_pos = to_global(offset)
		var depth = wave_h - real_point_world_pos.y
		
		# 累積平均高度供後續計算
		avg_wave_height += wave_h
		
		if depth > 0:
			points_underwater += 1
			# 彈簧浮力： F = k * x
			var buoyancy = float_force * depth * 0.25
			total_force_y += buoyancy
	
	avg_wave_height /= 4.0
	
	# 2. 計算目標法線 (使用採樣點的波浪高度建構平面)
	# Sampling Pos 即使在船傾斜時也是展開的，所以 wave_normal 永遠是正確的水面法線
	var p_fl = global_position + (yaw_rotation * _offsets[0]); p_fl.y = water_manager.get_water_height_at(p_fl)
	var p_br = global_position + (yaw_rotation * _offsets[3]); p_br.y = water_manager.get_water_height_at(p_br)
	var p_fr = global_position + (yaw_rotation * _offsets[1]); p_fr.y = water_manager.get_water_height_at(p_fr)
	var p_bl = global_position + (yaw_rotation * _offsets[2]); p_bl.y = water_manager.get_water_height_at(p_bl)
	
	var diag1 = p_br - p_fl
	var diag2 = p_bl - p_fr
	var wave_normal = diag1.cross(diag2).normalized()
	if wave_normal.y < 0: wave_normal = - wave_normal
	
	# 3. 穩定施力與移動
	# 重力
	if points_underwater == 0:
		velocity.y -= 9.8 * delta
	else:
		velocity.y += total_force_y * delta
	
	# 阻尼 (使用新的 Delta 相關公式)
	var damp = clamp(1.0 - water_drag * delta, 0.0, 1.0)
	velocity.x *= damp
	velocity.z *= damp
	velocity.y *= damp # 垂直阻尼
	
	global_position += velocity * delta
	
	# 防止掉出世界
	if global_position.y < -50.0:
		global_position.y = -50.0
		velocity = Vector3.ZERO

	# 4. 旋轉對齊 (Tilt)
	# 將船的 Up 向量對齊到波浪法線
	var current_up = transform.basis.y
	var align_speed = 2.0 * delta
	
	# 根據是否有接觸水面決定旋轉速度
	if points_underwater > 0:
		var target_quat = Basis(transform.basis.get_rotation_quaternion()).slerp(Quaternion(Vector3.UP, wave_normal), align_speed * 2.0).get_rotation_quaternion()
		
		# 我們不想完全覆蓋 Yaw (Y 軸旋轉)，只調整 Pitch/Roll
		# 這是個簡易的 LookAt 變體
		var t_trans = Transform3D(transform.basis, global_position)
		t_trans.basis.y = wave_normal
		t_trans.basis.x = wave_normal.cross(t_trans.basis.z).normalized()
		t_trans.basis.z = t_trans.basis.x.cross(wave_normal).normalized()
		
		# Slerp Basis
		transform.basis = transform.basis.slerp(t_trans.basis, align_speed)
	
	# 5. 互動漣漪
	if gpu_local_ocean and velocity.length() > 0.5 and points_underwater > 0:
		gpu_local_ocean.add_interaction_world(global_position, ripple_radius, velocity.length() * ripple_strength * delta)

	# 6. Debug Visualization
	if debug_visuals:
		_draw_debug_points()

var _debug_mesh_instance: MeshInstance3D
var _debug_mesh: ImmediateMesh
@export var debug_visuals: bool = true

func _draw_debug_points():
	if not _debug_mesh_instance:
		_debug_mesh = ImmediateMesh.new()
		var mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		
		_debug_mesh_instance = MeshInstance3D.new()
		_debug_mesh_instance.mesh = _debug_mesh
		_debug_mesh_instance.material_override = mat
		_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh_instance)
		
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var yaw_rotation = Transform3D.IDENTITY.rotated(Vector3.UP, global_rotation.y)
	
	for offset in _offsets:
		var p_local = yaw_rotation * offset
		var p_world = global_position + p_local
		var h = water_manager.get_water_height_at(p_world)
		var p_water = Vector3(p_world.x, h, p_world.z)
		
		# Draw Line from Boat Point to Water Surface
		var real_world_pos = to_global(offset)
		var color = Color.RED if real_world_pos.y < h else Color.GREEN
		
		_debug_mesh.surface_set_color(color)
		_debug_mesh.surface_add_vertex(real_world_pos - global_position)
		_debug_mesh.surface_add_vertex(p_water - global_position)
		
		# Draw Marker at Water
		_debug_mesh.surface_set_color(Color.BLUE)
		_debug_mesh.surface_add_vertex(p_water - global_position + Vector3.UP * 0.2)
		_debug_mesh.surface_add_vertex(p_water - global_position - Vector3.UP * 0.2)
		
	_debug_mesh.surface_end()
