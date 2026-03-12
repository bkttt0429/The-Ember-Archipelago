@tool
extends EditorScript

## 比較 Shimmy_Left 和 Shimmy_Right 動畫內容

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== 比較 Shimmy 動畫 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load animation library")
		return
	
	var left_anim = lib.get_animation("Shimmy_Left")
	var right_anim = lib.get_animation("Shimmy_Right")
	
	if not left_anim:
		print("ERROR: Shimmy_Left not found")
		return
	if not right_anim:
		print("ERROR: Shimmy_Right not found")
		return
	
	print("Shimmy_Left: 長度=%.2fs, 軌道數=%d" % [left_anim.length, left_anim.get_track_count()])
	print("Shimmy_Right: 長度=%.2fs, 軌道數=%d" % [right_anim.length, right_anim.get_track_count()])
	
	# 檢查 Hips 位置軌道（這是最明顯的區別）
	print("\n=== 檢查 Hips 位置軌道 ===")
	_compare_hips_track(left_anim, right_anim)
	
	# 檢查動畫是否完全相同
	print("\n=== 快速比較 ===")
	var identical = true
	
	for i in left_anim.get_track_count():
		var left_path = str(left_anim.track_get_path(i))
		var left_type = left_anim.track_get_type(i)
		var left_keys = left_anim.track_get_key_count(i)
		
		# 找到對應的右邊軌道
		var right_idx = -1
		for j in right_anim.get_track_count():
			if str(right_anim.track_get_path(j)) == left_path:
				right_idx = j
				break
		
		if right_idx >= 0:
			var right_keys = right_anim.track_get_key_count(right_idx)
			if left_keys != right_keys:
				print("  軌道 %s: 幀數不同 (左=%d, 右=%d)" % [left_path, left_keys, right_keys])
				identical = false
			elif left_keys > 0:
				# 比較第一個關鍵幀
				var left_val = left_anim.track_get_key_value(i, 0)
				var right_val = right_anim.track_get_key_value(right_idx, 0)
				if str(left_val) != str(right_val):
					if "Hips" in left_path or "LeftHand" in left_path or "RightHand" in left_path:
						print("  軌道 %s: 值不同" % left_path)
						print("    左: %s" % str(left_val))
						print("    右: %s" % str(right_val))
					identical = false
	
	if identical:
		print("\n⚠️ 警告：兩個動畫內容完全相同！")
		print("   需要重新匯入正確的 Shimmy_Left 動畫")
	else:
		print("\n✅ 兩個動畫內容不同")
	
	print("\n✅ 比較完成")

func _compare_hips_track(left_anim: Animation, right_anim: Animation) -> void:
	for i in left_anim.get_track_count():
		var path = str(left_anim.track_get_path(i))
		if "Hips" in path and left_anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			print("  [左] Hips 位置軌道: ", path)
			if left_anim.track_get_key_count(i) >= 2:
				var first = left_anim.track_get_key_value(i, 0)
				var last = left_anim.track_get_key_value(i, left_anim.track_get_key_count(i) - 1)
				var delta = last - first
				print("    起點: %s" % first)
				print("    終點: %s" % last)
				print("    位移: X=%.3f, Y=%.3f, Z=%.3f" % [delta.x, delta.y, delta.z])
	
	for i in right_anim.get_track_count():
		var path = str(right_anim.track_get_path(i))
		if "Hips" in path and right_anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			print("  [右] Hips 位置軌道: ", path)
			if right_anim.track_get_key_count(i) >= 2:
				var first = right_anim.track_get_key_value(i, 0)
				var last = right_anim.track_get_key_value(i, right_anim.track_get_key_count(i) - 1)
				var delta = last - first
				print("    起點: %s" % first)
				print("    終點: %s" % last)
				print("    位移: X=%.3f, Y=%.3f, Z=%.3f" % [delta.x, delta.y, delta.z])
