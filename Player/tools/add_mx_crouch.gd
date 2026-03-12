@tool
extends EditorScript
## 將 mx/Crouch 動畫加入 movement.res (設為 loop)
## 使用方式：Script > Run

const MX_CROUCH_DIR = "res://Player/assets/characters/player/motion/mx/Crouch/"
const TARGET_LIBRARY_PATH = "res://Player/animations/movement.res"

# 動畫對應表 (FBX 檔名 -> 新名稱)
const CROUCH_ANIMS = {
	"Crouched Walking.fbx": "mx_Crouch_Walk",
	"Standing To Crouched.fbx": "mx_Stand_To_Crouch",
	"Crouch To Stand.fbx": "mx_Crouch_To_Stand",
	"Crouched To Sprinting.fbx": "mx_Crouch_To_Sprint"
}

func _run():
	print("=== 加入 mx/Crouch 動畫 ===")
	
	# 載入目標 AnimationLibrary
	var library = load(TARGET_LIBRARY_PATH) as AnimationLibrary
	if not library:
		push_error("無法載入 %s" % TARGET_LIBRARY_PATH)
		return
	
	var added_count = 0
	
	for fbx_name in CROUCH_ANIMS.keys():
		var new_name = CROUCH_ANIMS[fbx_name]
		var fbx_path = MX_CROUCH_DIR + fbx_name
		
		# 檢查是否已存在
		if library.has_animation(new_name):
			print("  跳過 %s (已存在)" % new_name)
			continue
		
		# 載入 FBX 作為 PackedScene
		var fbx_scene = load(fbx_path) as PackedScene
		if not fbx_scene:
			push_warning("無法載入 FBX: %s" % fbx_path)
			continue
		
		# 實例化場景來取得 AnimationPlayer
		var instance = fbx_scene.instantiate()
		var anim_player: AnimationPlayer = null
		
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if not anim_player:
			push_warning("FBX 沒有 AnimationPlayer: %s" % fbx_path)
			instance.queue_free()
			continue
		
		# 取得動畫列表
		var anim_names = anim_player.get_animation_list()
		if anim_names.is_empty():
			push_warning("FBX 沒有動畫: %s" % fbx_path)
			instance.queue_free()
			continue
		
		# 取得第一個動畫
		var original_anim = anim_player.get_animation(anim_names[0])
		if not original_anim:
			instance.queue_free()
			continue
		
		# 複製動畫
		var new_anim = original_anim.duplicate() as Animation
		
		# 設定為循環 (對於 walk 類動畫)
		if "Walk" in new_name or "Crouch_Walk" in new_name:
			new_anim.loop_mode = Animation.LOOP_LINEAR
			print("  設定 %s 為 LOOP" % new_name)
		
		# 加入到 library
		var err = library.add_animation(new_name, new_anim)
		if err == OK:
			print("  ✅ 已加入: %s" % new_name)
			added_count += 1
		else:
			push_warning("無法加入動畫: %s (錯誤 %d)" % [new_name, err])
		
		instance.queue_free()
	
	# 儲存
	if added_count > 0:
		var err = ResourceSaver.save(library, TARGET_LIBRARY_PATH)
		if err == OK:
			print("=== 完成！已加入 %d 個動畫 ===" % added_count)
		else:
			push_error("儲存失敗: %d" % err)
	else:
		print("=== 沒有新動畫需要加入 ===")
