@tool
extends EditorScript

## 將 Idle 資料夾中的所有 FBX 動畫添加到 movement.res 動畫庫

const FBX_DIR = "res://Player/assets/characters/player/motion/mx/Idle/"
const LIB_PATH = "res://Player/animations/movement.res"

# FBX 檔案名 -> 動畫庫中的名稱
const ANIM_MAPPING = {
	"Breathing Idle.fbx": "Breathing_Idle",
	"Run To Stop.fbx": "Run_To_Stop",
	"Run To Stop (1).fbx": "Run_To_Stop_Alt",
	"Stop Walking.fbx": "Stop_Walking",
}

func _run() -> void:
	print("\n=== Adding Idle Animations to movement.res ===\n")
	
	# 加載動畫庫
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	print("Current animations in library:")
	for anim_name in lib.get_animation_list():
		print("  - " + anim_name)
	print("")
	
	var added_count = 0
	var skipped_count = 0
	
	# 遍歷所有 FBX 檔案
	for fbx_file in ANIM_MAPPING.keys():
		var fbx_path = FBX_DIR + fbx_file
		var target_name = ANIM_MAPPING[fbx_file]
		
		# 檢查是否已存在
		if lib.has_animation(target_name):
			print("SKIP: '%s' already exists" % target_name)
			skipped_count += 1
			continue
		
		# 加載 FBX 場景
		var fbx_scene = load(fbx_path)
		if not fbx_scene:
			print("ERROR: Cannot load FBX: " + fbx_path)
			continue
		
		var instance = fbx_scene.instantiate()
		var anim_player: AnimationPlayer = null
		
		# 查找 AnimationPlayer
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if not anim_player:
			print("ERROR: No AnimationPlayer in FBX: " + fbx_file)
			instance.queue_free()
			continue
		
		# 獲取並添加動畫
		var anim_list = anim_player.get_animation_list()
		if anim_list.size() > 0:
			var anim = anim_player.get_animation(anim_list[0])
			lib.add_animation(target_name, anim.duplicate())
			print("ADDED: '%s' (from %s, length: %.2fs)" % [target_name, fbx_file, anim.length])
			added_count += 1
		else:
			print("ERROR: No animations found in: " + fbx_file)
		
		instance.queue_free()
	
	# 保存
	if added_count > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\nSUCCESS: Saved %d new animations to %s" % [added_count, LIB_PATH])
		else:
			print("\nERROR saving: ", err)
	else:
		print("\nNo new animations added (skipped: %d)" % skipped_count)
	
	print("\n=== Done ===")
