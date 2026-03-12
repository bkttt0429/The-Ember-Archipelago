@tool
extends EditorScript

func _run():
	print("\n=== Animation Library Debug ===\n")
	
	# 載入 animations_mx.res
	var mx_lib = load("res://Player/assets/characters/player/motion/animations_mx.res") as AnimationLibrary
	if mx_lib:
		print("=== mx library animations ===")
		var anims = mx_lib.get_animation_list()
		for anim in anims:
			print("  - ", anim)
		print("Total: %d animations" % anims.size())
	else:
		print("ERROR: Could not load animations_mx.res")
	
	print("\n=== Done ===")
