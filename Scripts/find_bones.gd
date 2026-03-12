@tool
extends EditorScript

# 查找骨架中的所有骨骼名稱

func _run():
	print("=== 查找骨骼名稱 ===")
	
	var mannequin = load("res://Assets/Models/character/mannequin.fbx") as PackedScene
	if not mannequin:
		push_error("無法載入 mannequin.fbx")
		return
	
	var instance = mannequin.instantiate()
	
	# 遍歷查找 Skeleton3D
	_find_skeleton(instance, "")
	
	instance.queue_free()

func _find_skeleton(node: Node, indent: String):
	if node is Skeleton3D:
		print("%sSkeleton3D: %s" % [indent, node.name])
		for i in range(node.get_bone_count()):
			var bone_name = node.get_bone_name(i)
			var parent_idx = node.get_bone_parent(i)
			var parent_name = node.get_bone_name(parent_idx) if parent_idx >= 0 else "ROOT"
			print("%s  [%d] %s (parent: %s)" % [indent, i, bone_name, parent_name])
	
	for child in node.get_children():
		_find_skeleton(child, indent + "  ")
