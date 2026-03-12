@tool
extends EditorScript

# 直接配置 Player.tscn 中的 AnimationTree BlendSpace2D
# 運行方式：Godot 編輯器中 File > Run

func _run():
	print("=== 開始配置 Player AnimationTree ===\n")
	
	# 載入場景
	var player_scene = load("res://Player/Player.tscn") as PackedScene
	if not player_scene:
		push_error("無法載入 Player.tscn")
		return
	
	var player = player_scene.instantiate()
	
	# 找到 AnimationTree 和 AnimationPlayer
	var anim_tree = player.get_node_or_null("Animation/AnimationTree")
	var anim_player = player.get_node_or_null("Animation/AnimationPlayer")
	
	if not anim_tree or not anim_player:
		push_error("找不到 AnimationTree 或 AnimationPlayer")
		player.queue_free()
		return
	
	print("找到 AnimationTree 和 AnimationPlayer")
	
	# 檢查動畫庫
	var lib_names = anim_player.get_animation_library_list()
	print("現有動畫庫: ", lib_names)
	
	# 獲取動畫庫
	var lib = null
	var lib_prefix = ""
	
	if anim_player.has_animation_library("movement_animations"):
		lib = anim_player.get_animation_library("movement_animations")
		lib_prefix = "movement_animations/"
		print("使用 movement_animations 庫")
	elif anim_player.has_animation_library(""):
		lib = anim_player.get_animation_library("")
		lib_prefix = ""
		print("使用預設庫")
	
	if not lib:
		push_error("找不到動畫庫")
		player.queue_free()
		return
	
	var anims = lib.get_animation_list()
	print("可用動畫 (", anims.size(), "): ", anims)
	
	# 建立 StateMachine
	var state_machine = AnimationNodeStateMachine.new()
	
	# 1. Idle 狀態
	var idle_node = AnimationNodeAnimation.new()
	var idle_found = false
	
	for a in anims:
		if a == "Idle" or "idle" in a.to_lower():
			idle_node.animation = lib_prefix + a
			idle_found = true
			print("  找到 Idle: ", idle_node.animation)
			break
	
	if idle_found:
		state_machine.add_node("Idle", idle_node)
	
	# 2. Locomotion BlendSpace2D
	var locomotion_bs = AnimationNodeBlendSpace2D.new()
	locomotion_bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	
	# 設定混合參數範圍
	locomotion_bs.min_space = Vector2(-1, -1)
	locomotion_bs.max_space = Vector2(1, 1)
	locomotion_bs.snap = Vector2(0.1, 0.1)
	
	# 8方向映射
	var directions = {
		"Forward": Vector2(0, 1),
		"Backward": Vector2(0, -1),
		"Left": Vector2(-1, 0),
		"Right": Vector2(1, 0),
		"ForwardLeft": Vector2(-1, 1).normalized(),
		"ForwardRight": Vector2(1, 1).normalized(),
		"BackwardLeft": Vector2(-1, -1).normalized(),
		"BackwardRight": Vector2(1, -1).normalized()
	}
	
	var walk_count = 0
	var run_count = 0
	
	print("\n添加混合點:")
	for dir_name in directions.keys():
		var vec = directions[dir_name]
		
		# Walk (magnitude 0.5)
		for a in anims:
			if a == "Walk_" + dir_name:
				var walk_node = AnimationNodeAnimation.new()
				walk_node.animation = lib_prefix + a
				var pos = vec * 0.5
				locomotion_bs.add_blend_point(walk_node, pos)
				print("  Walk ", dir_name, " at ", pos)
				walk_count += 1
				break
		
		# Run (magnitude 1.0)
		for a in anims:
			if a == "Run_" + dir_name:
				var run_node = AnimationNodeAnimation.new()
				run_node.animation = lib_prefix + a
				var pos = vec * 1.0
				locomotion_bs.add_blend_point(run_node, pos)
				print("  Run ", dir_name, " at ", pos)
				run_count += 1
				break
	
	state_machine.add_node("Locomotion", locomotion_bs)
	print("\nBlendSpace2D: ", walk_count, " walk + ", run_count, " run = ", locomotion_bs.get_blend_point_count(), " 點")
	
	# 3. 過渡設置
	var trans_start_idle = AnimationNodeStateMachineTransition.new()
	trans_start_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	state_machine.add_transition("Start", "Idle", trans_start_idle)
	
	var trans_idle_loco = AnimationNodeStateMachineTransition.new()
	trans_idle_loco.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_idle_loco.advance_condition = "is_moving"
	trans_idle_loco.xfade_time = 0.2
	state_machine.add_transition("Idle", "Locomotion", trans_idle_loco)
	
	var trans_loco_idle = AnimationNodeStateMachineTransition.new()
	trans_loco_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_loco_idle.advance_condition = "is_moving"
	trans_loco_idle.advance_expression = "!is_moving"
	trans_loco_idle.xfade_time = 0.2
	state_machine.add_transition("Locomotion", "Idle", trans_loco_idle)
	
	print("\n過渡設置完成")
	
	# 設置到 AnimationTree
	anim_tree.tree_root = state_machine
	
	# 保存場景
	var packed = PackedScene.new()
	var pack_err = packed.pack(player)
	if pack_err != OK:
		push_error("打包場景失敗")
		player.queue_free()
		return
	
	var save_err = ResourceSaver.save(packed, "res://Player/Player.tscn")
	
	if save_err == OK:
		print("\n=== 成功！ ===")
		print("✓ Player.tscn 已更新")
		print("✓ AnimationTree StateMachine 包含: Idle, Locomotion")
		print("✓ BlendSpace2D 包含 ", locomotion_bs.get_blend_point_count(), " 個混合點")
		print("\n請重新載入場景以查看變更")
	else:
		push_error("保存失敗，錯誤碼: " + str(save_err))
	
	player.queue_free()
