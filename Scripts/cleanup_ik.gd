@tool
extends EditorScript

## 清理 Foot IK 節點 - 移除不工作的 TwoBoneIK3D
## 運行方式: 打開 Player.tscn，然後 File → Run

func _run() -> void:
	var edited_scene = EditorInterface.get_edited_scene_root()
	
	if not edited_scene:
		printerr("請先打開 Player.tscn 場景!")
		return
	
	var skeleton = edited_scene.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if not skeleton:
		printerr("找不到 GeneralSkeleton!")
		return
	
	print("找到 Skeleton: ", skeleton.name)
	print("子節點數量: ", skeleton.get_child_count())
	
	# 列出所有子節點
	var to_remove = []
	for child in skeleton.get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
		
		# 標記要移除的 TwoBoneIK3D 節點
		if child.get_class() == "TwoBoneIK3D":
			to_remove.append(child)
	
	# 移除 TwoBoneIK3D 節點
	for node in to_remove:
		print("移除: ", node.name)
		node.free()
	
	if to_remove.size() > 0:
		print("\n✅ 已移除 %d 個 TwoBoneIK3D 節點" % to_remove.size())
		print("請保存場景 (Ctrl+S)")
	else:
		print("\n沒有找到需要移除的 TwoBoneIK3D 節點")
