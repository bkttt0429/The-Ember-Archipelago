@tool
extends EditorScript

## 快速檢查 Shimmy 軌道
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib or not lib.has_animation("Shimmy_Left"):
		print("ERROR")
		return
	
	var anim = lib.get_animation("Shimmy_Left")
	print("=== Shimmy_Left 前 10 軌道 ===")
	for i in min(10, anim.get_track_count()):
		print("  [%02d] %s" % [i, str(anim.track_get_path(i))])
