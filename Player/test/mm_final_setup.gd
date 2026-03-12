@tool
extends EditorScript
## Motion Matching 最終配置腳本
## 
## 修復：
## 1. AnimationTree.tree_root 需要 AnimationNodeBlendTree（不是直接設 MMAnimationNode）
## 2. MMAnimationNode 要連接到 BlendTree 的 output
## 3. Player (MMCharacter) 需要設定 trajectory/history 參數
##
## 用法: File > Run Script > 選擇此腳本

func _run() -> void:
	print("\n=== 最終 Motion Matching 配置 ===\n")
	
	var root := get_editor_interface().get_edited_scene_root()
	if not root:
		printerr("ERROR: 沒有打開的場景")
		return
	
	# 1. 找到 Player (MMCharacter)
	var player = root.find_child("Player", false)
	if not player:
		printerr("ERROR: 找不到 Player 節點")
		return
	print("Player 類型: ", player.get_class())
	
	# 2. 設定 MMCharacter 參數（參考 demo）
	if player.get_class() == "MMCharacter":
		# 軌跡設定
		player.set("trajectory_point_count", 4) # 4 個未來點
		player.set("trajectory_delta_time", 0.5) # 每 0.5s 一個點
		player.set("history_point_count", 3) # 3 個歷史點
		player.set("history_delta_time", 0.1) # 每 0.1s 一個點
		player.set("halflife", 0.2) # 彈簧阻尼半衰期
		player.set("check_environment", false) # 暫時不檢查環境碰撞
		print("✓ MMCharacter 軌跡參數已設定")
		print("  trajectory_point_count=4, trajectory_delta_time=0.5")
		print("  history_point_count=3, history_delta_time=0.1")
		print("  halflife=0.2")
	else:
		printerr("WARNING: Player 不是 MMCharacter 類型: ", player.get_class())
	
	# 3. 找到 AnimationTree
	var anim_tree: AnimationTree = player.find_child("AnimationTree", false)
	if not anim_tree:
		printerr("ERROR: 找不到 AnimationTree")
		return
	print("✓ AnimationTree 找到")
	print("  tree_root: ", anim_tree.tree_root)
	
	# 4. 找到 AnimationPlayer 中的 MMAnimationLibrary
	var anim_player: AnimationPlayer = player.find_child("AnimationPlayer", false)
	if not anim_player:
		printerr("ERROR: 找不到 AnimationPlayer")
		return
	
	var mm_lib = anim_player.get_animation_library("mm")
	if not mm_lib:
		printerr("ERROR: 找不到 'mm' library")
		return
	print("✓ mm library: ", mm_lib.get_class(), " (", mm_lib.get_animation_list().size(), " animations)")
	
	# 5. 建立 AnimationNodeBlendTree + MMAnimationNode（參考 demo 結構）
	var blend_tree := AnimationNodeBlendTree.new()
	
	# 建立 MMAnimationNode
	if not ClassDB.class_exists("MMAnimationNode"):
		printerr("ERROR: MMAnimationNode 類型不存在")
		return
	
	var mm_node = ClassDB.instantiate("MMAnimationNode")
	print("✓ MMAnimationNode 建立: ", mm_node.get_class())
	
	# 設定 MMAnimationNode 的 animation_library
	mm_node.set("animation_library", mm_lib)
	print("✓ MMAnimationNode.animation_library = mm library")
	
	# 加入 BlendTree
	blend_tree.add_node("MMAnimationNode", mm_node, Vector2(0, 140))
	print("✓ MMAnimationNode 加入 BlendTree")
	
	# 連接到 output
	blend_tree.connect_node("output", 0, "MMAnimationNode")
	print("✓ MMAnimationNode → output 連接")
	
	# 設定 tree_root
	anim_tree.tree_root = blend_tree
	print("✓ AnimationTree.tree_root = AnimationNodeBlendTree")
	
	# 6. 設定 AnimationTree 的 advance_expression_base_node
	anim_tree.advance_expression_base_node = NodePath("..")
	print("✓ advance_expression_base_node = '..'")
	
	# 7. 確認 AnimationTree 是 active
	anim_tree.active = true
	print("✓ AnimationTree.active = true")
	
	# 8. 保存場景
	EditorInterface.save_scene()
	print("\n✓ 場景已保存")
	
	# 驗證
	print("\n--- 驗證 ---")
	print("AnimationTree.tree_root: ", anim_tree.tree_root)
	print("tree_root class: ", anim_tree.tree_root.get_class() if anim_tree.tree_root else "null")
	
	# 檢查 MMQueryInput 參數
	var props := anim_tree.get_property_list()
	for p in props:
		if "MMQueryInput" in str(p.get("hint_string", "")):
			print("✓ 發現 MMQueryInput 參數: ", p["name"])
	
	print("\n=== 配置完成！按 F5 測試 ===")
	print("操作：WASD 移動、Shift 衝刺、Space 跳躍、ESC 切換滑鼠")
