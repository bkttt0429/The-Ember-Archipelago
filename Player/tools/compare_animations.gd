@tool
extends EditorScript

## 比較兩個動畫的軌道結構
## 使用方式：在 Godot 編輯器中執行 File > Run

func _run():
	print("\n" + "=".repeat(60))
	print("🔍 動畫軌道比較工具")
	print("=".repeat(60))
	
	# 載入兩個 FBX
	var original_path = "res://Player/assets/characters/player/motion/mx/Crouch/Crouched Walking.fbx"
	var new_path = "res://Player/assets/characters/player/motion/mx/Crouch/Crouched Walking Forward-Right.fbx"
	
	var original_tracks = get_animation_tracks(original_path, "原始 Crouched Walking")
	var new_tracks = get_animation_tracks(new_path, "新的 Forward-Right")
	
	# 比較
	print("\n" + "=".repeat(60))
	print("📊 軌道比較")
	print("=".repeat(60))
	
	if original_tracks.is_empty() or new_tracks.is_empty():
		print("無法比較，有動畫載入失敗")
		return
	
	# 找出差異
	var only_in_original = []
	var only_in_new = []
	var in_both = []
	
	for track in original_tracks:
		if track in new_tracks:
			in_both.append(track)
		else:
			only_in_original.append(track)
	
	for track in new_tracks:
		if track not in original_tracks:
			only_in_new.append(track)
	
	print("\n✅ 兩者都有的軌道: ", in_both.size())
	
	if only_in_original.size() > 0:
		print("\n⚠️ 只在原始動畫中的軌道:")
		for track in only_in_original:
			print("   ", track)
	
	if only_in_new.size() > 0:
		print("\n🆕 只在新動畫中的軌道:")
		for track in only_in_new:
			print("   ", track)
	
	if only_in_original.is_empty() and only_in_new.is_empty():
		print("\n✅ 軌道結構完全一致！")
		print("如果動畫仍有問題，可能是骨骼名稱映射或導入設定問題")

func get_animation_tracks(fbx_path: String, label: String) -> Array:
	var tracks = []
	
	var fbx = load(fbx_path) as PackedScene
	if fbx == null:
		print("❌ 無法載入: ", fbx_path)
		return tracks
	
	var instance = fbx.instantiate()
	var anim_player = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	
	if anim_player == null:
		print("❌ 找不到 AnimationPlayer: ", label)
		instance.queue_free()
		return tracks
	
	var anim_list = anim_player.get_animation_list()
	if anim_list.is_empty():
		print("❌ 沒有動畫: ", label)
		instance.queue_free()
		return tracks
	
	var anim = anim_player.get_animation(anim_list[0])
	
	print("\n📦 ", label)
	print("   動畫名稱: ", anim_list[0])
	print("   軌道數量: ", anim.get_track_count())
	print("   長度: ", anim.length, " 秒")
	
	for i in range(anim.get_track_count()):
		var track_path = anim.track_get_path(i)
		var track_type = anim.track_get_type(i)
		var key_count = anim.track_get_key_count(i)
		tracks.append(str(track_path))
		
		# 顯示前幾個軌道
		if i < 5:
			var type_name = ["Value", "Position3D", "Rotation3D", "Scale3D", "BlendShape", "Method", "Bezier", "Audio", "Animation"][track_type]
			print("   [%02d] %s (%s, %d keys)" % [i, track_path, type_name, key_count])
		elif i == 5:
			print("   ... 還有 %d 個軌道" % (anim.get_track_count() - 5))
	
	instance.queue_free()
	return tracks
