@tool
extends EditorScript

## 分析 Hanging_Idle 動畫中的手部骨骼位置
## 這會播放動畫並讀取手部骨骼的實際世界位置

const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== 分析 Hanging_Idle 動畫手部位置 ===\n")
	
	# 載入場景
	var scene = load(SCENE_PATH) as PackedScene
	if not scene:
		print("ERROR: Cannot load scene")
		return
	
	var instance = scene.instantiate()
	
	# 找到骨架和動畫播放器
	var skeleton: Skeleton3D = _find_node_by_type(instance, "Skeleton3D")
	var anim_player: AnimationPlayer = _find_node_by_type(instance, "AnimationPlayer")
	
	if not skeleton:
		print("ERROR: Cannot find skeleton")
		instance.queue_free()
		return
	
	if not anim_player:
		print("ERROR: Cannot find AnimationPlayer")
		instance.queue_free()
		return
	
	print("找到骨架: ", skeleton.name)
	print("找到 AnimationPlayer: ", anim_player.name)
	
	# 找到骨骼索引
	var hips_idx = skeleton.find_bone("Hips")
	var left_hand_idx = skeleton.find_bone("LeftHand")
	var right_hand_idx = skeleton.find_bone("RightHand")
	
	print("\n骨骼索引: Hips=%d, LeftHand=%d, RightHand=%d" % [hips_idx, left_hand_idx, right_hand_idx])
	
	# 載入動畫庫並找到 Hanging_Idle
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib or not lib.has_animation("Hanging_Idle"):
		print("ERROR: Cannot find Hanging_Idle animation")
		instance.queue_free()
		return
	
	var anim = lib.get_animation("Hanging_Idle")
	print("動畫長度: %.2f 秒, 幀數: %d" % [anim.length, anim.get_track_count()])
	
	# 方法 1: 直接從動畫軌道讀取 Hips 位置
	print("\n=== 方法 1: 動畫軌道分析 ===")
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		var track_type = anim.track_get_type(i)
		
		if "Hips" in path and track_type == Animation.TYPE_POSITION_3D:
			print("找到 Hips 位置軌道: ", path)
			# 讀取第一個關鍵幀的值
			if anim.track_get_key_count(i) > 0:
				var pos = anim.track_get_key_value(i, 0)
				print("  第一幀 Hips 位置: ", pos)
				print("  Y 偏移（從原點）: %.3fm" % pos.y)
		
		if "LeftHand" in path and track_type == Animation.TYPE_ROTATION_3D:
			print("找到 LeftHand 旋轉軌道: ", path)
		if "RightHand" in path and track_type == Animation.TYPE_ROTATION_3D:
			print("找到 RightHand 旋轉軌道: ", path)
	
	# 方法 2: 播放動畫並讀取骨骼位置
	print("\n=== 方法 2: 模擬骨骼姿態 ===")
	
	# 手動應用動畫第一幀到骨架
	_apply_animation_frame(anim, skeleton, 0.0)
	
	# 讀取骨骼全域位置
	var hips_global = skeleton.get_bone_global_pose(hips_idx)
	var left_hand_global = skeleton.get_bone_global_pose(left_hand_idx)
	var right_hand_global = skeleton.get_bone_global_pose(right_hand_idx)
	
	print("Hips 全域位置: ", hips_global.origin)
	print("LeftHand 全域位置: ", left_hand_global.origin)
	print("RightHand 全域位置: ", right_hand_global.origin)
	
	# 計算手到 Hips 的距離
	var left_hand_offset = left_hand_global.origin - hips_global.origin
	var right_hand_offset = right_hand_global.origin - hips_global.origin
	
	print("\n=== 手部相對於 Hips 的偏移 ===")
	print("LeftHand - Hips: ", left_hand_offset)
	print("  Y 距離: %.3fm" % left_hand_offset.y)
	print("RightHand - Hips: ", right_hand_offset)
	print("  Y 距離: %.3fm" % right_hand_offset.y)
	
	var avg_hand_above_hips = (left_hand_offset.y + right_hand_offset.y) / 2.0
	print("\n=== 結論 ===")
	print("手高於 Hips 平均距離: %.3fm" % avg_hand_above_hips)
	print("Hips 在模型中的高度: %.3fm" % hips_global.origin.y)
	print("手在模型中的平均高度: %.3fm" % ((left_hand_global.origin.y + right_hand_global.origin.y) / 2.0))
	
	# 建議的偏移值
	# 角色腳在 Y=0，如果手在 grab_point，角色應該在 grab_point.y - hand_height
	var hand_height = (left_hand_global.origin.y + right_hand_global.origin.y) / 2.0
	print("\n★ 建議的 grab_point.y 偏移: %.2fm" % hand_height)
	print("（這是手到腳的距離）")
	
	instance.queue_free()
	print("\n✅ 分析完成")

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_type(child, type_name)
		if result:
			return result
	return null

## 手動應用動畫幀到骨架
func _apply_animation_frame(anim: Animation, skeleton: Skeleton3D, time: float) -> void:
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var bone_name = _extract_bone_name(str(path))
		if bone_name.is_empty():
			continue
		
		var bone_idx = skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		
		var track_type = anim.track_get_type(i)
		
		if track_type == Animation.TYPE_POSITION_3D:
			var pos = anim.position_track_interpolate(i, time)
			var pose = skeleton.get_bone_pose(bone_idx)
			pose.origin = pos
			skeleton.set_bone_pose(bone_idx, pose)
		elif track_type == Animation.TYPE_ROTATION_3D:
			var rot = anim.rotation_track_interpolate(i, time)
			var pose = skeleton.get_bone_pose(bone_idx)
			pose.basis = Basis(rot)
			skeleton.set_bone_pose(bone_idx, pose)

func _extract_bone_name(path: String) -> String:
	# 從路徑 "%GeneralSkeleton:Hips" 提取 "Hips"
	var colon_pos = path.find(":")
	if colon_pos >= 0:
		return path.substr(colon_pos + 1)
	return ""
