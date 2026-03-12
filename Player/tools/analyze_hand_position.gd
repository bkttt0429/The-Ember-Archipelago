@tool
extends EditorScript

## 分析 Hanging_Idle 動畫中手部骨骼位置
## 這會幫助我們計算正確的懸掛高度偏移

const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== 分析手部骨骼位置 ===\n")
	
	# 載入場景
	var scene = load(SCENE_PATH) as PackedScene
	if not scene:
		print("ERROR: Cannot load scene")
		return
	
	var instance = scene.instantiate()
	
	# 找到骨架
	var skeleton: Skeleton3D = _find_skeleton(instance)
	if not skeleton:
		print("ERROR: Cannot find skeleton")
		instance.queue_free()
		return
	
	print("找到骨架: ", skeleton.name)
	print("骨骼數量: ", skeleton.get_bone_count())
	
	# 找到關鍵骨骼索引
	var hips_idx = skeleton.find_bone("Hips")
	var left_hand_idx = skeleton.find_bone("LeftHand")
	var right_hand_idx = skeleton.find_bone("RightHand")
	
	print("\n骨骼索引:")
	print("  Hips: ", hips_idx)
	print("  LeftHand: ", left_hand_idx)
	print("  RightHand: ", right_hand_idx)
	
	if hips_idx < 0 or left_hand_idx < 0 or right_hand_idx < 0:
		print("ERROR: Missing bones")
		instance.queue_free()
		return
	
	# 載入動畫庫
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib or not lib.has_animation("Hanging_Idle"):
		print("ERROR: Cannot find Hanging_Idle animation")
		instance.queue_free()
		return
	
	var anim = lib.get_animation("Hanging_Idle")
	
	# 尋找 Hips 位置軌道
	var hips_pos_track = -1
	var left_hand_rot_track = -1
	var right_hand_rot_track = -1
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			hips_pos_track = i
			print("\n找到 Hips 位置軌道: ", path)
		elif "LeftHand" in path:
			print("找到 LeftHand 軌道: ", path, " (類型: ", anim.track_get_type(i), ")")
		elif "RightHand" in path:
			print("找到 RightHand 軌道: ", path, " (類型: ", anim.track_get_type(i), ")")
	
	# 獲取休息姿勢下的骨骼位置
	print("\n=== 休息姿勢骨骼位置 ===")
	var hips_rest = skeleton.get_bone_rest(hips_idx)
	var left_hand_rest = skeleton.get_bone_rest(left_hand_idx)
	var right_hand_rest = skeleton.get_bone_rest(right_hand_idx)
	
	print("Hips rest origin: ", hips_rest.origin)
	print("LeftHand rest origin: ", left_hand_rest.origin)
	print("RightHand rest origin: ", right_hand_rest.origin)
	
	# 計算全域位置（通過骨骼鏈）
	print("\n=== 全域骨骼位置 (通過 get_bone_global_pose) ===")
	var hips_global = skeleton.get_bone_global_pose(hips_idx)
	var left_hand_global = skeleton.get_bone_global_pose(left_hand_idx)
	var right_hand_global = skeleton.get_bone_global_pose(right_hand_idx)
	
	print("Hips global: ", hips_global.origin)
	print("LeftHand global: ", left_hand_global.origin)
	print("RightHand global: ", right_hand_global.origin)
	
	# 計算手到 Hips 的垂直距離
	var left_hand_to_hips = left_hand_global.origin.y - hips_global.origin.y
	var right_hand_to_hips = right_hand_global.origin.y - hips_global.origin.y
	
	print("\n=== 手到 Hips 的垂直距離 ===")
	print("LeftHand - Hips (Y): ", left_hand_to_hips, "m")
	print("RightHand - Hips (Y): ", right_hand_to_hips, "m")
	print("平均值: ", (left_hand_to_hips + right_hand_to_hips) / 2, "m")
	
	# 建議的偏移值
	var avg_hand_height = (left_hand_to_hips + right_hand_to_hips) / 2
	print("\n=== 建議 ===")
	print("手到 Hips 距離: %.2fm" % avg_hand_height)
	print("腳到 Hips 距離 (假設): 約 0.9m")
	print("建議 grab_point.y 偏移: %.2fm (手到腳)" % (avg_hand_height + 0.9))
	
	instance.queue_free()
	print("\n✅ 分析完成")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
