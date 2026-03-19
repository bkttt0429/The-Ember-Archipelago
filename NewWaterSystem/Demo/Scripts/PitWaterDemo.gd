extends Node3D

## SWE 水物理視覺測試 — 兩角注水碰撞合併
## 使用正常海洋 shader + SWE fill mode alpha
## N = 一次性注水  R = 重置  左鍵 = 衝擊

@export var cam_speed: float = 12.0
@export var cam_rotate_speed: float = 0.003

var _wm: Node = null
var _cam: Camera3D
var _mouse_captured := false
var _yaw := 0.0
var _pitch := -35.0

func _ready():
	_cam = $"../Camera3D" if has_node("../Camera3D") else get_viewport().get_camera_3d()
	if _cam:
		_yaw = _cam.rotation_degrees.y
		_pitch = _cam.rotation_degrees.x
	
	# ★ 立即找 WaterManager 設 flag（在 WM 30-frame init 之前）
	var wm_nodes = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if wm_nodes.size() > 0:
		_wm = wm_nodes[0]
		_wm.skip_obstacle_bake = true
		_wm.use_lod = false
	
	await get_tree().create_timer(1.5).timeout
	
	if not _wm:
		wm_nodes = get_tree().get_nodes_in_group("WaterSystem_Managers")
		if wm_nodes.size() > 0:
			_wm = wm_nodes[0]
	
	if _wm:
		# 關閉 Gerstner + FFT，只留 SWE
		_wm.wind_strength = 0.0
		_wm.fft_scale = 0.0
		_wm.swe_strength = 1.5
		_wm.damping = 0.997
		if "debug_disable_waves" in _wm:
			_wm.debug_disable_waves = true
		
		# ★ 啟用 Fill Mode（用正常海洋 shader 的 alpha 漸變）
		_wm.swe_fill_mode = 1.0
		_wm.swe_fill_threshold = 0.02
		
		# 隱藏 OceanLOD
		var lod = _wm.get_node_or_null("OceanLOD")
		if lod: lod.visible = false
		
		# 確保 WaterPlane 可見（不替換材質！用原始海洋 shader）
		var wp = _wm.get_node_or_null("WaterPlane")
		if wp: wp.visible = true
		
		if _wm.has_method("_update_shader_parameters"):
			_wm._update_shader_parameters()
		
		if _wm.has_method("clear_obstacles"):
			_wm.clear_obstacles()
		
		print("[SWE-Test] Fill Mode ON（正常海洋 shader）")
		print("[SWE-Test] 按 N = 一次性兩角注水")

func _inject_pulse():
	if not _wm or not _wm.has_method("trigger_water_injection"):
		return
	var half = max(_wm.sea_size.x * 0.3, 1.0)
	for i in range(5):
		var offset = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		_wm.trigger_water_injection(_wm.global_position + Vector3(-half, 0, -half) + offset, 3.0, 3.0)
	for i in range(5):
		var offset = Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		_wm.trigger_water_injection(_wm.global_position + Vector3(half, 0, half) + offset, 3.0, 3.0)
	print("[SWE-Test] ▶ 脈衝注水完成")

func _process(delta):
	_update_camera(delta)

func _update_camera(delta):
	if not _cam: return
	var move_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move_dir.z -= 1
	if Input.is_key_pressed(KEY_S): move_dir.z += 1
	if Input.is_key_pressed(KEY_A): move_dir.x -= 1
	if Input.is_key_pressed(KEY_D): move_dir.x += 1
	if Input.is_key_pressed(KEY_Q): move_dir.y -= 1
	if Input.is_key_pressed(KEY_E): move_dir.y += 1
	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		var forward = -_cam.global_basis.z
		var right = _cam.global_basis.x
		_cam.global_position += (right * move_dir.x + Vector3.UP * move_dir.y + forward * move_dir.z) * cam_speed * delta

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_captured = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
	
	if event is InputEventMouseMotion and _mouse_captured:
		_yaw -= event.relative.x * cam_rotate_speed * 60.0
		_pitch -= event.relative.y * cam_rotate_speed * 60.0
		_pitch = clamp(_pitch, -89, 89)
		if _cam:
			_cam.rotation_degrees = Vector3(_pitch, _yaw, 0)
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_N:
				_inject_pulse()
			KEY_R:
				if _wm and _wm.has_method("clear_obstacles"):
					_wm.clear_obstacles()
				print("[SWE-Test] ■ 已重置")
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _mouse_captured and _wm:
			var cam = get_viewport().get_camera_3d()
			if cam:
				var from = cam.project_ray_origin(event.position)
				var dir = cam.project_ray_normal(event.position)
				if dir.y < -0.001:
					var t = -from.y / dir.y
					var hit = from + dir * t
					if _wm.has_method("trigger_water_injection"):
						_wm.trigger_water_injection(hit, 2.0, 2.0)

func _exit_tree():
	if _wm:
		_wm.swe_fill_mode = 0.0
		_wm.skip_obstacle_bake = false
		_wm.use_lod = true
		if _wm.has_method("_update_shader_parameters"):
			_wm._update_shader_parameters()
