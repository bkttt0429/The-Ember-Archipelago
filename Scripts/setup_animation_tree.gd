@tool
extends EditorScript

# 修正版：動畫名稱需要加上 library 前綴 "mx/"

const OUTPUT_PATH = "res://Player/player_animation_tree.tres"

func _run():
	print("開始建立 AnimationTree (修正版)...")
	
	# 建立根狀態機
	var root_sm = AnimationNodeStateMachine.new()
	
	# 建立 Idle 節點 - 注意前綴 "mx/"
	var idle_node = AnimationNodeAnimation.new()
	idle_node.animation = &"mx/idle"
	root_sm.add_node("Idle", idle_node)
	root_sm.set_node_position("Idle", Vector2(100, 100))
	
	# 建立 Locomotion BlendSpace2D
	var loco_bs = AnimationNodeBlendSpace2D.new()
	loco_bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	
	# 8 方向動畫 - 注意前綴 "mx/"
	var directions = [
		{"name": "mx/mx_f_walk", "pos": Vector2(0, 1)},
		{"name": "mx/mx_fr_walk", "pos": Vector2(0.707, 0.707)},
		{"name": "mx/mx_r_walk", "pos": Vector2(1, 0)},
		{"name": "mx/mx_br_walk", "pos": Vector2(0.707, -0.707)},
		{"name": "mx/mx_b_walk", "pos": Vector2(0, -1)},
		{"name": "mx/mx_bl_walk", "pos": Vector2(-0.707, -0.707)},
		{"name": "mx/mx_l_walk", "pos": Vector2(-1, 0)},
		{"name": "mx/mx_fl_walk", "pos": Vector2(-0.707, 0.707)}
	]
	
	for d in directions:
		var anim = AnimationNodeAnimation.new()
		anim.animation = StringName(d.name)
		loco_bs.add_blend_point(anim, d.pos)
	
	root_sm.add_node("Locomotion", loco_bs)
	root_sm.set_node_position("Locomotion", Vector2(300, 100))
	
	# 建立 Transitions
	var tr_start = AnimationNodeStateMachineTransition.new()
	tr_start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	root_sm.add_transition("Start", "Idle", tr_start)
	
	var tr_idle_loco = AnimationNodeStateMachineTransition.new()
	tr_idle_loco.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	tr_idle_loco.xfade_time = 0.2
	tr_idle_loco.advance_condition = &"is_moving"
	root_sm.add_transition("Idle", "Locomotion", tr_idle_loco)
	
	var tr_loco_idle = AnimationNodeStateMachineTransition.new()
	tr_loco_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	tr_loco_idle.xfade_time = 0.2
	tr_loco_idle.advance_condition = &"not_moving"
	root_sm.add_transition("Locomotion", "Idle", tr_loco_idle)
	
	# 儲存
	var error = ResourceSaver.save(root_sm, OUTPUT_PATH)
	if error == OK:
		print("成功建立: ", OUTPUT_PATH)
		print("動畫名稱已加上 'mx/' 前綴")
	else:
		push_error("儲存失敗: %d" % error)
