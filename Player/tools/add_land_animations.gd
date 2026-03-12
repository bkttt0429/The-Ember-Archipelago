@tool
extends EditorScript

## 將落地動畫從 FBX 提取並加入 movement library
## 在 Godot 編輯器中：Script > Run

const LAND_FOLDER = "res://Player/assets/characters/player/motion/mx/land/"
const LIBRARY_PATH = "res://Player/animations/movement.res"

const ANIMATION_MAP = {
	"Hard Landing.fbx": ["Hard_Land", false],
	"Hard Landing (1).fbx": ["Hard_Land_Alt", false],
}

func _run() -> void:
	print("=== 開始提取落地動畫 ===")
	
	var lib: AnimationLibrary
	if ResourceLoader.exists(LIBRARY_PATH):
		lib = ResourceLoader.load(LIBRARY_PATH) as AnimationLibrary
		print("已載入現有 library: %s" % LIBRARY_PATH)
	else:
		lib = AnimationLibrary.new()
		print("創建新 library")
	
	var added_count = 0
	var updated_count = 0
	
	for fbx_name in ANIMATION_MAP:
		var anim_config = ANIMATION_MAP[fbx_name]
		var anim_name: String = anim_config[0]
		var should_loop: bool = anim_config[1]
		var fbx_path = LAND_FOLDER + fbx_name
		
		if not ResourceLoader.exists(fbx_path):
			print("❌ 找不到: %s" % fbx_path)
			continue
		
		var scene = ResourceLoader.load(fbx_path) as PackedScene
		if scene == null:
			print("❌ 無法載入: %s" % fbx_path)
			continue
		
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
		
		var anim_list = anim_player.get_animation_list()
		if anim_list.is_empty():
			print("❌ 無動畫: %s" % fbx_name)
			instance.queue_free()
			continue
		
		var source_anim_name = anim_list[0]
		var anim = anim_player.get_animation(source_anim_name)
		
		if anim:
			var new_anim = anim.duplicate() as Animation
			
			if should_loop:
				new_anim.loop_mode = Animation.LOOP_LINEAR
			else:
				new_anim.loop_mode = Animation.LOOP_NONE
			
			# In-Place 處理
			_make_in_place(new_anim, anim_name)
			
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
				lib.add_animation(anim_name, new_anim)
				print("🔄 已更新: %s (來自 %s, %.2fs)" % [anim_name, fbx_name, new_anim.length])
				updated_count += 1
			else:
				lib.add_animation(anim_name, new_anim)
				print("✅ 已加入: %s (來自 %s, %.2fs)" % [anim_name, fbx_name, new_anim.length])
				added_count += 1
		
		instance.queue_free()
	
	var err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err == OK:
		print("=== 完成！新增 %d 個，更新 %d 個落地動畫 ===" % [added_count, updated_count])
	else:
		print("❌ 儲存失敗: %s" % error_string(err))

func _make_in_place(anim: Animation, anim_name: String) -> void:
	var tracks_modified = 0
	
	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if "Hips" in path_str or "Root" in path_str or "Pelvis" in path_str:
				var key_count = anim.track_get_key_count(i)
				var first_pos = anim.track_get_key_value(i, 0) as Vector3
				
				for key_idx in range(key_count):
					var pos = anim.track_get_key_value(i, key_idx) as Vector3
					var relative_y = pos.y - first_pos.y
					anim.track_set_key_value(i, key_idx, Vector3(0, first_pos.y + relative_y, 0))
				
				tracks_modified += 1
	
	if tracks_modified > 0:
		print("   📍 In-Place: %s (%d 軌道)" % [anim_name, tracks_modified])
