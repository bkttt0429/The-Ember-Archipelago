@tool
extends EditorScript

## 檢查 Shimmy 動畫是否存在

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== 檢查 Shimmy 動畫 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load animation library")
		return
	
	var anims = lib.get_animation_list()
	
	# 搜索包含 shimmy 的動畫
	print("搜索包含 'shimmy' 的動畫:")
	for anim_name in anims:
		if "shimmy" in anim_name.to_lower() or "shift" in anim_name.to_lower():
			print("  ✅ ", anim_name)
	
	# 直接檢查代碼中使用的名稱
	print("\n檢查代碼中定義的動畫名稱:")
	var check_names = ["Shimmy_Left", "Shimmy_Right", "shimmy_left", "shimmy_right"]
	for name in check_names:
		if lib.has_animation(name):
			print("  ✅ 存在: ", name)
		else:
			print("  ❌ 不存在: ", name)
	
	print("\n✅ 檢查完成")
