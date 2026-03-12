@tool
extends EditorScript

## 添加手臂 TwoBoneIK3D 節點
## 在 Godot Editor 中運行此腳本

const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"

func _run() -> void:
	print("\n=== 添加手臂 IK 節點 ===\n")
	
	# 獲取當前場景
	var editor = EditorInterface.get_edited_scene_root()
	if not editor:
		print("ERROR: No scene open")
		return
	
	# 找到骨架
	var skeleton: Skeleton3D = _find_node_by_type(editor, "Skeleton3D")
	if not skeleton:
		print("ERROR: Cannot find Skeleton3D")
		return
	
	print("找到骨架: ", skeleton.name)
	
	# 獲取骨骼索引
	var right_upper_arm_idx = skeleton.find_bone("RightUpperArm")
	var right_lower_arm_idx = skeleton.find_bone("RightLowerArm")
	var right_hand_idx = skeleton.find_bone("RightHand")
	
	var left_upper_arm_idx = skeleton.find_bone("LeftUpperArm")
	var left_lower_arm_idx = skeleton.find_bone("LeftLowerArm")
	var left_hand_idx = skeleton.find_bone("LeftHand")
	
	print("右臂骨骼: UpperArm=%d, LowerArm=%d, Hand=%d" % [right_upper_arm_idx, right_lower_arm_idx, right_hand_idx])
	print("左臂骨骼: UpperArm=%d, LowerArm=%d, Hand=%d" % [left_upper_arm_idx, left_lower_arm_idx, left_hand_idx])
	
	# 檢查是否已存在
	var existing_right = skeleton.get_node_or_null("RightArmIK")
	var existing_left = skeleton.get_node_or_null("LeftArmIK")
	
	if existing_right and existing_left:
		print("手臂 IK 節點已存在！")
		return
	
	# 創建右臂 IK
	if not existing_right and right_hand_idx >= 0:
		var right_ik = TwoBoneIK3D.new()
		right_ik.name = "RightArmIK"
		right_ik.root_bone_idx = right_upper_arm_idx
		right_ik.tip_bone_idx = right_hand_idx
		right_ik.override_tip_basis = true
		right_ik.interpolation = 0.0 # 初始關閉，代碼控制
		skeleton.add_child(right_ik)
		right_ik.owner = editor
		print("✅ 創建 RightArmIK")
		
		# 創建目標 Marker
		var right_target = Marker3D.new()
		right_target.name = "RightHandTarget"
		editor.add_child(right_target)
		right_target.owner = editor
		right_ik.target_node = right_ik.get_path_to(right_target)
		print("✅ 創建 RightHandTarget")
	
	# 創建左臂 IK
	if not existing_left and left_hand_idx >= 0:
		var left_ik = TwoBoneIK3D.new()
		left_ik.name = "LeftArmIK"
		left_ik.root_bone_idx = left_upper_arm_idx
		left_ik.tip_bone_idx = left_hand_idx
		left_ik.override_tip_basis = true
		left_ik.interpolation = 0.0 # 初始關閉
		skeleton.add_child(left_ik)
		left_ik.owner = editor
		print("✅ 創建 LeftArmIK")
		
		# 創建目標 Marker
		var left_target = Marker3D.new()
		left_target.name = "LeftHandTarget"
		editor.add_child(left_target)
		left_target.owner = editor
		left_ik.target_node = left_ik.get_path_to(left_target)
		print("✅ 創建 LeftHandTarget")
	
	print("\n=== 完成！請保存場景 (Ctrl+S) ===")

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_type(child, type_name)
		if result:
			return result
	return null
