@tool
extends EditorScript

## 完全移除動畫中 Hips 的位置軌道（解決角色下沉問題）
## 用法：Ctrl+Shift+X 執行

const ANIM_NAMES = ["Run_To_Stop", "Stop_Walking"]
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	for anim_name in ANIM_NAMES:
		_remove_hips_position(lib, anim_name)
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== SUCCESS: Library saved! ===")
	else:
		print("ERROR saving: ", err)

func _remove_hips_position(lib: AnimationLibrary, anim_name: String) -> void:
	if not lib.has_animation(anim_name):
		print("SKIP: Animation not found: ", anim_name)
		return
	
	var anim = lib.get_animation(anim_name)
	print("\n--- Processing: ", anim_name, " ---")
	
	# 找出並刪除 Hips 位置軌道
	var tracks_to_remove: Array[int] = []
	
	for i in range(anim.get_track_count() - 1, -1, -1): # 倒序遍歷
		var path = str(anim.track_get_path(i))
		if path.contains("Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			print("  REMOVING track: ", path)
			tracks_to_remove.append(i)
	
	for idx in tracks_to_remove:
		anim.remove_track(idx)
	
	if tracks_to_remove.size() > 0:
		print("  Removed ", tracks_to_remove.size(), " Hips position track(s)")
	else:
		print("  No Hips position track found")
