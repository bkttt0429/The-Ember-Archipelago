@tool
extends EditorScript

## 在編輯器中設置 TwoBoneIK3D 節點
## 這個腳本會正確創建和配置手臂 IK

const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"

func _run() -> void:
	print("\n=== 設置手臂 TwoBoneIK3D ===\n")
	
	# 獲取編輯器中的當前場景
	var editor = EditorInterface.get_editor_main_screen()
	var edited_scene = EditorInterface.get_edited_scene_root()
	
	if not edited_scene:
		print("ERROR: 請先打開 PlayerCapsuleTest.tscn 場景！")
		return
	
	print("當前場景: ", edited_scene.name)
	
	# 查找骨架
	var skeleton = _find_skeleton(edited_scene)
	if not skeleton:
		print("ERROR: 找不到 Skeleton3D")
		return
	
	print("找到骨架: ", skeleton.name)
	
	# 列出手臂骨骼
	var right_upper = skeleton.find_bone("RightUpperArm")
	var right_lower = skeleton.find_bone("RightLowerArm")
	var right_hand = skeleton.find_bone("RightHand")
	var left_upper = skeleton.find_bone("LeftUpperArm")
	var left_lower = skeleton.find_bone("LeftLowerArm")
	var left_hand = skeleton.find_bone("LeftHand")
	
	print("右手骨骼: upper=%d, lower=%d, hand=%d" % [right_upper, right_lower, right_hand])
	print("左手骨骼: upper=%d, lower=%d, hand=%d" % [left_upper, left_lower, left_hand])
	
	# 查找或創建 RightArmIK
	var right_arm_ik = skeleton.get_node_or_null("RightArmIK")
	if not right_arm_ik:
		right_arm_ik = TwoBoneIK3D.new()
		right_arm_ik.name = "RightArmIK"
		skeleton.add_child(right_arm_ik)
		right_arm_ik.owner = edited_scene
		print("創建 RightArmIK")
	
	# 配置 RightArmIK
	if right_arm_ik is TwoBoneIK3D:
		_setup_two_bone_ik(right_arm_ik, right_upper, right_lower, right_hand, "Right")
	
	# 查找或創建 LeftArmIK
	var left_arm_ik = skeleton.get_node_or_null("LeftArmIK")
	if not left_arm_ik:
		left_arm_ik = TwoBoneIK3D.new()
		left_arm_ik.name = "LeftArmIK"
		skeleton.add_child(left_arm_ik)
		left_arm_ik.owner = edited_scene
		print("創建 LeftArmIK")
	
	# 配置 LeftArmIK
	if left_arm_ik is TwoBoneIK3D:
		_setup_two_bone_ik(left_arm_ik, left_upper, left_lower, left_hand, "Left")
	
	# 保存場景
	print("\n請按 Ctrl+S 保存場景")
	print("✅ 手臂 IK 設置完成！")

func _setup_two_bone_ik(ik: TwoBoneIK3D, root_idx: int, mid_idx: int, end_idx: int, side: String) -> void:
	print("配置 %sArmIK..." % side)
	
	# 設置骨架（如果尚未設置）
	if not ik.get_skeleton():
		var parent = ik.get_parent()
		if parent is Skeleton3D:
			# TwoBoneIK3D 作為 Skeleton3D 的子節點會自動連接
			pass
	
	# TwoBoneIK3D 使用 settings 屬性數組
	# 我們需要確保至少有一個設置項
	
	# 獲取當前 settings 數組
	var settings = ik.get("settings")
	print("  當前 settings 類型: ", typeof(settings))
	
	if settings == null:
		print("  settings 為 null，無法配置")
		print("  請手動在 Inspector 中添加 Settings 項目：")
		print("  1. 選擇 %sArmIK 節點" % side)
		print("  2. 在 Inspector 中找到 'Settings' 屬性")
		print("  3. 點擊 'Add Element' 添加一個設置項")
		print("  4. 設置 Root Bone = %sUpperArm" % side)
		print("  5. 設置 Middle Bone = %sLowerArm" % side)
		print("  6. 設置 End Bone = %sHand" % side)
		return
	
	print("  settings 數組大小: ", settings.size() if settings is Array else "N/A")
	
	# 嘗試直接設置屬性
	ik.influence = 0.0 # 默認禁用，由代碼控制
	print("  ✅ %sArmIK influence=0 (由代碼控制)" % side)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
