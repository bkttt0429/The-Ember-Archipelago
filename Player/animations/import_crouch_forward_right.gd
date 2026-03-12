@tool
extends EditorScript

## 工具腳本：將新的斜向蹲行動畫加入 movement.res AnimationLibrary
## 使用方式：在 Godot 編輯器中，選擇此腳本然後按 File > Run

const NEW_FBX_PATH = "res://Player/assets/characters/player/motion/mx/Crouch/Crouched Walking Forward-Right.fbx"
const LIBRARY_PATH = "res://Player/animations/movement.res"
const NEW_ANIM_NAME = "Crouch_Walk_ForwardRight"

func _run():
	print("=== 開始導入斜向蹲行動畫 ===")
	
	# 載入 AnimationLibrary
	var lib = load(LIBRARY_PATH) as AnimationLibrary
	if lib == null:
		push_error("無法載入 AnimationLibrary: " + LIBRARY_PATH)
		return
	
	print("已載入 AnimationLibrary: ", LIBRARY_PATH)
	print("現有動畫數量: ", lib.get_animation_list().size())
	
	# 載入 FBX 場景
	var fbx_scene = load(NEW_FBX_PATH) as PackedScene
	if fbx_scene == null:
		push_error("無法載入 FBX: " + NEW_FBX_PATH)
		push_error("請確保 Godot 已經掃描並導入此 FBX 檔案")
		return
	
	# 實例化場景來提取動畫
	var instance = fbx_scene.instantiate()
	
	# 找到 AnimationPlayer
	var anim_player: AnimationPlayer = null
	for child in instance.get_children():
		if child is AnimationPlayer:
			anim_player = child
			break
	
	if anim_player == null:
		# 嘗試在更深層尋找
		anim_player = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	
	if anim_player == null:
		push_error("在 FBX 中找不到 AnimationPlayer")
		instance.queue_free()
		return
	
	print("找到 AnimationPlayer，動畫列表: ", anim_player.get_animation_list())
	
	# 取得動畫
	var anim_list = anim_player.get_animation_list()
	if anim_list.is_empty():
		push_error("FBX 中沒有動畫")
		instance.queue_free()
		return
	
	# 取得第一個動畫（通常只有一個）
	var source_anim_name = anim_list[0]
	var source_anim = anim_player.get_animation(source_anim_name)
	
	if source_anim == null:
		push_error("無法取得動畫: " + source_anim_name)
		instance.queue_free()
		return
	
	# 複製動畫
	var new_anim = source_anim.duplicate(true) as Animation
	new_anim.resource_name = NEW_ANIM_NAME
	
	print("動畫資訊:")
	print("  原始名稱: ", source_anim_name)
	print("  新名稱: ", NEW_ANIM_NAME)
	print("  長度: ", new_anim.length, " 秒")
	print("  軌道數: ", new_anim.get_track_count())
	
	# 檢查是否已存在同名動畫
	if lib.has_animation(NEW_ANIM_NAME):
		print("警告: 動畫 '", NEW_ANIM_NAME, "' 已存在，將被覆蓋")
		lib.remove_animation(NEW_ANIM_NAME)
	
	# 加入到 library
	var err = lib.add_animation(NEW_ANIM_NAME, new_anim)
	if err != OK:
		push_error("無法加入動畫到 library: ", err)
		instance.queue_free()
		return
	
	# 儲存 library
	err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err != OK:
		push_error("無法儲存 AnimationLibrary: ", err)
		instance.queue_free()
		return
	
	print("=== 成功! ===")
	print("動畫 '", NEW_ANIM_NAME, "' 已加入到 ", LIBRARY_PATH)
	print("現有動畫數量: ", lib.get_animation_list().size())
	
	# 清理
	instance.queue_free()
