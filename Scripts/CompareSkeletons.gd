@tool
extends EditorScript

func _run():
	# 1. Player Model (Mannequin)
	var player_model_path = "res://Assets/Models/character/mannequin.fbx"
	# 2. Target Animation Source (UAL1)
	var anim_source_path = "res://Player/assets/characters/player/motion/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
	
	print("=== 骨架比較報告 ===")
	print("Player Model: ", player_model_path)
	print("Source Model: ", anim_source_path)
	print("---------------------------------------------------")

	var player_bones = _get_bones_from_path(player_model_path, "Player(Mannequin)")
	var source_bones = _get_bones_from_path(anim_source_path, "Source(UAL1)")
	
	print("\n=== 差異分析 ===")
	print(str("Player 骨頭數量: ", player_bones.size()))
	print(str("Source 骨頭數量: ", source_bones.size()))
	
	print("\n[只存在於 Player 的骨頭] (可能導致動畫無法驅動這些部位)")
	var unique_player = []
	for b in player_bones:
		if not source_bones.has(b):
			unique_player.append(b)
	print(unique_player)
	
	print("\n[只存在於 Source 的骨頭] (可能導致包含無效的動畫軌道)")
	var unique_source = []
	for b in source_bones:
		if not player_bones.has(b):
			unique_source.append(b)
	print(unique_source)

func _get_bones_from_path(path: String, label: String) -> Array:
	if not FileAccess.file_exists(path):
		printerr("錯誤：找不到檔案 ", path)
		return []
		
	var scene = load(path)
	if not scene:
		printerr("錯誤：無法載入 ", path)
		return []
		
	var inst = scene.instantiate()
	var skeleton = _find_skeleton(inst)
	var bones = []
	
	if skeleton:
		print("\n載入 ", label, " 成功。骨架名稱: ", skeleton.name)
		for i in range(skeleton.get_bone_count()):
			bones.append(skeleton.get_bone_name(i))
	else:
		printerr("錯誤：在 ", label, " 中找不到 Skeleton3D 節點！")
		_print_tree(inst)
	
	inst.free()
	return bones

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found: return found
	return null

func _print_tree(node: Node, depth: int = 0):
	var indent = ""
	for i in range(depth): indent += "  "
	print(indent + "- " + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		_print_tree(child, depth + 1)
