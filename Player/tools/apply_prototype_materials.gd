@tool
extends EditorScript

## 批量套用 Kenney Prototype Textures 到測試場景
## 在編輯器中使用: File > Run (Ctrl+Shift+X)

func _run() -> void:
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		push_error("No scene open!")
		return
	
	# 載入材質
	var mat_dark = preload("res://Assets/Materials/Environment/prototype_dark.tres")
	var mat_orange = preload("res://Assets/Materials/Environment/prototype_orange.tres")
	var mat_green = preload("res://Assets/Materials/Environment/prototype_green.tres")
	var mat_blue = preload("res://Assets/Materials/Environment/prototype_blue.tres")
	
	var applied_count := 0
	
	# 套用到地面 - 使用深色
	var floor_mesh = _find_node_by_path(root, "Floor/FloorMesh")
	if floor_mesh:
		floor_mesh.material_override = mat_dark
		applied_count += 1
		print("✅ FloorMesh -> Dark")
	
	# 套用到障礙物 - 使用橙色
	var obstacle_mesh = _find_node_by_path(root, "Obstacle/ObstacleMesh")
	if obstacle_mesh:
		obstacle_mesh.material_override = mat_orange
		applied_count += 1
		print("✅ ObstacleMesh -> Orange")
	
	# 套用到斜坡 - 使用綠色
	var ramp_mesh = _find_node_by_path(root, "Ramp/RampMesh")
	if ramp_mesh:
		ramp_mesh.material_override = mat_green
		applied_count += 1
		print("✅ RampMesh -> Green")
	
	# 套用到平台 - 使用藍色
	var platform_mesh = _find_node_by_path(root, "Platform/PlatformMesh")
	if platform_mesh:
		platform_mesh.material_override = mat_blue
		applied_count += 1
		print("✅ PlatformMesh -> Blue")
	
	# 套用到樓梯 - 交替顏色
	var stair_mats = [mat_dark, mat_orange, mat_green, mat_blue]
	for i in range(1, 5):
		var step_mesh = _find_node_by_path(root, "Stairs/Step%d/Mesh" % i)
		if step_mesh:
			step_mesh.material_override = stair_mats[(i - 1) % 4]
			applied_count += 1
			print("✅ Step%d/Mesh -> %s" % [i, ["Dark", "Orange", "Green", "Blue"][(i - 1) % 4]])
	
	# 套用到攀爬箱 - 不同高度用不同顏色
	var climb_configs = [
		{"path": "ClimbBox_Low/MeshInstance3D", "mat": mat_green, "name": "Low"},
		{"path": "ClimbBox_Medium/MeshInstance3D", "mat": mat_orange, "name": "Medium"},
		{"path": "ClimbBox_High/MeshInstance3D", "mat": mat_blue, "name": "High"},
	]
	
	for config in climb_configs:
		var mesh = _find_node_by_path(root, config.path)
		if mesh:
			mesh.material_override = config.mat
			applied_count += 1
			print("✅ ClimbBox_%s -> %s" % [config.name, ["Green", "Orange", "Blue"][climb_configs.find(config)]])
	
	print("")
	print("===== 完成 =====")
	print("已套用材質到 %d 個物件" % applied_count)
	print("請按 Ctrl+S 儲存場景")

func _find_node_by_path(root: Node, path: String) -> Node:
	if root.has_node(path):
		return root.get_node(path)
	return null
