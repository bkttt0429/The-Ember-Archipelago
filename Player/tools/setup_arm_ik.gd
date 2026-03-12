@tool
extends EditorScript

## 設置手部 TwoBoneIK3D 節點的骨骼配置

const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"

func _run() -> void:
	print("\n=== 設置手部 IK ===\n")
	
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
	
	# 列出所有骨骼
	print("骨架骨骼:")
	for i in skeleton.get_bone_count():
		var name = skeleton.get_bone_name(i)
		if "Arm" in name or "Hand" in name or "Shoulder" in name:
			print("  [%d] %s" % [i, name])
	
	# 查找手部 IK 節點
	var right_arm_ik: Node = null
	var left_arm_ik: Node = null
	
	for child in skeleton.get_children():
		if child.name == "RightArmIK":
			right_arm_ik = child
		elif child.name == "LeftArmIK":
			left_arm_ik = child
	
	if not right_arm_ik or not left_arm_ik:
		print("ERROR: Cannot find arm IK nodes")
		instance.queue_free()
		return
	
	print("\n找到 IK 節點:")
	print("  RightArmIK: ", right_arm_ik)
	print("  LeftArmIK: ", left_arm_ik)
	
	# 配置右手 IK
	# UpperArm -> LowerArm -> Hand
	var right_upper = skeleton.find_bone("RightUpperArm")
	var right_lower = skeleton.find_bone("RightLowerArm")
	var right_hand = skeleton.find_bone("RightHand")
	
	print("\n右手骨骼索引: upper=%d, lower=%d, hand=%d" % [right_upper, right_lower, right_hand])
	
	if right_upper >= 0 and right_lower >= 0 and right_hand >= 0:
		right_arm_ik.set("settings/0/root_bone_name", "RightUpperArm")
		right_arm_ik.set("settings/0/root_bone", right_upper)
		right_arm_ik.set("settings/0/middle_bone_name", "RightLowerArm")
		right_arm_ik.set("settings/0/middle_bone", right_lower)
		right_arm_ik.set("settings/0/end_bone_name", "RightHand")
		right_arm_ik.set("settings/0/end_bone", right_hand)
		right_arm_ik.set("settings/0/pole_direction", 2) # +Y 方向肘部
		print("  ✅ 已配置 RightArmIK")
	
	# 配置左手 IK
	var left_upper = skeleton.find_bone("LeftUpperArm")
	var left_lower = skeleton.find_bone("LeftLowerArm")
	var left_hand = skeleton.find_bone("LeftHand")
	
	print("左手骨骼索引: upper=%d, lower=%d, hand=%d" % [left_upper, left_lower, left_hand])
	
	if left_upper >= 0 and left_lower >= 0 and left_hand >= 0:
		left_arm_ik.set("settings/0/root_bone_name", "LeftUpperArm")
		left_arm_ik.set("settings/0/root_bone", left_upper)
		left_arm_ik.set("settings/0/middle_bone_name", "LeftLowerArm")
		left_arm_ik.set("settings/0/middle_bone", left_lower)
		left_arm_ik.set("settings/0/end_bone_name", "LeftHand")
		left_arm_ik.set("settings/0/end_bone", left_hand)
		left_arm_ik.set("settings/0/pole_direction", 2) # +Y 方向肘部
		print("  ✅ 已配置 LeftArmIK")
	
	# 保存場景
	var packed = PackedScene.new()
	var err = packed.pack(instance)
	if err != OK:
		print("ERROR: Failed to pack scene: ", err)
		instance.queue_free()
		return
	
	err = ResourceSaver.save(packed, SCENE_PATH)
	if err != OK:
		print("ERROR: Failed to save scene: ", err)
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
