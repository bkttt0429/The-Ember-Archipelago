@tool
extends EditorScript

## 設置 TwoBoneIK3D（使用 Pole Node）
## 運行方式: 打開 Player.tscn，然後 File → Run

func _run() -> void:
	var edited_scene = EditorInterface.get_edited_scene_root()
	
	if not edited_scene:
		printerr("請先打開 Player.tscn 場景!")
		return
	
	var skeleton = edited_scene.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if not skeleton:
		printerr("找不到 GeneralSkeleton!")
		return
	
	var left_target = edited_scene.find_child("LeftFootTarget", true, false) as Marker3D
	var right_target = edited_scene.find_child("RightFootTarget", true, false) as Marker3D
	
	if not left_target or not right_target:
		printerr("找不到 LeftFootTarget 或 RightFootTarget!")
		return
	
	print("=== 設置 TwoBoneIK3D (使用 Pole Node) ===")
	
	# 移除舊的節點
	for node_name in ["LeftFootIK", "RightFootIK", "LeftKneePole", "RightKneePole"]:
		var old_node = skeleton.find_child(node_name, false, false)
		if old_node:
			print("移除: ", node_name)
			old_node.free()
		old_node = edited_scene.find_child(node_name, true, false)
		if old_node:
			print("移除: ", node_name)
			old_node.free()
	
	# ===== 創建 Pole Nodes（放在角色前方） =====
	var left_pole = Marker3D.new()
	left_pole.name = "LeftKneePole"
	edited_scene.add_child(left_pole)
	left_pole.owner = edited_scene
	left_pole.global_position = Vector3(-0.15, 0.5, 0.5) # 前方、膝蓋高度
	print("創建 LeftKneePole at ", left_pole.global_position)
	
	var right_pole = Marker3D.new()
	right_pole.name = "RightKneePole"
	edited_scene.add_child(right_pole)
	right_pole.owner = edited_scene
	right_pole.global_position = Vector3(0.15, 0.5, 0.5) # 前方、膝蓋高度
	print("創建 RightKneePole at ", right_pole.global_position)
	
	# ===== 設置左腳 IK =====
	var left_ik = TwoBoneIK3D.new()
	left_ik.name = "LeftFootIK"
	skeleton.add_child(left_ik)
	left_ik.owner = edited_scene
	
	# 關鍵！必須先設定 setting_count
	left_ik.setting_count = 1
	
	# 設置骨骼鏈
	left_ik.set_root_bone_name(0, "LeftUpperLeg")
	left_ik.set_middle_bone_name(0, "LeftLowerLeg")
	left_ik.set_end_bone_name(0, "LeftFoot")
	
	# 設置目標和極點節點
	left_ik.set_target_node(0, left_ik.get_path_to(left_target))
	left_ik.set_pole_node(0, left_ik.get_path_to(left_pole))
	
	print("✅ LeftFootIK 設置完成")
	print("   Target: ", left_ik.get_target_node(0))
	print("   Pole: ", left_ik.get_pole_node(0))
	
	# ===== 設置右腳 IK =====
	var right_ik = TwoBoneIK3D.new()
	right_ik.name = "RightFootIK"
	skeleton.add_child(right_ik)
	right_ik.owner = edited_scene
	
	right_ik.setting_count = 1
	
	right_ik.set_root_bone_name(0, "RightUpperLeg")
	right_ik.set_middle_bone_name(0, "RightLowerLeg")
	right_ik.set_end_bone_name(0, "RightFoot")
	
	right_ik.set_target_node(0, right_ik.get_path_to(right_target))
	right_ik.set_pole_node(0, right_ik.get_path_to(right_pole))
	
	print("✅ RightFootIK 設置完成")
	print("   Target: ", right_ik.get_target_node(0))
	print("   Pole: ", right_ik.get_pole_node(0))
	
	print("\n=== 設置完成! ===")
	print("1. 保存場景 (Ctrl+S)")
	print("2. 測試: 拖動 LeftFootTarget，腿應該會跟隨")
	print("3. 如果膝蓋方向錯誤，調整 LeftKneePole/RightKneePole 的位置")
