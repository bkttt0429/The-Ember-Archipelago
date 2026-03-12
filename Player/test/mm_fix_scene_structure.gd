@tool
extends EditorScript
## 修復場景結構：將 Player (CharacterBody3D) 改為 MMCharacter
##
## 問題：Demo 中根節點就是 MMCharacter（自帶 move_and_slide），
## 但我們的場景中 Player 是 CharacterBody3D，MMCharacter 是子節點。
## MMCharacter 呼叫 move_and_slide() 但沒有碰撞體，導致掉落。
##
## 解法：直接在 .tscn 中將 Player 節點的 type 改成 MMCharacter，
## 並把原本子節點 MMCharacter 的屬性移到 Player 上，然後刪除子節點。
##
## 用法: File > Run Script > 選擇此腳本

func _run() -> void:
	print("\n=== 修復場景結構 ===\n")
	
	var root := get_editor_interface().get_edited_scene_root()
	if not root:
		printerr("ERROR: 沒有打開的場景")
		return
	
	# 找到 Player 節點
	var player := root.find_child("Player", false) as CharacterBody3D
	if not player:
		# 也許 Player 就是 root？
		player = root as CharacterBody3D
		if not player:
			printerr("ERROR: 找不到 Player 節點")
			return
	
	print("Player 類型: ", player.get_class(), " at ", player.get_path())
	
	# 找到 MMCharacter 子節點
	var mm_char = player.find_child("MMCharacter", false)
	if mm_char:
		print("MMCharacter 子節點: ", mm_char.get_class(), " at ", mm_char.get_path())
		print("  skeleton = ", mm_char.get("skeleton"))
		print("  animation_tree = ", mm_char.get("animation_tree"))
		print("  synchronizer = ", mm_char.get("synchronizer"))
	else:
		print("沒有 MMCharacter 子節點（已經是正確結構？）")
	
	# 檢查 Player 是否已經是 MMCharacter
	if player.get_class() == "MMCharacter":
		print("✓ Player 已經是 MMCharacter，無需修改")
		return
	
	print("\n⚠ 場景結構問題確認：")
	print("  Player 是 CharacterBody3D，需要改成 MMCharacter")
	print("  MMCharacter 是子節點，碰撞體和模型都在 Player 上")
	print("")
	print("由於 EditorScript 無法直接修改節點類型，")
	print("我會透過修改 .tscn 檔案來修復。")
	print("")
	
	# 讀取 tscn 檔案
	var scene_path := root.scene_file_path
	if scene_path.is_empty():
		printerr("ERROR: 場景沒有檔案路徑")
		return
	
	var abs_path := ProjectSettings.globalize_path(scene_path)
	print("場景檔案: ", abs_path)
	
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if not file:
		printerr("ERROR: 無法讀取場景檔案: ", FileAccess.get_open_error())
		return
	
	var content := file.get_as_text()
	file.close()
	
	# 步驟 1: 把 Player 的類型從 CharacterBody3D 改成 MMCharacter
	# 並加上 node_paths（MMCharacter 需要）
	var old_player := '[node name="Player" type="CharacterBody3D" parent="." unique_id=2121761385]'
	var new_player := '[node name="Player" type="MMCharacter" parent="." unique_id=2121761385 node_paths=PackedStringArray("skeleton", "animation_tree")]'
	
	if content.find(old_player) == -1:
		printerr("ERROR: 找不到 Player 節點定義")
		printerr("  嘗試尋找的文字: ", old_player)
		return
	
	content = content.replace(old_player, new_player)
	print("✓ Player 類型已改為 MMCharacter")
	
	# 步驟 2: 在 Player 節點定義後加入 MMCharacter 屬性
	# 我們需要加入 skeleton 和 animation_tree 路徑
	var player_transform := "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, 0)"
	var player_with_props := player_transform + "\n"
	player_with_props += 'skeleton = NodePath("Visuals/Human/Armature/GeneralSkeleton")\n'
	player_with_props += 'animation_tree = NodePath("AnimationTree")\n'
	
	# 取得 synchronizer
	if mm_char and mm_char.get("synchronizer"):
		# synchronizer 是 SubResource，我們需要找到它的 ID
		pass # 會從刪除的 MMCharacter 節點複製
	
	content = content.replace(player_transform, player_with_props)
	print("✓ 加入 skeleton 和 animation_tree 屬性")
	
	# 步驟 3: 刪除 MMCharacter 子節點定義
	# 找到 MMCharacter 區塊並移除
	var mm_char_block := '[node name="MMCharacter" type="MMCharacter" parent="Player" unique_id=175367558 node_paths=PackedStringArray("skeleton", "animation_tree")]\n'
	mm_char_block += 'skeleton = NodePath("../Visuals/Human/Armature/GeneralSkeleton")\n'
	mm_char_block += 'animation_tree = NodePath("../AnimationTree")\n'
	mm_char_block += 'synchronizer = SubResource("MMMixSynchronizer_1")\n'
	
	if content.find(mm_char_block) != -1:
		content = content.replace(mm_char_block, "")
		print("✓ 已移除 MMCharacter 子節點")
	else:
		print("⚠ 找不到完整的 MMCharacter 區塊，嘗試部分替換...")
		# 至少移除節點定義行
		var mm_node_line := '[node name="MMCharacter" type="MMCharacter" parent="Player"'
		var idx := content.find(mm_node_line)
		if idx != -1:
			# 找到這一行的結尾和下一個 [node 的開頭
			var next_node := content.find("\n[node ", idx + 1)
			if next_node != -1:
				var block_to_remove := content.substr(idx, next_node - idx + 1)
				content = content.replace(block_to_remove, "")
				print("✓ 已移除 MMCharacter 子節點區塊")
		
	# 步驟 4: 更新 PlayerController 的 character 路徑
	# 原本指向 "../MMCharacter"，現在 Player 本身就是 MMCharacter
	content = content.replace(
		'character = NodePath("../MMCharacter")',
		'character = NodePath("..")'
	)
	print("✓ PlayerController.character 路徑已更新")
	
	# 步驟 5: 更新 CameraPivot 的 character 路徑
	content = content.replace(
		'character = NodePath("../Player/MMCharacter")',
		'character = NodePath("../Player")'
	)
	print("✓ CameraPivot.character 路徑已更新")
	
	# 步驟 6: 加入 synchronizer（需要加在 Player 的屬性中）
	# 在 animation_tree 行後面加入
	content = content.replace(
		'animation_tree = NodePath("AnimationTree")\n',
		'animation_tree = NodePath("AnimationTree")\nsynchronizer = SubResource("MMMixSynchronizer_1")\n'
	)
	print("✓ synchronizer 已加入")
	
	# 寫回
	file = FileAccess.open(abs_path, FileAccess.WRITE)
	if not file:
		printerr("ERROR: 無法寫入場景檔案")
		return
	
	file.store_string(content)
	file.close()
	
	print("\n✓ 場景檔案已修改！")
	print("\n⚠ 重要：請重新載入場景！")
	print("  方法：按 Ctrl+Shift+T 重開目前場景，或關閉再重新打開")
	print("\n=== 完成 ===")
