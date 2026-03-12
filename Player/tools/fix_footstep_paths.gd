@tool
extends EditorScript

## 修正腳步事件的路徑 - 使用 ".." 指向父節點（CharacterBody3D）
## 用法：Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	print("\n=== Fixing Footstep Track Paths ===")
	
	var count = 0
	for anim_name in lib.get_animation_list():
		var anim = lib.get_animation(anim_name)
		
		for i in range(anim.get_track_count() - 1, -1, -1):
			var track_type = anim.track_get_type(i)
			if track_type == Animation.TYPE_METHOD:
				var path = str(anim.track_get_path(i))
				if path == ".":
					# 刪除舊的錯誤軌道
					anim.remove_track(i)
					print("  REMOVED old track from: ", anim_name)
					count += 1
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== Removed ", count, " old method tracks ===")
		print("Now run add_footstep_events_v2.gd to add correct tracks")
	else:
		print("ERROR saving: ", err)
