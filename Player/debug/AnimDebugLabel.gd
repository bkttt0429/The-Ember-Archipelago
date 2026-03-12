extends Label

## 實時顯示 AnimationSystem 的 blend_position debug 信息

var player: CharacterBody3D
var anim_tree: AnimationTree

func _ready():
	# 從父節點的父節點（Player）找 AnimationTree
	var canvas_layer = get_parent()
	if canvas_layer:
		player = canvas_layer.get_parent()
		if player:
			anim_tree = player.find_child("AnimationTree", true, false)
	
	if not anim_tree:
		text = "❌ No AnimationTree found"
		return

func _get_input_axis(neg_action: String, pos_action: String, neg_fallback: String, pos_fallback: String) -> float:
	var neg_val = 0.0
	if InputMap.has_action(neg_action): neg_val = Input.get_action_strength(neg_action)
	elif InputMap.has_action(neg_fallback): neg_val = Input.get_action_strength(neg_fallback)
	
	var pos_val = 0.0
	if InputMap.has_action(pos_action): pos_val = Input.get_action_strength(pos_action)
	elif InputMap.has_action(pos_fallback): pos_val = Input.get_action_strength(pos_fallback)
	
	return pos_val - neg_val

func _process(_delta):
	if not anim_tree:
		return
	
	var blend_pos = anim_tree.get("parameters/movement/blend_position")
	var current_node = anim_tree.get("parameters/playback")
	var current_state = ""
	if current_node:
		current_state = current_node.get_current_node()
	
	# 獲取移動向量
	var mv = Vector2.ZERO
	if player and player.has_method("get_move_vector"):
		var move_vec = player.get_move_vector()
		if move_vec is Vector3:
			mv = Vector2(move_vec.x, move_vec.z)
		elif move_vec is Vector2:
			mv = move_vec
	
	# 嘗試獲取最接近的動畫名稱
	var closest_anim = "Unknown"
	if anim_tree and anim_tree.tree_root:
		var state_machine = anim_tree.tree_root as AnimationNodeStateMachine
		if state_machine and state_machine.has_node("movement"):
			var blend_space = state_machine.get_node("movement") as AnimationNodeBlendSpace2D
			if blend_space:
				var min_dist = 999.0
				for i in range(blend_space.get_blend_point_count()):
					var point_pos = blend_space.get_blend_point_position(i)
					var dist = point_pos.distance_to(blend_pos)
					if dist < min_dist:
						min_dist = dist
						var node = blend_space.get_blend_point_node(i)
						if node is AnimationNodeAnimation:
							closest_anim = node.animation
	
	text = """🎮 Animation Debug
State: %s
D-Pad: X=%.2f, Y=%.2f
Inputs: (%.2f, %.2f)
Blend: (%.2f, %.2f)
Anim: %s

前進(W): Y+    | 實際: %.2f (%s)
後退(S): Y-    | 實際: %.2f (%s)
左移(A): X-    | 實際: %.2f (%s)
右移(D): X+    | 實際: %.2f (%s)
""" % [
		current_state,
		_get_input_axis("move_left", "move_right", "ui_left", "ui_right"),
		_get_input_axis("move_back", "move_forward", "ui_down", "ui_up"),
		mv.x, mv.y,
		blend_pos.x, blend_pos.y,
		closest_anim,
		blend_pos.y, "✅" if blend_pos.y > 0.1 else ("❌" if blend_pos.y < -0.1 else "-"),
		blend_pos.y, "✅" if blend_pos.y < -0.1 else ("❌" if blend_pos.y > 0.1 else "-"),
		blend_pos.x, "✅" if blend_pos.x < -0.1 else ("❌" if blend_pos.x > 0.1 else "-"),
		blend_pos.x, "✅" if blend_pos.x > 0.1 else ("❌" if blend_pos.x < -0.1 else "-")
	]
	
	# Output 日誌輸出 (每秒一次)
	if Engine.get_process_frames() % 60 == 0:
		var keys = ""
		if Input.is_key_pressed(KEY_W): keys += "W "
		if Input.is_key_pressed(KEY_S): keys += "S "
		if Input.is_key_pressed(KEY_A): keys += "A "
		if Input.is_key_pressed(KEY_D): keys += "D "
		if keys == "": keys = "(None)"
		
		print("[AnimDebug] Keys: %-8s | Blend: (%.2f, %.2f) | Anim: %s" % [keys, blend_pos.x, blend_pos.y, closest_anim])
