@tool
extends EditorScript

## 設置手部 TwoBoneIK3D 節點 - 使用正確的 API

const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"

func _run() -> void:
	print("\n=== 設置手部 IK (v2) ===\n")
	
	var scene = load(SCENE_PATH) as PackedScene
	if not scene:
		print("ERROR: Cannot load scene")
		return
	
	var instance = scene.instantiate()
	var skeleton = _find_skeleton(instance)
	
	if not skeleton:
		print("ERROR: Cannot find skeleton")
		instance.queue_free()
		return
	
	# 查找手部 IK 節點
	var right_arm_ik: TwoBoneIK3D = null
	var left_arm_ik: TwoBoneIK3D = null
	
	for child in skeleton.get_children():
		if child.name == "RightArmIK" and child is TwoBoneIK3D:
			right_arm_ik = child as TwoBoneIK3D
		elif child.name == "LeftArmIK" and child is TwoBoneIK3D:
			left_arm_ik = child as TwoBoneIK3D
	
	if not right_arm_ik or not left_arm_ik:
		print("ERROR: Cannot find arm IK nodes")
		instance.queue_free()
		return
	
	print("找到 IK 節點")
	
	# 使用正確的 API 配置 TwoBoneIK3D
	# add_chain 會自動創建設置項
	
	# 右手配置
	var right_upper = skeleton.find_bone("RightUpperArm")
	var right_lower = skeleton.find_bone("RightLowerArm")
	var right_hand = skeleton.find_bone("RightHand")
	
	print("右手骨骼: upper=%d, lower=%d, hand=%d" % [right_upper, right_lower, right_hand])
	
	if right_upper >= 0 and right_lower >= 0 and right_hand >= 0:
		# 清除現有設置
		while right_arm_ik.get_chain_count() > 0:
			right_arm_ik.delete_setting(0)
		
		# 添加新的 IK 鏈
		right_arm_ik.add_chain(
			"RightUpperArm", # root bone name
			right_upper, # root bone index
			"RightLowerArm", # middle bone name
			right_lower, # middle bone index
			0, # pole direction (0 = default)
			"RightHand", # end bone name
			right_hand, # end bone index
			false, # use virtual end
			false # extend end bone
		)
		print("✅ RightArmIK 已配置")
	
	# 左手配置
	var left_upper = skeleton.find_bone("LeftUpperArm")
	var left_lower = skeleton.find_bone("LeftLowerArm")
	var left_hand = skeleton.find_bone("LeftHand")
	
	print("左手骨骼: upper=%d, lower=%d, hand=%d" % [left_upper, left_lower, left_hand])
	
	if left_upper >= 0 and left_lower >= 0 and left_hand >= 0:
		while left_arm_ik.get_chain_count() > 0:
			left_arm_ik.delete_setting(0)
		
		left_arm_ik.add_chain(
			"LeftUpperArm",
			left_upper,
			"LeftLowerArm",
			left_lower,
			0,
			"LeftHand",
			left_hand,
			false,
			false
		)
		print("✅ LeftArmIK 已配置")
	
	# 保存場景
	var packed = PackedScene.new()
	var err = packed.pack(instance)
	if err != OK:
		print("ERROR: Failed to pack scene")
		instance.queue_free()
		return
	
	err = ResourceSaver.save(packed, SCENE_PATH)
	if err != OK:
		print("ERROR: Failed to save scene")
		instance.queue_free()
		return
	
	print("\n✅ 手部 IK 配置完成！請重新加載場景")
	instance.queue_free()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
