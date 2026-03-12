@tool
extends EditorScript

## 修復 Shimmy_Right：使用 Shimmy_Left 的鏡像版本
## 這會把 Shimmy_Left 的 X 位移反轉來創建 Shimmy_Right

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== 修復 Shimmy_Right 動畫 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load animation library")
		return
	
	var left_anim = lib.get_animation("Shimmy_Left")
	if not left_anim:
		print("ERROR: Shimmy_Left not found")
		return
	
	# 複製 Shimmy_Left 作為新的 Shimmy_Right
	var right_anim = left_anim.duplicate(true) as Animation
	
	# 鏡像處理：反轉 Hips 的 X 位置
	for i in right_anim.get_track_count():
		var path = str(right_anim.track_get_path(i))
		var track_type = right_anim.track_get_type(i)
		
		# 只處理位置軌道
		if track_type == Animation.TYPE_POSITION_3D:
			if "Hips" in path:
				print("鏡像 Hips 位置軌道...")
				_mirror_position_track_x(right_anim, i)
	
	# 移除舊的 Shimmy_Right 並添加新的
	if lib.has_animation("Shimmy_Right"):
		lib.remove_animation("Shimmy_Right")
		print("移除舊的 Shimmy_Right")
	
	var err = lib.add_animation("Shimmy_Right", right_anim)
	if err != OK:
		print("ERROR: Failed to add animation: ", err)
		return
	
	# 保存
	err = ResourceSaver.save(lib, LIB_PATH)
	if err != OK:
		print("ERROR: Failed to save library: ", err)
		return
	
	# 驗證
	var verify_anim = lib.get_animation("Shimmy_Right")
	for i in verify_anim.get_track_count():
		var path = str(verify_anim.track_get_path(i))
		if "Hips" in path and verify_anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if verify_anim.track_get_key_count(i) >= 2:
				var first = verify_anim.track_get_key_value(i, 0)
				var last = verify_anim.track_get_key_value(i, verify_anim.track_get_key_count(i) - 1)
				var delta = last - first
				print("修復後 Shimmy_Right Hips 位移: X=%.3f" % delta.x)
	
	print("\n✅ Shimmy_Right 已修復！請重新加載場景測試")

## 鏡像位置軌道的 X 軸
func _mirror_position_track_x(anim: Animation, track_idx: int) -> void:
	var key_count = anim.track_get_key_count(track_idx)
	
	for k in key_count:
		var pos: Vector3 = anim.track_get_key_value(track_idx, k)
		pos.x = - pos.x # 反轉 X
		anim.track_set_key_value(track_idx, k, pos)
	
	print("  已反轉 %d 個關鍵幀的 X 值" % key_count)
