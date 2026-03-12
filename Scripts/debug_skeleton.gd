@tool
extends EditorScript

## 調試骨架和物理骨骼設定

func _run():
	print("=== 骨架調試 ===")
	
	var scene = load("res://Assets/Models/character/mannequin.fbx") as PackedScene
	if not scene:
		push_error("無法加載模型")
		return
	
	var instance = scene.instantiate()
	_find_and_debug_skeleton(instance, "")
	instance.queue_free()
	
	print("=== 完成 ===")

func _find_and_debug_skeleton(node: Node, indent: String):
	if node is Skeleton3D:
		print(indent + "Skeleton3D: " + node.name)
		
		# 查找 Head 骨骼
		var head_idx = node.find_bone("Head")
		print(indent + "  Head 骨骼索引: %d" % head_idx)
		
		if head_idx >= 0:
			var rest = node.get_bone_rest(head_idx)
			var pose = node.get_bone_pose(head_idx)
			print(indent + "  Head Rest: %s" % str(rest))
			print(indent + "  Head Pose: %s" % str(pose))
		
		# 列出所有子節點（包括修改器）
		print(indent + "  子節點:")
		for child in node.get_children():
			print(indent + "    - %s (%s)" % [child.name, child.get_class()])
			
			if child is PhysicalBoneSimulator3D:
				print(indent + "      ⚠️ PhysicalBoneSimulator3D 可能覆蓋骨骼姿勢!")
			
			if child is SkeletonModifier3D:
				print(indent + "      修改器 active: %s" % child.active)
	
	for child in node.get_children():
		_find_and_debug_skeleton(child, indent + "  ")
