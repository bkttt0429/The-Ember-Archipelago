@tool
extends EditorScript

## 移除所有動畫中的 Method Track（解決 on_foot_left/right 錯誤）
## 用法：Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	print("\n=== Removing ALL Method Tracks ===")
	
	var count = 0
	for anim_name in lib.get_animation_list():
		var anim = lib.get_animation(anim_name)
		
		# 從後往前刪除以避免索引問題
		for i in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_type(i) == Animation.TYPE_METHOD:
				anim.remove_track(i)
				print("  REMOVED from: ", anim_name)
				count += 1
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== Removed ", count, " method tracks ===")
	else:
		print("ERROR saving: ", err)
