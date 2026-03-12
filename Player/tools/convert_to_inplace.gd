@tool
extends EditorScript

## 將動畫轉換為 In-Place (只移除水平位移，保留垂直運動)
## 用法：Ctrl+Shift+X 執行

const ANIM_NAMES = ["Run_To_Stop", "Stop_Walking"]
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	for anim_name in ANIM_NAMES:
		_convert_to_inplace(lib, anim_name)
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== SUCCESS: Library saved! ===")
	else:
		print("ERROR saving: ", err)

func _convert_to_inplace(lib: AnimationLibrary, anim_name: String) -> void:
	if not lib.has_animation(anim_name):
		print("SKIP: Animation not found: ", anim_name)
		return
	
	var anim = lib.get_animation(anim_name)
	print("\n--- Processing: ", anim_name, " ---")
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		
		# 只處理 Hips 的位置軌道
		if path.contains("Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			print("  Found Hips position: ", key_count, " keys")
			
			# 只清除 X 和 Z，完整保留 Y 軸！
			for key_idx in key_count:
				var old_pos = anim.track_get_key_value(i, key_idx) as Vector3
				var new_pos = Vector3(0, old_pos.y, 0) # 保留原始 Y 值
				anim.track_set_key_value(i, key_idx, new_pos)
			
			print("  Zeroed X/Z, kept Y intact!")
			return
	
	print("  WARNING: No Hips position track found")
