@tool
extends EditorScript
## 重建 AnimationTree StateMachine - 純條件過渡
## 在 Godot Editor 運行：Script → Run

func _run() -> void:
	print("=== 開始重建 StateMachine 條件過渡 ===")
	
	# 找到測試場景
	var scene_path = "res://Player/test/PlayerCapsuleTest.tscn"
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("無法載入場景: " + scene_path)
		return
	
	var root = scene.instantiate()
	var player = root.get_node_or_null("Player")
	if not player:
		push_error("找不到 Player 節點")
		return
	
	var anim_tree = player.get_node_or_null("AnimationTree") as AnimationTree
	if not anim_tree:
		push_error("找不到 AnimationTree")
		return
	
	var state_machine = anim_tree.tree_root as AnimationNodeStateMachine
	if not state_machine:
		push_error("tree_root 不是 AnimationNodeStateMachine")
		return
	
	print("找到 StateMachine！開始配置過渡...")
	
	# 移除所有現有過渡
	var transitions_to_remove = []
	for i in range(100): # 假設最多 100 個過渡
		# 無法直接列出過渡，跳過清除步驟
		pass
	
	# 重新配置過渡
	_setup_transitions(state_machine)
	
	# 保存場景
	var packed = PackedScene.new()
	packed.pack(root)
	var err = ResourceSaver.save(packed, scene_path)
	if err == OK:
		print("場景保存成功！")
	else:
		push_error("保存失敗: " + str(err))
	
	root.queue_free()
	print("=== 完成！請重新載入場景 ===")

func _setup_transitions(sm: AnimationNodeStateMachine) -> void:
	# 定義所有需要的過渡
	# 格式: [from, to, condition_name, xfade_time]
	var transitions = [
		# Start -> movement (自動)
		["Start", "movement", "", 0.0],
		
		# movement -> 其他狀態
		["movement", "jump_start", "jump", 0.1],
		["movement", "crouch_idle", "crouch_idle", 0.15],
		
		# 跳躍流程
		["jump_start", "jump_loop", "falling", 0.1],
		["jump_loop", "jump_land", "landed", 0.1],
		["jump_land", "movement", "grounded", 0.15],
		
		# 蹲下
		["crouch_idle", "crouch_fwd", "crouch_walk", 0.1],
		["crouch_fwd", "crouch_idle", "crouch_idle", 0.1],
		["crouch_idle", "movement", "stand_up", 0.2],
		["crouch_fwd", "movement", "stand_up", 0.2],
	]
	
	for t in transitions:
		var from_state = t[0] as String
		var to_state = t[1] as String
		var condition = t[2] as String
		var xfade = t[3] as float
		
		# 檢查節點是否存在
		if not sm.has_node(from_state):
			print("  跳過 (找不到 from): ", from_state)
			continue
		if not sm.has_node(to_state):
			print("  跳過 (找不到 to): ", to_state)
			continue
		
		# 建立過渡
		var trans = AnimationNodeStateMachineTransition.new()
		trans.xfade_time = xfade
		
		if condition.is_empty():
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		else:
			trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			trans.advance_condition = condition
		
		# 檢查過渡是否已存在，如果存在則移除
		if sm.has_transition(from_state, to_state):
			sm.remove_transition(from_state, to_state)
		
		sm.add_transition(from_state, to_state, trans)
		print("  ✓ ", from_state, " -> ", to_state, " (", condition if not condition.is_empty() else "auto", ")")
