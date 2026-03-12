@tool
extends EditorScript
## 診斷腳本：列出 FBX 動畫檔的骨架資訊
## 用途: 確認 FBX 骨骼名稱和骨架節點路徑

func _run() -> void:
	var fbx_path := "res://Player/assets/characters/player/motion/Human Animations/Animations/Female/Idles/HumanF@Idle01.fbx"
	
	print("\n=== FBX 骨架診斷 ===")
	print("檔案: ", fbx_path)
	
	var scene_res = load(fbx_path)
	if not scene_res or not scene_res is PackedScene:
		print("ERROR: 無法載入 FBX")
		return
	
	var instance: Node = scene_res.instantiate()
	
	# 列出完整節點樹
	print("\n--- 節點樹 ---")
	_print_tree(instance, 0)
	
	# 找到 Skeleton3D
	var skeleton: Skeleton3D = _find_skeleton(instance)
	if skeleton:
		print("\n--- 骨架資訊 ---")
		print("骨架節點路徑: ", instance.get_path_to(skeleton))
		print("骨骼數量: ", skeleton.get_bone_count())
		print("\n所有骨骼名稱:")
		for i in range(skeleton.get_bone_count()):
			var parent_idx := skeleton.get_bone_parent(i)
			var parent_name := skeleton.get_bone_name(parent_idx) if parent_idx >= 0 else "(root)"
			print("  [%d] %s  (parent: %s)" % [i, skeleton.get_bone_name(i), parent_name])
	else:
		print("ERROR: 找不到 Skeleton3D")
	
	# 找到 AnimationPlayer，列出 track 路徑
	var anim_player: AnimationPlayer = _find_animation_player(instance)
	if anim_player:
		print("\n--- 動畫 Track 路徑 ---")
		for lib_name in anim_player.get_animation_library_list():
			var lib := anim_player.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				if anim_name == "RESET":
					continue
				var anim := lib.get_animation(anim_name)
				print("動畫: ", anim_name, " (tracks: ", anim.get_track_count(), ")")
				for i in range(min(anim.get_track_count(), 15)):
					print("  Track[%d]: %s  type:%d" % [i, anim.track_get_path(i), anim.track_get_type(i)])
				if anim.get_track_count() > 15:
					print("  ... 還有 %d 個 tracks" % (anim.get_track_count() - 15))
				break # 只顯示第一個動畫
	
	instance.free()
	print("\n=== 診斷完成 ===")


func _print_tree(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	print("%s%s (%s)" % [indent, node.name, node.get_class()])
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
