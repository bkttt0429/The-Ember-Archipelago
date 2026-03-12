@tool
extends EditorScript

## 把 Run_To_Stop 的 Hips Y 值對齊到 Idle 動畫
## 用法：Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	# 獲取 Idle 的 Hips Y 值（作為基準）
	var idle_y = _get_hips_y(lib, "Idle")
	if idle_y == null:
		print("ERROR: Could not get Idle Hips Y value")
		return
	
	print("=== Idle Hips Y: ", idle_y, " ===")
	
	# 顯示 Run_To_Stop 當前的 Y 值
	var rts_y = _get_hips_y(lib, "Run_To_Stop")
	if rts_y != null:
		print("=== Run_To_Stop Hips Y (current): ", rts_y, " ===")
		print("=== Difference: ", rts_y - idle_y, " ===")
	
	# 把 Run_To_Stop 的所有 Y 值設為 Idle 的 Y 值
	_set_hips_y(lib, "Run_To_Stop", idle_y)
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== SUCCESS: Library saved! ===")
	else:
		print("ERROR saving: ", err)

func _get_hips_y(lib: AnimationLibrary, anim_name: String) -> Variant:
	if not lib.has_animation(anim_name):
		print("SKIP: Animation not found: ", anim_name)
		return null
	
	var anim = lib.get_animation(anim_name)
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if path.contains("Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if anim.track_get_key_count(i) > 0:
				var pos = anim.track_get_key_value(i, 0) as Vector3
				return pos.y
	
	return null

func _set_hips_y(lib: AnimationLibrary, anim_name: String, target_y: float) -> void:
	if not lib.has_animation(anim_name):
		print("SKIP: Animation not found: ", anim_name)
		return
	
	var anim = lib.get_animation(anim_name)
	print("\n--- Setting ", anim_name, " Hips Y to: ", target_y, " ---")
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if path.contains("Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			
			for key_idx in key_count:
				var pos = anim.track_get_key_value(i, key_idx) as Vector3
				var new_pos = Vector3(pos.x, target_y, pos.z)
				anim.track_set_key_value(i, key_idx, new_pos)
			
			print("  Updated ", key_count, " keyframes")
			return
	
	print("  WARNING: No Hips position track found")
