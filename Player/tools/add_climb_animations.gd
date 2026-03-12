@tool
extends EditorScript

## 將攀爬動畫從 FBX 提取並加入 movement_animations library
## 在 Godot 編輯器中：Script > Run

const CLIMB_FOLDER = "res://Player/assets/characters/player/motion/mx/Climb/"
const LIBRARY_PATH = "res://Player/assets/characters/player/motion/movement_animations.res"

# 動畫名稱映射：FBX名稱 -> Library名稱
const ANIMATION_MAP = {
	"Hanging Idle.fbx": "Hang_Idle",
	"Braced Hang Drop.fbx": "Hang_Drop",
	"Braced Hang To Crouch.fbx": "Hang_ClimbUp",
	"Braced Hang left.fbx": "Hang_ShimmyLeft",
	"Braced Hang right.fbx": "Hang_ShimmyRight",
	"Free Hang Hop Left.fbx": "Hang_HopLeft",
	"Free Hang Hop Right.fbx": "Hang_HopRight",
	"Breathing Idle.fbx": "Hang_BreathingIdle",
}

func _run() -> void:
	print("=== 開始提取攀爬動畫 ===")
	
	# 載入現有 library
	var lib: AnimationLibrary
	if ResourceLoader.exists(LIBRARY_PATH):
		lib = ResourceLoader.load(LIBRARY_PATH) as AnimationLibrary
		print("已載入現有 library: %s" % LIBRARY_PATH)
	else:
		lib = AnimationLibrary.new()
		print("創建新 library")
	
	var added_count = 0
	
	for fbx_name in ANIMATION_MAP:
		var anim_name = ANIMATION_MAP[fbx_name]
		var fbx_path = CLIMB_FOLDER + fbx_name
		
		# 檢查是否已存在
		if lib.has_animation(anim_name):
			print("⏭️ 跳過 (已存在): %s" % anim_name)
			continue
		
		# 載入 FBX 場景
		if not ResourceLoader.exists(fbx_path):
			print("❌ 找不到: %s" % fbx_path)
			continue
		
		var scene = ResourceLoader.load(fbx_path) as PackedScene
		if scene == null:
			print("❌ 無法載入: %s" % fbx_path)
			continue
		
		# 實例化場景找 AnimationPlayer
		var instance = scene.instantiate()
		var anim_player: AnimationPlayer = null
		
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if anim_player == null:
			print("❌ 找不到 AnimationPlayer: %s" % fbx_name)
			instance.queue_free()
			continue
		
		# 取得動畫列表
		var anim_list = anim_player.get_animation_list()
		if anim_list.is_empty():
			print("❌ 無動畫: %s" % fbx_name)
			instance.queue_free()
			continue
		
		# 取得第一個動畫（通常 FBX 只有一個）
		var source_anim_name = anim_list[0]
		var anim = anim_player.get_animation(source_anim_name)
		
		if anim:
			# 複製動畫並加入 library
			var new_anim = anim.duplicate()
			lib.add_animation(anim_name, new_anim)
			print("✅ 已加入: %s (來自 %s)" % [anim_name, fbx_name])
			added_count += 1
		
		instance.queue_free()
	
	# 儲存 library
	var err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err == OK:
		print("=== 完成！已加入 %d 個動畫 ===" % added_count)
		print("Library 已儲存: %s" % LIBRARY_PATH)
	else:
		print("❌ 儲存失敗: %s" % error_string(err))
