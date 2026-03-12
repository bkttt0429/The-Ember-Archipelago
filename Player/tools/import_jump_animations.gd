@tool
extends EditorScript

## 從 FBX 匯入跳躍動畫到 movement.res
## 在 Godot 編輯器中執行：File > Run

const FBX_DIR = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/Movement/Jump/"
const LIBRARY_PATH = "res://Player/animations/movement.res"

# FBX 檔案 -> 動畫名稱映射
const IMPORT_MAP = {
	"HumanM@Jump01 - Begin.fbx": "Jump01_Start",
	"HumanM@Fall01.fbx": "Fall01_Loop",
	"HumanM@Jump01 - Land.fbx": "Jump01_Land",
	"HumanM@Jump01.fbx": "Jump01_Full",
}

func _run() -> void:
	print("=== 開始匯入跳躍動畫 ===")
	
	# 載入現有的動畫庫
	var library = load(LIBRARY_PATH) as AnimationLibrary
	if not library:
		push_error("無法載入動畫庫: " + LIBRARY_PATH)
		return
	
	print("已載入動畫庫: ", LIBRARY_PATH)
	
	var imported_count = 0
	
	for fbx_name in IMPORT_MAP:
		var anim_name = IMPORT_MAP[fbx_name]
		var fbx_path = FBX_DIR + fbx_name
		
		print("----------------------------------------")
		print("處理: ", fbx_name)
		
		# 載入 FBX 場景
		var fbx_scene = load(fbx_path) as PackedScene
		if not fbx_scene:
			push_warning("無法載入 FBX: " + fbx_path)
			continue
		
		# 實例化以取得 AnimationPlayer
		var instance = fbx_scene.instantiate()
		var anim_player: AnimationPlayer = null
		
		# 尋找 AnimationPlayer
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if not anim_player:
			push_warning("FBX 中找不到 AnimationPlayer: " + fbx_name)
			instance.queue_free()
			continue
		
		# 取得動畫列表
		var anim_list = anim_player.get_animation_list()
		print("  找到動畫: ", anim_list)
		
		if anim_list.is_empty():
			push_warning("FBX 中沒有動畫: " + fbx_name)
			instance.queue_free()
			continue
		
		# 取得第一個動畫 (通常 FBX 只有一個)
		var source_anim = anim_player.get_animation(anim_list[0])
		if not source_anim:
			push_warning("無法取得動畫")
			instance.queue_free()
			continue
		
		# 複製動畫
		var new_anim = source_anim.duplicate(true)
		
		# 檢查是否已存在
		if library.has_animation(anim_name):
			library.remove_animation(anim_name)
			print("  移除舊動畫: ", anim_name)
		
		# 添加到庫
		var err = library.add_animation(anim_name, new_anim)
		if err == OK:
			print("  ✅ 已添加: ", anim_name, " (長度: %.2f 秒)" % new_anim.length)
			imported_count += 1
		else:
			push_error("添加動畫失敗: " + anim_name)
		
		instance.queue_free()
	
	# 儲存動畫庫
	var save_err = ResourceSaver.save(library, LIBRARY_PATH)
	if save_err == OK:
		print("========================================")
		print("✅ 成功匯入 %d 個動畫並儲存!" % imported_count)
	else:
		push_error("儲存失敗: " + str(save_err))
