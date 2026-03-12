@tool
extends EditorScript

## 列出 movement.res 中所有動畫名稱
## 用法：Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	print("=== Animations in movement.res ===")
	var names = lib.get_animation_list()
	for n in names:
		print("  - ", n)
	print("=== Total: ", names.size(), " animations ===")
