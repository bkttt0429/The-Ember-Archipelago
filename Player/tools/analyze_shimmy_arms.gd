@tool
extends EditorScript

## 分析 Shimmy 動畫的手臂動作差異

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== 分析 Shimmy 手臂動作 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library")
		return
	
	var left_anim = lib.get_animation("Shimmy_Left")
	var right_anim = lib.get_animation("Shimmy_Right")
	
	if not left_anim or not right_anim:
		print("ERROR: Animations not found")
		return
	
	# 比較左右肩膀的第一個關鍵幀
	print("=== 比較肩膀動作 ===")
	
	var bones_to_check = ["LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm"]
	
	for bone_name in bones_to_check:
		print("\n骨骼: %s" % bone_name)
		_compare_bone_first_keys(left_anim, right_anim, bone_name)
	
	# 檢查所有軌道是否完全相同
	print("\n=== 軌道完全比對 ===")
	var identical_count = 0
	var different_count = 0
	
	for i in left_anim.get_track_count():
		var left_path = str(left_anim.track_get_path(i))
		
		# 找對應右邊軌道
		for j in right_anim.get_track_count():
			var right_path = str(right_anim.track_get_path(j))
			if left_path == right_path:
				if _are_tracks_identical(left_anim, i, right_anim, j):
					identical_count += 1
				else:
					different_count += 1
					# 只打印骨骼名稱不同的
					var bone = left_path.split(":")[-1] if ":" in left_path else left_path
					if "Shoulder" in bone or "Arm" in bone or "Hand" in bone:
						print("  不同: %s" % bone)
				break
	
	print("\n總結: 相同軌道=%d, 不同軌道=%d" % [identical_count, different_count])
	
	if identical_count > 30 and different_count < 5:
		print("\n⚠️ 警告: 大部分軌道相同！兩個動畫可能是同一個來源")

func _compare_bone_first_keys(left_anim: Animation, right_anim: Animation, bone_name: String) -> void:
	for i in left_anim.get_track_count():
		var path = str(left_anim.track_get_path(i))
		if bone_name in path and left_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var left_val = left_anim.track_get_key_value(i, 0) if left_anim.track_get_key_count(i) > 0 else null
			
			# 找右邊對應
			for j in right_anim.get_track_count():
				if str(right_anim.track_get_path(j)) == path:
					var right_val = right_anim.track_get_key_value(j, 0) if right_anim.track_get_key_count(j) > 0 else null
					
					if left_val and right_val:
						var diff = (left_val as Quaternion).angle_to(right_val as Quaternion)
						var status = "相同" if diff < 0.01 else "不同 (差異=%.3f rad)" % diff
						print("  旋轉(frame 0): %s" % status)
					break
			break

func _are_tracks_identical(anim1: Animation, idx1: int, anim2: Animation, idx2: int) -> bool:
	if anim1.track_get_key_count(idx1) != anim2.track_get_key_count(idx2):
		return false
	
	for k in anim1.track_get_key_count(idx1):
		var v1 = anim1.track_get_key_value(idx1, k)
		var v2 = anim2.track_get_key_value(idx2, k)
		if str(v1) != str(v2):
			return false
	
	return true
