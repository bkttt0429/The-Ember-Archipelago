@tool
extends EditorScript

## 匯入 Climb 資料夾的 FBX 動畫到 movement.res AnimationLibrary
## 運行方式: Godot Editor → Script → Run (Ctrl+Shift+X)

func _run() -> void:
	print("=== 開始匯入 Climb 動畫 ===")
	
	# 載入目標 AnimationLibrary
	var lib_path = "res://Player/animations/movement.res"
	var lib = load(lib_path) as AnimationLibrary
	if not lib:
		push_error("找不到 AnimationLibrary: " + lib_path)
		return
	
	# FBX 檔案對應列表 (檔名 → 動畫名)
	var fbx_files = {
		"Hanging_Idle": "res://Player/assets/characters/player/motion/mx/Climb/Hanging Idle.fbx",
		"Hang_To_Crouch": "res://Player/assets/characters/player/motion/mx/Climb/Braced Hang To Crouch.fbx",
		"Hang_Drop": "res://Player/assets/characters/player/motion/mx/Climb/Braced Hang Drop.fbx",
		"Shimmy_Left": "res://Player/assets/characters/player/motion/mx/Climb/Left Shimmy.fbx",
		"Shimmy_Right": "res://Player/assets/characters/player/motion/mx/Climb/Right Shimmy.fbx",
		"Braced_Hang_Left": "res://Player/assets/characters/player/motion/mx/Climb/Braced Hang left.fbx",
		"Braced_Hang_Right": "res://Player/assets/characters/player/motion/mx/Climb/Braced Hang right.fbx",
		"Free_Hang_Hop_Left": "res://Player/assets/characters/player/motion/mx/Climb/Free Hang Hop Left.fbx",
		"Free_Hang_Hop_Right": "res://Player/assets/characters/player/motion/mx/Climb/Free Hang Hop Right.fbx",
		"Breathing_Idle": "res://Player/assets/characters/player/motion/mx/Climb/Breathing Idle.fbx"
	}
	
	var imported_count = 0
	var skipped_count = 0
	
	for anim_name in fbx_files:
		var fbx_path = fbx_files[anim_name]
		
		# 檢查是否已存在
		if lib.has_animation(anim_name):
			print("跳過 (已存在): ", anim_name)
			skipped_count += 1
			continue
		
		print("處理: ", fbx_path)
		
		# 載入 FBX 場景
		var fbx_scene = load(fbx_path) as PackedScene
		if not fbx_scene:
			push_warning("無法載入 FBX: " + fbx_path)
			continue
		
		# 實例化場景
		var instance = fbx_scene.instantiate()
		if not instance:
			push_warning("無法實例化: " + fbx_path)
			continue
		
		# 找到 AnimationPlayer
		var anim_player: AnimationPlayer = null
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if not anim_player:
			push_warning("找不到 AnimationPlayer: " + fbx_path)
			instance.queue_free()
			continue
		
		# 獲取動畫列表
		var anim_list = anim_player.get_animation_list()
		if anim_list.is_empty():
			push_warning("沒有動畫: " + fbx_path)
			instance.queue_free()
			continue
		
		# 取第一個動畫 (Mixamo FBX 通常只有一個)
		var source_anim = anim_player.get_animation(anim_list[0])
		if source_anim:
			# 複製動畫
			var new_anim = source_anim.duplicate()
			
			# 添加到 library
			var err = lib.add_animation(anim_name, new_anim)
			if err == OK:
				print("✓ 匯入成功: ", anim_name, " (長度: ", new_anim.length, "s)")
				imported_count += 1
			else:
				push_error("添加動畫失敗: " + anim_name + " - " + str(err))
		
		instance.queue_free()
	
	# 儲存 library
	var err = ResourceSaver.save(lib, lib_path)
	if err == OK:
		print("=== AnimationLibrary 已儲存! ===")
		print("匯入: ", imported_count, " | 跳過: ", skipped_count)
	else:
		push_error("儲存失敗: " + str(err))
