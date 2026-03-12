@tool
extends EditorScript

## 將跳躍動畫從 FBX 提取並加入 movement library
## 包含 In-Place 處理
## 在 Godot 編輯器中：Script > Run

const JUMP_FOLDER = "res://Player/assets/characters/player/motion/mx/Jump/"
const LIBRARY_PATH = "res://Player/animations/movement.res"

# 動畫名稱映射：FBX名稱 -> [Library名稱, 是否循環]
const ANIMATION_MAP = {
	# 基本跳躍 (一體式)
	"Standing Jump.fbx": ["Jump_Standing", false],
	"Standing Jump (1).fbx": ["Jump_Standing_Alt", false],
	"Jump Backward.fbx": ["Jump_Backward", false],
	
	# 跑步/衝刺跳躍
	"Jumping to stage.fbx": ["Jump_ToStage", false],
	"Jumping to stage1.fbx": ["Jump_ToStage1", false],
	"Jumping to stage runing.fbx": ["Jump_Running", false],
	
	# 下落循環 (空中姿態)
	"Jumping Down stage.fbx": ["Fall_Loop1", true], # 循環
	"Jumping Down stage2.fbx": ["Fall_Loop2", true],
	"Jumping Down stage3.fbx": ["Fall_Loop3", true],
}

func _run() -> void:
	print("=== 開始提取跳躍動畫 ===")
	
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
		var fbx_path = JUMP_FOLDER + fbx_name
		
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
			else:
				new_anim.loop_mode = Animation.LOOP_NONE
			
			# In-Place 處理：移除根骨骼的位移軌道
			_make_in_place(new_anim, anim_name)
			
			# 檢查是否已存在
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
	
	# 儲存 library
	var err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err == OK:
		print("=== 完成！新增 %d 個，更新 %d 個動畫 ===" % [added_count, updated_count])
		print("Library 已儲存: %s" % LIBRARY_PATH)
		_print_jump_animation_guide()
	else:
		print("❌ 儲存失敗: %s" % error_string(err))

func _make_in_place(anim: Animation, anim_name: String) -> void:
	"""移除根骨骼的水平位移，保留垂直運動"""
	var tracks_modified = 0
	
	# 找出所有根骨骼相關的位置軌道
	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# 檢查是否是根骨骼的位置軌道
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if "Hips" in path_str or "Root" in path_str or "Pelvis" in path_str:
				var key_count = anim.track_get_key_count(i)
				
				# 獲取第一幀的位置作為基準
				var first_pos = anim.track_get_key_value(i, 0) as Vector3
				
				for key_idx in range(key_count):
					var pos = anim.track_get_key_value(i, key_idx) as Vector3
					# 保留相對 Y 軸變化，清除水平位移
					var relative_y = pos.y - first_pos.y
					anim.track_set_key_value(i, key_idx, Vector3(0, first_pos.y + relative_y, 0))
				
				tracks_modified += 1
	
	if tracks_modified > 0:
		print("   📍 In-Place: %s (%d 軌道)" % [anim_name, tracks_modified])

func _print_jump_animation_guide() -> void:
	print("")
	print("=== 跳躍動畫使用指南 ===")
	print("")
	print("【基礎跳躍方案】(推薦)")
	print("  - Jump_Standing: 原地跳 (起跳+空中+落地一體)")
	print("  - Jump_Backward: 後跳")
	print("")
	print("【分段跳躍方案】(進階)")
	print("  使用現有的 ual_Jump_Start/ual_Jump/ual_Jump_Land")
	print("  - ual_Jump_Start: 起跳 (可循環)")
	print("  - ual_Jump: 空中滯空 (循環)")
	print("  - ual_Jump_Land: 落地")
	print("")
	print("【平台跳躍】(特殊場景)")
	print("  - Jump_Up_Platform: 跳上平台")
	print("  - Jump_Up_Running: 跑跳上平台")
	print("  - Jump_Down_Platform: 跳下平台")
	print("")
	print("在 AnimationTree 中可以選擇不同方案！")
