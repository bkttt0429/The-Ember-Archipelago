extends Node3D

## SWE 測試控制器 — 可掛在任何有 WaterManager 的場景
## N = 注水脈衝  R = 重置  左鍵 = 點擊衝擊  G = 大量注水壓力測試

var _wm: Node = null

func _ready():
	await get_tree().create_timer(1.0).timeout
	var wm_nodes = get_tree().get_nodes_in_group("WaterSystem_Managers")
	if wm_nodes.size() > 0:
		_wm = wm_nodes[0]
		print("[SWE-Test] ✓ WaterManager found: ", _wm.name)
		print("[SWE-Test] 按鍵: N=注水 | R=重置 | G=壓力測試 | 左鍵=衝擊")
	else:
		print("[SWE-Test] ✗ No WaterManager found!")

func _unhandled_input(event):
	if not _wm: return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_N:
				_inject_pulse()
			KEY_R:
				if _wm.has_method("clear_obstacles"):
					_wm.clear_obstacles()
				print("[SWE-Test] ■ 已重置")
			KEY_G:
				_stress_test()
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam = get_viewport().get_camera_3d()
		if cam and _wm.has_method("trigger_water_injection"):
			var from = cam.project_ray_origin(event.position)
			var dir = cam.project_ray_normal(event.position)
			if dir.y < -0.001:
				var t = -from.y / dir.y
				var hit = from + dir * t
				_wm.trigger_water_injection(hit, 3.0, 2.5)
				print("[SWE-Test] ▶ 衝擊 @ ", hit)

func _inject_pulse():
	if not _wm or not _wm.has_method("trigger_water_injection"):
		return
	var half = max(_wm.sea_size.x * 0.2, 2.0)
	var center = _wm.global_position
	for i in range(5):
		var offset = Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		_wm.trigger_water_injection(center + Vector3(-half, 0, -half) + offset, 3.0, 3.0)
	for i in range(5):
		var offset = Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		_wm.trigger_water_injection(center + Vector3(half, 0, half) + offset, 3.0, 3.0)
	print("[SWE-Test] ▶ 兩角注水脈衝")

func _stress_test():
	if not _wm or not _wm.has_method("trigger_water_injection"):
		return
	var center = _wm.global_position
	for i in range(20):
		var pos = center + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		_wm.trigger_water_injection(pos, 8.0, 4.0)
	print("[SWE-Test] ▶ 壓力測試：20 點高強度注水 (CFL 應防爆)")
