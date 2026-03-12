@tool
extends EditorScript

# 列出動畫庫中的所有動畫名稱

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"

func _run():
	print("=== 動畫庫內容 ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + ANIM_LIB_PATH)
		return
	
	var anims = lib.get_animation_list()
	print("共 %d 個動畫:" % anims.size())
	
	for anim_name in anims:
		print("  - %s" % anim_name)
	
	print("===================")
	print("使用方式: 在 AnimationTree 中，動畫名稱應為 'mx/<上面的名稱>'")
	print("例如: 如果有 'idle'，則使用 'mx/idle'")
