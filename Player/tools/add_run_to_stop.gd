@tool
extends EditorScript

## 將 Run To Stop.fbx 動畫添加到 movement.res 動畫庫

func _run() -> void:
	var fbx_path = "res://Player/assets/characters/player/motion/mx/Idle/Run To Stop.fbx"
	var lib_path = "res://Player/animations/movement.res"
	
	# 加載 FBX 場景
	var fbx_scene = load(fbx_path)
	if not fbx_scene:
		print("ERROR: Cannot load FBX: " + fbx_path)
		return
	
	var instance = fbx_scene.instantiate()
	var anim_player: AnimationPlayer = null
	
	# 查找 AnimationPlayer
	for child in instance.get_children():
		if child is AnimationPlayer:
			anim_player = child
			break
	
	if not anim_player:
		print("ERROR: No AnimationPlayer in FBX")
		instance.queue_free()
		return
	
	print("Found animations: ", anim_player.get_animation_list())
	
	# 加載動畫庫
	var lib = load(lib_path) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + lib_path)
		instance.queue_free()
		return
	
	# 添加動畫
	for anim_name in anim_player.get_animation_list():
		var anim = anim_player.get_animation(anim_name)
		var new_name = "Run_To_Stop"
		if not lib.has_animation(new_name):
			lib.add_animation(new_name, anim.duplicate())
			print("Added animation: " + new_name)
		else:
			print("Animation already exists: " + new_name)
	
	# 保存
	var err = ResourceSaver.save(lib, lib_path)
	if err == OK:
		print("SUCCESS: Saved to " + lib_path)
	else:
		print("ERROR saving: ", err)
	
	instance.queue_free()
