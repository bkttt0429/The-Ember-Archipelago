@tool
extends EditorScript

## 匯入 land 資料夾的動畫到 movement library
## 使用方式：在 Godot 編輯器中打開此腳本，按 Ctrl+Shift+X 執行

func _run() -> void:
	print("=== 開始匯入 Land 動畫 ===")
	
	# 載入目標 AnimationLibrary
	var lib_path = "res://Player/animations/movement.res"
	var lib = load(lib_path) as AnimationLibrary
	if not lib:
		push_error("找不到 AnimationLibrary: " + lib_path)
		return
	
	# FBX 檔案列表
	var fbx_files = {
		"Falling_To_Landing": "res://Player/assets/characters/player/motion/mx/land/Falling To Landing.fbx",
		"Hard_Landing": "res://Player/assets/characters/player/motion/mx/land/Hard Landing.fbx"
	}
	
	for anim_name in fbx_files:
		var fbx_path = fbx_files[anim_name]
		print("處理: ", fbx_path)
		
		# 載入 FBX 場景
		var scene = load(fbx_path) as PackedScene
		if not scene:
			push_warning("無法載入 FBX: " + fbx_path)
			continue
		
		# 實例化並找到 AnimationPlayer
		var instance = scene.instantiate()
		var anim_player: AnimationPlayer = null
		
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if not anim_player:
			push_warning("FBX 中沒有 AnimationPlayer: " + fbx_path)
			instance.queue_free()
			continue
		
		# 獲取動畫列表
		var anim_list = anim_player.get_animation_list()
		for source_anim_name in anim_list:
			if source_anim_name == "RESET":
				continue
			
			var anim = anim_player.get_animation(source_anim_name)
			if anim:
				# 複製動畫
				var new_anim = anim.duplicate(true)
				
				# 添加到 library
				if lib.has_animation(anim_name):
					lib.remove_animation(anim_name)
				lib.add_animation(anim_name, new_anim)
				print("已添加動畫: ", anim_name)
		
		instance.queue_free()
	
	# 儲存 library
	var err = ResourceSaver.save(lib, lib_path)
	if err == OK:
		print("=== AnimationLibrary 已儲存! ===")
	else:
		push_error("儲存失敗: " + str(err))
