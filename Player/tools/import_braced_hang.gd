@tool
extends EditorScript

## 匯入 Braced Hang 動畫到 movement.res 並對齊位置
## 會分析動畫的根位移並調整到原點

const SOURCE_PATH = "res://Player/assets/characters/player/motion/mx/Climb/"
const LIB_PATH = "res://Player/animations/movement.res"

# 要匯入的動畫檔案對應
const ANIMATIONS = {
	"Braced_Hang_Left": "Braced Hang left.fbx",
	"Braced_Hang_Right": "Braced Hang right.fbx",
}

func _run() -> void:
	print("\n=== 匯入 Braced Hang 動畫 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load ", LIB_PATH)
		return
	
	for anim_name in ANIMATIONS:
		var fbx_file = ANIMATIONS[anim_name]
		var fbx_path = SOURCE_PATH + fbx_file
		
		print("\n--- 處理: %s ---" % fbx_file)
		
		# 載入 FBX 場景
		var scene = load(fbx_path) as PackedScene
		if not scene:
			print("  ERROR: Cannot load ", fbx_path)
			continue
		
		var instance = scene.instantiate()
		var anim_player = _find_anim_player(instance)
		
		if not anim_player:
			print("  ERROR: No AnimationPlayer found")
			instance.queue_free()
			continue
		
		# 查找 Mixamo 命名的動畫
		var source_anim: Animation = null
		for name in anim_player.get_animation_list():
			print("  找到動畫: %s" % name)
			if "mixamo" in name.to_lower() or name.begins_with("Armature"):
				source_anim = anim_player.get_animation(name)
				break
			# 取第一個非 RESET 動畫
			if name != "RESET" and source_anim == null:
				source_anim = anim_player.get_animation(name)
		
		if not source_anim:
			print("  ERROR: No animation found")
			instance.queue_free()
			continue
		
		# 複製並調整動畫
		var new_anim = source_anim.duplicate(true) as Animation
		_align_animation_to_origin(new_anim, anim_name)
		
		# 添加到動畫庫
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
			print("  移除舊動畫: %s" % anim_name)
		
		lib.add_animation(anim_name, new_anim)
		print("  ✅ 添加動畫: %s (長度=%.2fs, 軌道數=%d)" % [
			anim_name, new_anim.length, new_anim.get_track_count()
		])
		
		instance.queue_free()
	
	# 保存動畫庫
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err != OK:
		print("\nERROR: Failed to save library: ", err)
		return
	
	print("\n✅ 動畫庫已保存！")
	print("新動畫: Braced_Hang_Left, Braced_Hang_Right")

## 對齊動畫到原點 - 調整 Hips 位置軌道
func _align_animation_to_origin(anim: Animation, anim_name: String) -> void:
	print("  對齊動畫到原點...")
	
	# 查找 Hips 位置軌道
	var hips_track_idx = -1
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		if "Hips" in path_str and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			hips_track_idx = i
			break
	
	if hips_track_idx < 0:
		print("  WARNING: No Hips position track found")
		return
	
	# 獲取第一幀的 Hips 位置
	var key_count = anim.track_get_key_count(hips_track_idx)
	if key_count == 0:
		return
	
	var first_pos = anim.track_get_key_value(hips_track_idx, 0) as Vector3
	print("  第一幀 Hips 位置: %s" % first_pos)
	
	# 計算偏移量（將 XZ 歸零，保留 Y）
	var offset = Vector3(first_pos.x, 0, first_pos.z)
	
	# 調整所有關鍵幀
	for i in key_count:
		var pos = anim.track_get_key_value(hips_track_idx, i) as Vector3
		var new_pos = pos - offset
		anim.track_set_key_value(hips_track_idx, i, new_pos)
	
	var last_pos = anim.track_get_key_value(hips_track_idx, key_count - 1) as Vector3
	print("  調整後: 第一幀=(%.3f, %.3f, %.3f), 最後幀=(%.3f, %.3f, %.3f)" % [
		0.0, first_pos.y, 0.0,
		last_pos.x, last_pos.y, last_pos.z
	])
	
	# 分析運動方向
	if key_count > 1:
		var total_x = last_pos.x
		var total_z = last_pos.z
		print("  總位移: X=%.3f, Z=%.3f" % [total_x, total_z])

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_anim_player(child)
		if result:
			return result
	return null
