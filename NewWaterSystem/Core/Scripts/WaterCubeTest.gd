extends RigidBody3D
## 水方塊測試腳本：掉入水面後融化並注入 SWE 質量 + 觸發可見漣漪

var water_manager: Node = null
var current_volume: float = 200.0
var initial_volume: float = 200.0
var is_melting: bool = false
var mesh_instance: MeshInstance3D
var _melt_log_timer: float = 0.0
var _ripple_timer: float = 0.0

func _ready() -> void:
	# 建立視覺方塊
	mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2, 2, 2)
	mesh_instance.mesh = box_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic = 0.1
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	
	# 建立碰撞體
	var collision = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(2, 2, 2)
	collision.shape = box_shape
	add_child(collision)
	
	# 尋找 WaterManager（場景中可能叫 OceanWaterManager）
	water_manager = get_tree().root.find_child("OceanWaterManager", true, false)
	if not water_manager:
		water_manager = get_tree().root.find_child("WaterManager", true, false)
	print("[WaterCube] 生成在: ", global_position, " WaterManager=", water_manager)

func _physics_process(delta: float) -> void:
	if not water_manager:
		water_manager = get_tree().root.find_child("OceanWaterManager", true, false)
		if not water_manager:
			water_manager = get_tree().root.find_child("WaterManager", true, false)
		if not water_manager:
			return
	
	if not is_melting:
		# 用 WaterManager 的 Y 作為海面高度
		var sea_height: float = water_manager.global_position.y
		
		if global_position.y < sea_height + 1.0:
			is_melting = true
			linear_velocity *= 0.05
			gravity_scale = 0.0
			print("[WaterCube] ★ 碰觸水面！Y=%.2f 海面=%.2f" % [global_position.y, sea_height])
			
			# ① SWE 質量注入（產生水面高度變化）
			if water_manager.has_method("trigger_water_injection"):
				water_manager.trigger_water_injection(global_position, 80.0, 5.0)
				print("[WaterCube]   → SWE 初始注入: strength=80, radius=5")
			
			# ② 普通 SWE 漣漪（凹陷衝擊）
			if water_manager.has_method("trigger_ripple"):
				water_manager.trigger_ripple(global_position, -8.0, 5.0)
				print("[WaterCube]   → SWE 衝擊漣漪: strength=-8, radius=5")
			
			# ③ ★ Analytic Ripple（這才是肉眼可見的主要漣漪系統！）
			_spawn_analytic_ripples(8, 1.5)
			print("[WaterCube]   → Analytic 漣漪: 8 個, strength=1.5")
	else:
		if current_volume <= 0.0:
			print("[WaterCube] 水量耗盡，銷毀方塊")
			queue_free()
			return
		
		# 融化並持續注入（2 秒融化完）
		var melt_rate = initial_volume / 2.0 * delta
		var injected = min(melt_rate, current_volume)
		current_volume -= injected
		
		# SWE 持續注入
		if water_manager.has_method("trigger_water_injection"):
			water_manager.trigger_water_injection(global_position, injected * 0.3, 3.0)
		
		# 持續產生 Analytic 漣漪（每 0.15 秒一波）
		_ripple_timer += delta
		if _ripple_timer > 0.15:
			_ripple_timer = 0.0
			_spawn_analytic_ripples(3, 0.8)
		
		# 視覺效果：方塊縮小
		var ratio = current_volume / initial_volume
		mesh_instance.scale = Vector3(ratio, ratio, ratio)
		
		# 每秒印一次融化進度
		_melt_log_timer += delta
		if _melt_log_timer > 1.0:
			_melt_log_timer = 0.0
			print("[WaterCube] 融化中... 剩餘: %.0f%%" % (ratio * 100))

## 產生多個 Analytic 漣漪（這是肉眼可見的圓環波紋系統）
func _spawn_analytic_ripples(count: int, strength: float) -> void:
	# 找到 WaterRippleSimulator（它是 WaterManager 的子節點）
	var sim = water_manager.find_child("RippleSimulator", false, false)
	if not sim:
		# 嘗試用 ripple_simulator 屬性
		if water_manager.has_method("get") and water_manager.get("ripple_simulator"):
			sim = water_manager.get("ripple_simulator")
	
	if sim and sim.has_method("add_ripple"):
		for i in range(count):
			# 在方塊周圍隨機偏移位置產生多個漣漪
			var offset = Vector3(
				randf_range(-1.5, 1.5),
				0,
				randf_range(-1.5, 1.5)
			)
			sim.add_ripple(global_position + offset, strength)
	else:
		# Fallback: 印警告
		if not has_meta("_ripple_warn"):
			set_meta("_ripple_warn", true)
			print("[WaterCube] ⚠ 找不到 RippleSimulator，無法產生可見漣漪")
