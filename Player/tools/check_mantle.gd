@tool
extends EditorScript

## 檢查 Hang_To_Crouch 動畫軌道
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib or not lib.has_animation("Hang_To_Crouch"):
		print("ERROR: Hang_To_Crouch not found")
		return
	
	var anim = lib.get_animation("Hang_To_Crouch")
	print("=== Hang_To_Crouch 前 15 軌道 ===")
	for i in min(15, anim.get_track_count()):
		print("  [%02d] %s" % [i, str(anim.track_get_path(i))])
