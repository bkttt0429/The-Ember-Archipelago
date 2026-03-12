@tool
extends EditorScript

## 從原始 FBX 重新匯入 Shimmy 動畫到 movement.res

const LIB_PATH = "res://Player/animations/movement.res"
const LEFT_SHIMMY_FBX = "res://Player/assets/characters/player/motion/mx/Climb/Left Shimmy.fbx"
const RIGHT_SHIMMY_FBX = "res://Player/assets/characters/player/motion/mx/Climb/Right Shimmy.fbx"

func _run() -> void:
	print("\n=== 重新匯入 Shimmy 動畫 ===\n")
	
	# 載入動畫庫
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load animation library")
		return
	
	# 載入 FBX 場景
	var left_scene = load(LEFT_SHIMMY_FBX) as PackedScene
	var right_scene = load(RIGHT_SHIMMY_FBX) as PackedScene
	
	if not left_scene:
		print("ERROR: Cannot load Left Shimmy FBX")
		return
	if not right_scene:
		print("ERROR: Cannot load Right Shimmy FBX")
		return
	
	print("✅ 已載入 FBX 檔案")
	
	# 從 FBX 提取動畫
	var left_anim = _extract_animation_from_scene(left_scene, "Left Shimmy")
	var right_anim = _extract_animation_from_scene(right_scene, "Right Shimmy")
	
	if not left_anim:
		print("ERROR: Cannot extract left shimmy animation")
		return
	if not right_anim:
		print("ERROR: Cannot extract right shimmy animation")
		return
	
	print("✅ 已提取動畫")
	print("  Left Shimmy: 長度=%.2fs, 軌道=%d" % [left_anim.length, left_anim.get_track_count()])
	print("  Right Shimmy: 長度=%.2fs, 軌道=%d" % [right_anim.length, right_anim.get_track_count()])
	
	# 分析 Hips 位移
	print("\n=== Hips 位移分析 ===")
	_analyze_hips_displacement(left_anim, "Left")
	_analyze_hips_displacement(right_anim, "Right")
	
	# 更新動畫庫
	if lib.has_animation("Shimmy_Left"):
		lib.remove_animation("Shimmy_Left")
	if lib.has_animation("Shimmy_Right"):
		lib.remove_animation("Shimmy_Right")
	
	lib.add_animation("Shimmy_Left", left_anim)
	lib.add_animation("Shimmy_Right", right_anim)
	
	# 保存
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err != OK:
		print("ERROR: Failed to save: ", err)
		return
	
	print("\n✅ 動畫已更新！請重新加載場景測試")

func _extract_animation_from_scene(scene: PackedScene, hint_name: String) -> Animation:
	var instance = scene.instantiate()
	
	# 尋找 AnimationPlayer
	var anim_player = _find_animation_player(instance)
	if not anim_player:
		print("  無法在場景中找到 AnimationPlayer")
		instance.queue_free()
		return null
	
	print("  找到 AnimationPlayer，動畫列表: ", anim_player.get_animation_list())
	
	# 獲取第一個非 RESET 動畫
	for anim_name in anim_player.get_animation_list():
		if anim_name != "RESET" and anim_name != "_":
			var anim = anim_player.get_animation(anim_name)
			instance.queue_free()
			return anim.duplicate(true)
	
	instance.queue_free()
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _analyze_hips_displacement(anim: Animation, label: String) -> void:
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			if anim.track_get_key_count(i) >= 2:
				var first = anim.track_get_key_value(i, 0)
				var last = anim.track_get_key_value(i, anim.track_get_key_count(i) - 1)
				var delta = last - first
				print("  %s Shimmy Hips 位移: X=%.3f, Y=%.3f, Z=%.3f" % [label, delta.x, delta.y, delta.z])
