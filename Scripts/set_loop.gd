@tool
extends EditorScript

# 設定動畫為循環模式

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"

var anims_to_fix = ["jog_bl", "jog_br"]

func _run():
	print("=== 設定動畫循環 ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + ANIM_LIB_PATH)
		return
	
	for anim_name in anims_to_fix:
		if not lib.has_animation(anim_name):
			print("找不到: %s" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var old_mode = anim.loop_mode
		anim.loop_mode = Animation.LOOP_LINEAR
		print("%s: loop_mode 改為 LOOP_LINEAR (之前: %d)" % [anim_name, old_mode])
	
	var error = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if error == OK:
		print("已儲存！")
	else:
		push_error("儲存失敗")
