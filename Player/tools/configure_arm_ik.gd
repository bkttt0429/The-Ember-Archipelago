@tool
extends EditorScript

## 配置手臂 TwoBoneIK3D 節點的骨骼設置
## 運行方式：在編輯器中按 Ctrl+Shift+X
## 
## 使用 add_chain() 方法正確初始化 settings 陣列

func _run() -> void:
	print("\n=== 配置手臂 IK (add_chain 方法) ===\n")
	
	var editor = EditorInterface
	var scene = editor.get_edited_scene_root()
	
	if not scene:
		printerr("沒有打開的場景")
		return
	
	# 查找 Skeleton3D
	var skeleton = _find_node_by_type(scene, "Skeleton3D")
	if not skeleton:
		printerr("找不到 Skeleton3D")
		return
	
	print("骨架: ", skeleton.name)
	_list_arm_bones(skeleton)
	
	# 查找並配置 RightArmIK
	var right_arm_ik = skeleton.get_node_or_null("RightArmIK")
	if right_arm_ik and right_arm_ik is TwoBoneIK3D:
		print("\n找到 RightArmIK - 正在配置...")
		_configure_arm_ik(right_arm_ik, skeleton, "Right", scene)
	else:
		print("\n警告: 找不到 RightArmIK，將創建...")
		right_arm_ik = TwoBoneIK3D.new()
		right_arm_ik.name = "RightArmIK"
		skeleton.add_child(right_arm_ik)
		right_arm_ik.owner = scene
		_configure_arm_ik(right_arm_ik, skeleton, "Right", scene)
	
	# 查找並配置 LeftArmIK
	var left_arm_ik = skeleton.get_node_or_null("LeftArmIK")
	if left_arm_ik and left_arm_ik is TwoBoneIK3D:
		print("\n找到 LeftArmIK - 正在配置...")
		_configure_arm_ik(left_arm_ik, skeleton, "Left", scene)
	else:
		print("\n警告: 找不到 LeftArmIK，將創建...")
		left_arm_ik = TwoBoneIK3D.new()
		left_arm_ik.name = "LeftArmIK"
		skeleton.add_child(left_arm_ik)
		left_arm_ik.owner = scene
		_configure_arm_ik(left_arm_ik, skeleton, "Left", scene)
	
	print("\n=== 完成！請按 Ctrl+S 保存場景 ===")

func _configure_arm_ik(ik_node: TwoBoneIK3D, skeleton: Skeleton3D, side: String, scene_root: Node) -> void:
	# 骨骼名稱
	var upper_name = side + "UpperArm"
	var lower_name = side + "LowerArm"
	var hand_name = side + "Hand"
	
	# 查找骨骼索引
	var upper_idx = skeleton.find_bone(upper_name)
	var lower_idx = skeleton.find_bone(lower_name)
	var hand_idx = skeleton.find_bone(hand_name)
	
	print("  %s 骨骼索引: Upper=%d, Lower=%d, Hand=%d" % [side, upper_idx, lower_idx, hand_idx])
	
	if upper_idx == -1 or lower_idx == -1 or hand_idx == -1:
		printerr("  錯誤: 找不到 %s 的骨骼" % side)
		return
	
	# 清除現有的 chains（如果 API 支援）
	# 注意：有些版本可能不支援 get_chain_count
	var chain_count = 0
	if ik_node.has_method("get_chain_count"):
		chain_count = ik_node.get_chain_count()
		print("  現有 chain 數量: %d" % chain_count)
		# 移除現有 chains
		while ik_node.get_chain_count() > 0:
			ik_node.remove_chain(0)
	else:
		print("  注意: 此版本不支援 get_chain_count，嘗試直接 add_chain")
	
	# 使用 add_chain 方法添加骨骼鏈
	# add_chain(root_bone_name, root_bone_index, middle_bone_name, middle_bone_index,
	#           pole_direction, end_bone_name, end_bone_index, use_virtual_end, extend_end_bone)
	if ik_node.has_method("add_chain"):
		print("  正在使用 add_chain 方法...")
		ik_node.add_chain(
			upper_name, # root_bone_name
			upper_idx, # root_bone
			lower_name, # middle_bone_name
			lower_idx, # middle_bone
			2, # pole_direction (+Y = 2 for elbow pointing backward)
			hand_name, # end_bone_name
			hand_idx, # end_bone
			false, # use_virtual_end
			false # extend_end_bone
		)
		print("  ✓ 已使用 add_chain 配置 %sArmIK" % side)
	else:
		# 備用方案：直接設置屬性（可能不適用於所有版本）
		printerr("  錯誤: add_chain 方法不可用")
		return
	
	# 設置 active 為 true（確保 IK 啟用）
	ik_node.active = true
	
	# 設置初始 influence 為 0（由代碼動態控制）
	ik_node.influence = 0.0
	
	print("  ✓ %sArmIK 配置完成 (active=%s, influence=%.1f)" % [side, ik_node.active, ik_node.influence])

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_type(child, type_name)
		if result:
			return result
	return null

func _list_arm_bones(skeleton: Skeleton3D) -> void:
	print("\n手臂相關骨骼列表:")
	for i in range(skeleton.get_bone_count()):
		var name = skeleton.get_bone_name(i)
		if "Arm" in name or "arm" in name or "Hand" in name or "hand" in name or "Upper" in name or "Lower" in name:
			print("  [%d] %s" % [i, name])
