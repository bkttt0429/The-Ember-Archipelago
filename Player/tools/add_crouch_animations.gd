@tool
extends EditorScript

## 將蹲下動畫從 FBX 提取並加入 movement library
## 包含 Loop 和 In-Place 處理
## 在 Godot 編輯器中：Script > Run

const CROUCH_FOLDER = "res://Player/assets/characters/player/motion/mx/Crouch/"
const LIBRARY_PATH = "res://Player/animations/movement.res"

# 動畫名稱映射：FBX名稱 -> [Library名稱, 是否循環]
const ANIMATION_MAP = {
	"Crouched Walking.fbx": ["Crouch_Walk_Forward", true],
	"Crouch Walk Back.fbx": ["Crouch_Walk_Backward", true],
	"Crouch Walk Left.fbx": ["Crouch_Walk_Left", true],
	"Crouch Walk Right.fbx": ["Crouch_Walk_Right", true],
	"Standing To Crouched.fbx": ["Stand_To_Crouch", false],
	"Crouch To Stand.fbx": ["Crouch_To_Stand", false],
	"Crouched To Sprinting.fbx": ["Crouch_To_Sprint", false],
	"Crouch Turn Left 90.fbx": ["Crouch_Turn_Left", false],
	"Crouch Turn Right 90.fbx": ["Crouch_Turn_Right", false],
}

func _run() -> void:
	print("=== 開始提取蹲下動畫 ===")
	
	# 載入現有 library
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
		var fbx_path = CROUCH_FOLDER + fbx_name
		
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
			# 複製動畫
			var new_anim = anim.duplicate() as Animation
			
			# 設置循環模式
			if should_loop:
				new_anim.loop_mode = Animation.LOOP_LINEAR
				print("🔄 設置循環: %s" % anim_name)
			else:
				new_anim.loop_mode = Animation.LOOP_NONE
			
			# In-Place 處理：移除根骨骼的位移軌道
			_make_in_place(new_anim)
			
			# 檢查是否已存在
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
				lib.add_animation(anim_name, new_anim)
				print("🔄 已更新: %s (來自 %s)" % [anim_name, fbx_name])
				updated_count += 1
			else:
				lib.add_animation(anim_name, new_anim)
				print("✅ 已加入: %s (來自 %s)" % [anim_name, fbx_name])
				added_count += 1
		
		instance.queue_free()
	
	# 儲存 library
	var err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err == OK:
		print("=== 完成！新增 %d 個，更新 %d 個動畫 ===" % [added_count, updated_count])
		print("Library 已儲存: %s" % LIBRARY_PATH)
	else:
		print("❌ 儲存失敗: %s" % error_string(err))

func _make_in_place(anim: Animation) -> void:
	"""移除根骨骼的位移，保留旋轉"""
	var tracks_to_process: Array[int] = []
	
	# 找出所有根骨骼相關的位置軌道
	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# 檢查是否是根骨骼的位置軌道
		# 常見的根骨骼名稱：Root, Hips, Pelvis, mixamorig:Hips
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if "Hips" in path_str or "Root" in path_str or "Pelvis" in path_str:
				tracks_to_process.append(i)
	
	# 將根骨骼的 X/Z 位移設為 0（保留 Y 以維持高度變化）
	for track_idx in tracks_to_process:
		var key_count = anim.track_get_key_count(track_idx)
		for key_idx in range(key_count):
			var pos = anim.track_get_key_value(track_idx, key_idx) as Vector3
			# 只保留 Y 軸（高度），清除 X/Z（水平位移）
			anim.track_set_key_value(track_idx, key_idx, Vector3(0, pos.y, 0))
	
	if tracks_to_process.size() > 0:
		print("   📍 In-Place 處理完成，影響 %d 個軌道" % tracks_to_process.size())
