@tool
extends EditorScript

## 添加 LookAtModifier3D 到 Player 骨架
## Godot 4.3+ 內建節點，最穩定的頭部追蹤方式

func _run():
	print("=== 添加 LookAtModifier3D ===")
	
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
		if child is LookAtModifier3D:
			print("LookAtModifier3D 已存在，跳過")
			player.queue_free()
			return
	
	# 創建 LookAtModifier3D
	var look_at = LookAtModifier3D.new()
	look_at.name = "HeadLookAt"
	
	# 設定骨骼
	var head_idx = skeleton.find_bone("Head")
	if head_idx >= 0:
		look_at.bone_name = "Head"
		look_at.bone = head_idx
		print("Head bone index: %d" % head_idx)
	else:
		push_error("找不到 Head 骨骼")
		player.queue_free()
		return
	
	# 設定參數
	look_at.forward_axis = 5 # FORWARD_AXIS_Y (通常 Mixamo 骨骼)
	look_at.primary_rotation_axis = 1 # ROTATION_AXIS_Y
	look_at.use_secondary_rotation = true
	look_at.secondary_rotation_axis = 0 # ROTATION_AXIS_X
	look_at.symmetry_limitation = false
	look_at.primary_limit_angle = deg_to_rad(50.0) # 水平限制
	look_at.primary_damp_threshold = deg_to_rad(35.0)
	look_at.secondary_limit_angle = deg_to_rad(30.0) # 垂直限制
	look_at.secondary_damp_threshold = deg_to_rad(25.0)
	look_at.transition_speed = 8.0
	look_at.active = true
	
	# 注意：target_node 需要在運行時設定，因為它需要指向場景中的節點
	# 我們會創建一個目標節點
	
	# 添加到骨架
	skeleton.add_child(look_at)
	look_at.owner = player
	
	print("已添加 LookAtModifier3D")
	
	# 創建目標節點（放在 Player 根節點下）
	var target = Node3D.new()
	target.name = "LookAtTarget"
	player.add_child(target)
	target.owner = player
	target.position = Vector3(0, 1.6, -5) # 預設在頭部前方5米
	
	print("已創建 LookAtTarget 節點")
	
	# 移除舊的 HeadLookAt 節點
	var old_look_at = player.get_node_or_null("HeadLookAt")
	if old_look_at:
		old_look_at.queue_free()
		print("已移除舊的 HeadLookAt 節點")
	
	# 保存場景
	var packed = PackedScene.new()
	var err = packed.pack(player)
	if err == OK:
		err = ResourceSaver.save(packed, "res://Player/Player.tscn")
		if err == OK:
			print("✅ 場景已保存!")
			print("⚠️ 注意：請在編輯器中手動設定 LookAtModifier3D 的 target_node 為 LookAtTarget")
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
