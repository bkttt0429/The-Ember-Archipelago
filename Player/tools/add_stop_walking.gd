@tool
extends EditorScript

## 將 Stop Walking 動畫添加到 movement 庫
## 執行：Ctrl+Shift+X

func _run() -> void:
	var lib_path = "res://Player/animations/movement.res"
	var fbx_path = "res://Player/assets/characters/player/motion/mx/Idle/Stop Walking.fbx"
	var anim_name = "Stop_Walking" # 在庫中的名稱
	
	# 載入動畫庫
	var lib = load(lib_path) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library")
		return
	
	# 載入 FBX
	var fbx = load(fbx_path) as PackedScene
	if not fbx:
		print("ERROR: Cannot load FBX: ", fbx_path)
		return
	
	# 實例化並找動畫
	var instance = fbx.instantiate()
	var anim_player = instance.get_node_or_null("AnimationPlayer") as AnimationPlayer
	
	if not anim_player:
		print("ERROR: No AnimationPlayer in FBX")
		instance.queue_free()
		return
	
	# FBX 通常有一個與文件同名的動畫或 "-loop" 後綴
	var source_anim: Animation = null
	for lib_name in anim_player.get_animation_library_list():
		var source_lib = anim_player.get_animation_library(lib_name)
		for name in source_lib.get_animation_list():
			print("Found animation: ", name)
			source_anim = source_lib.get_animation(name)
			break
		if source_anim:
			break
	
	instance.queue_free()
	
	if not source_anim:
		print("ERROR: No animation found in FBX")
		return
	
	# 添加到目標庫
	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)
		print("Removed existing: ", anim_name)
	
	lib.add_animation(anim_name, source_anim.duplicate())
	print("Added: ", anim_name)
	
	# 保存
	var err = ResourceSaver.save(lib, lib_path)
	if err == OK:
		print("SUCCESS: Library saved!")
	else:
		print("ERROR saving: ", err)
