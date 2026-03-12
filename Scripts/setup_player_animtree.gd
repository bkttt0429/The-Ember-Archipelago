@tool
extends EditorScript

# 自动配置 Player.tscn 中的 AnimationTree
# 运行方式：在 Godot 编辑器中 File > Run

const PLAYER_SCENE_PATH = "res://Player/Player.tscn"
const LIB_PREFIX = "movement_animations/"

func _run():
	print("=== 開始配置 Player AnimationTree ===\n")
	
	# 打开场景
	var scene = load(PLAYER_SCENE_PATH) as PackedScene
	if not scene:
		push_error("無法載入 Player.tscn")
		return
	
	var player = scene.instantiate()
	
	# 查找 AnimationTree 节点
	var anim_tree = _find_node_by_path(player, "Animation/AnimationTree")
	if not anim_tree or not anim_tree is AnimationTree:
		push_error("找不到 AnimationTree 節點")
		player.queue_free()
		return
	
	print("找到 AnimationTree: ", anim_tree.get_path())
	
	# 创建 StateMachine
	var state_machine = AnimationNodeStateMachine.new()
	anim_tree.tree_root = state_machine
	
	# 1. 添加 Idle 状态
	print("添加 Idle 狀態...")
	var idle_node = AnimationNodeAnimation.new()
	idle_node.animation = LIB_PREFIX + "Idle"
	state_machine.add_node("Idle", idle_node, Vector2(400, 100))
	
	# 2. 添加 Locomotion BlendSpace2D
	print("添加 Locomotion BlendSpace2D...")
	var locomotion_bs = AnimationNodeBlendSpace2D.new()
	locomotion_bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	locomotion_bs.min_space = Vector2(-1, -1)
	locomotion_bs.max_space = Vector2(1, 1)
	
	# 添加 Walk 混合点 (magnitude 0.5)
	_add_blend_point(locomotion_bs, "Walk_Forward", Vector2(0, 0.5))
	_add_blend_point(locomotion_bs, "Walk_Backward", Vector2(0, -0.5))
	_add_blend_point(locomotion_bs, "Walk_Left", Vector2(-0.5, 0))
	_add_blend_point(locomotion_bs, "Walk_Right", Vector2(0.5, 0))
	_add_blend_point(locomotion_bs, "Walk_ForwardLeft", Vector2(-0.354, 0.354))
	_add_blend_point(locomotion_bs, "Walk_ForwardRight", Vector2(0.354, 0.354))
	_add_blend_point(locomotion_bs, "Walk_BackwardLeft", Vector2(-0.354, -0.354))
	_add_blend_point(locomotion_bs, "Walk_BackwardRight", Vector2(0.354, -0.354))
	
	# 添加 Run 混合点 (magnitude 1.0)
	_add_blend_point(locomotion_bs, "Run_Forward", Vector2(0, 1))
	_add_blend_point(locomotion_bs, "Run_Backward", Vector2(0, -1))
	_add_blend_point(locomotion_bs, "Run_Left", Vector2(-1, 0))
	_add_blend_point(locomotion_bs, "Run_Right", Vector2(1, 0))
	_add_blend_point(locomotion_bs, "Run_ForwardLeft", Vector2(-0.707, 0.707))
	_add_blend_point(locomotion_bs, "Run_ForwardRight", Vector2(0.707, 0.707))
	_add_blend_point(locomotion_bs, "Run_BackwardLeft", Vector2(-0.707, -0.707))
	_add_blend_point(locomotion_bs, "Run_BackwardRight", Vector2(0.707, -0.707))
	
	state_machine.add_node("Locomotion", locomotion_bs, Vector2(700, 100))
	
	# 3. 添加 Jump 状态
	print("添加 Jump 狀態...")
	
	var jump_start_node = AnimationNodeAnimation.new()
	jump_start_node.animation = LIB_PREFIX + "Jump01_Begin"
	state_machine.add_node("JumpStart", jump_start_node, Vector2(400, 250))
	
	var jump_loop_node = AnimationNodeAnimation.new()
	jump_loop_node.animation = LIB_PREFIX + "Jump"
	state_machine.add_node("JumpLoop", jump_loop_node, Vector2(700, 250))
	
	var jump_land_node = AnimationNodeAnimation.new()
	jump_land_node.animation = LIB_PREFIX + "Jump01_Land"
	state_machine.add_node("JumpLand", jump_land_node, Vector2(400, 400))
	
	# 4. 配置状态转换
	print("配置狀態轉換...")
	
	# Start -> Idle
	var trans_start_idle = AnimationNodeStateMachineTransition.new()
	trans_start_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	state_machine.add_transition("Start", "Idle", trans_start_idle)
	
	# Idle <-> Locomotion
	var trans_idle_loco = AnimationNodeStateMachineTransition.new()
	trans_idle_loco.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_idle_loco.advance_condition = "is_moving"
	trans_idle_loco.xfade_time = 0.2
	state_machine.add_transition("Idle", "Locomotion", trans_idle_loco)
	
	var trans_loco_idle = AnimationNodeStateMachineTransition.new()
	trans_loco_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_loco_idle.advance_condition = "not_moving"
	trans_loco_idle.xfade_time = 0.2
	state_machine.add_transition("Locomotion", "Idle", trans_loco_idle)
	
	# Idle/Locomotion -> JumpStart
	var trans_idle_jump = AnimationNodeStateMachineTransition.new()
	trans_idle_jump.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_idle_jump.advance_condition = "is_jumping"
	trans_idle_jump.xfade_time = 0.1
	state_machine.add_transition("Idle", "JumpStart", trans_idle_jump)
	
	var trans_loco_jump = AnimationNodeStateMachineTransition.new()
	trans_loco_jump.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_loco_jump.advance_condition = "is_jumping"
	trans_loco_jump.xfade_time = 0.1
	state_machine.add_transition("Locomotion", "JumpStart", trans_loco_jump)
	
	# JumpStart -> JumpLoop
	var trans_start_loop = AnimationNodeStateMachineTransition.new()
	trans_start_loop.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	trans_start_loop.xfade_time = 0.1
	state_machine.add_transition("JumpStart", "JumpLoop", trans_start_loop)
	
	# JumpLoop -> JumpLand
	var trans_loop_land = AnimationNodeStateMachineTransition.new()
	trans_loop_land.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_loop_land.advance_condition = "is_landing"
	trans_loop_land.xfade_time = 0.1
	state_machine.add_transition("JumpLoop", "JumpLand", trans_loop_land)
	
	# JumpLand -> Idle
	var trans_land_idle = AnimationNodeStateMachineTransition.new()
	trans_land_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	trans_land_idle.xfade_time = 0.2
	state_machine.add_transition("JumpLand", "Idle", trans_land_idle)
	
	# 5. 保存场景
	print("\n儲存場景...")
	var packed = PackedScene.new()
	packed.pack(player)
	var err = ResourceSaver.save(packed, PLAYER_SCENE_PATH)
	
	if err == OK:
		print("✅ AnimationTree 配置完成！")
		print("場景已儲存到: ", PLAYER_SCENE_PATH)
		print("\n配置的狀態:")
		print("  - Idle")
		print("  - Locomotion (16 個混合點)")
		print("  - JumpStart")
		print("  - JumpLoop")
		print("  - JumpLand")
		print("\n請重新運行遊戲測試！")
	else:
		push_error("儲存失敗，錯誤碼: " + str(err))
	
	player.queue_free()

func _find_node_by_path(root: Node, path: String) -> Node:
	var parts = path.split("/")
	var current = root
	for part in parts:
		var found = false
		for child in current.get_children():
			if child.name == part:
				current = child
				found = true
				break
		if not found:
			return null
	return current

func _add_blend_point(bs: AnimationNodeBlendSpace2D, anim_name: String, position: Vector2):
	var node = AnimationNodeAnimation.new()
	node.animation = LIB_PREFIX + anim_name
	bs.add_blend_point(node, position)
	print("  添加混合點: ", anim_name, " at ", position)
