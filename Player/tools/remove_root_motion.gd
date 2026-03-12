@tool
extends EditorScript

## 移除動畫中的 Root Motion (歸零所有 Hips 位置)
## 運行方式: Godot Editor → Script → Run (Ctrl+Shift+X)

func _run() -> void:
	print("=== 移除 Root Motion (全部歸零) ===")
	
	var lib_path = "res://Player/animations/movement.res"
	var lib = load(lib_path) as AnimationLibrary
	if not lib:
		push_error("找不到 AnimationLibrary: " + lib_path)
		return
	
	# 要處理的動畫列表
	var anims_to_fix = [
		"Hang_To_Crouch",
		"Hang_Drop",
	]
	
	for anim_name in anims_to_fix:
		if not lib.has_animation(anim_name):
			print("跳過 (不存在): ", anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		print("處理動畫: ", anim_name)
		
		for i in range(anim.get_track_count()):
			var path = str(anim.track_get_path(i))
			var track_type = anim.track_get_type(i)
			
			# 尋找 Hips 的位置軌道
			if "Hips" in path and track_type == Animation.TYPE_POSITION_3D:
				var key_count = anim.track_get_key_count(i)
				print("  找到: ", path, " (", key_count, " 幀)")
				
				# 將所有關鍵幀位置設為 (0, 0, 0)
				for key_idx in range(key_count):
					var old_val = anim.track_get_key_value(i, key_idx)
					anim.track_set_key_value(i, key_idx, Vector3.ZERO)
				
				print("  → 已歸零!")
	
	# 儲存
	var result = ResourceSaver.save(lib, lib_path)
	if result == OK:
		print("=== 已儲存! 請重新載入場景測試 ===")
	else:
		push_error("儲存失敗!")
