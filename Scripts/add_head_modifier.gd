@tool
extends EditorScript

## 添加 HeadLookAtModifier 到 Player 場景的骨架中

func _run():
	print("=== 添加 HeadLookAtModifier ===")
	
	# 加載 Player 場景
	var scene = load("res://Player/Player.tscn") as PackedScene
	if not scene:
		push_error("無法加載 Player.tscn")
		return
	
	var player = scene.instantiate()
	
	# 找到骨架
	var skeleton = _find_skeleton(player)
	if not skeleton:
		push_error("找不到 Skeleton3D")
		player.queue_free()
		return
	
	print("找到骨架: " + skeleton.name)
	
	# 檢查是否已存在
	for child in skeleton.get_children():
		if child.name == "HeadLookAtModifier":
			print("HeadLookAtModifier 已存在，跳過")
			player.queue_free()
			return
	
	# 創建新的 SkeletonModifier3D 節點
	var modifier = SkeletonModifier3D.new()
	modifier.name = "HeadLookAtModifier"
	
	# 加載腳本
	var script = load("res://Player/systems/HeadLookAtModifier.gd")
	if script:
		modifier.set_script(script)
		print("已設定腳本")
	else:
		push_error("無法加載 HeadLookAtModifier.gd")
		player.queue_free()
		return
	
	# 添加到骨架
	skeleton.add_child(modifier)
	modifier.owner = player
	
	print("已添加 HeadLookAtModifier 到 " + skeleton.name)
	
	# 保存場景
	var packed = PackedScene.new()
	var err = packed.pack(player)
	if err == OK:
		err = ResourceSaver.save(packed, "res://Player/Player.tscn")
		if err == OK:
			print("✅ 場景已保存!")
		else:
			push_error("保存失敗: " + str(err))
	else:
		push_error("打包失敗: " + str(err))
	
	player.queue_free()
	print("=== 完成 ===")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
