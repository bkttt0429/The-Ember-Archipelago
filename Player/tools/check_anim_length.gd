@tool
extends EditorScript

## 檢查動畫長度
## Script > Run

const LIBRARY_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("=== 檢查動畫長度 ===")
	
	var lib = ResourceLoader.load(LIBRARY_PATH) as AnimationLibrary
	if lib == null:
		print("❌ 無法載入 library")
		return
	
	var anims_to_check = [
		"Jump_Standing",
		"Jump_Standing_Alt",
		"Jump_Backward",
		"Jump_ToStage",
		"Jump_Running",
		"Fall_Loop1",
		"Hard_Land"
	]
	
	print("動畫 | 長度(秒)")
	print("-".repeat(30))
	
	for anim_name in anims_to_check:
		if lib.has_animation(anim_name):
			var anim = lib.get_animation(anim_name)
			print("%s | %.2fs" % [anim_name, anim.length])
		else:
			print("%s | 不存在" % anim_name)
