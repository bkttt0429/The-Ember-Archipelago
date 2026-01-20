extends RefCounted
class_name InputSystem

var ecs_world: Node = null

func set_world(world: Node) -> void:
	ecs_world = world

func update(_delta: float) -> void:
	if ecs_world == null:
		return
	if not ecs_world.has_method("get_entities_with"):
		return
		
	var entities = ecs_world.get_entities_with(["MovementIntentComponent", "MovementState"])
	
	# 抓取輸入方向
	var move_left = _get_action_strength("move_left", "ui_left")
	var move_right = _get_action_strength("move_right", "ui_right")
	var move_forward = _get_action_strength("move_forward", "ui_up")
	var move_back = _get_action_strength("move_back", "ui_down")
	
	
	for entity_id in entities:
		var intent = ecs_world.get_component(entity_id, "MovementIntentComponent")
		var movement = ecs_world.get_component(entity_id, "MovementState")
		if intent == null: continue
			
		# 1. 獲取角色朝向
		var basis = Basis()
		if ecs_world is Node3D:
			basis = ecs_world.global_transform.basis.orthonormalized()
		
		# 2. 計算方向：Godot Forward 是 -Z
		var move_v3 = Vector3.ZERO
		move_v3 += -basis.z * (move_forward - move_back)
		move_v3 += basis.x * (move_right - move_left)
		
		# 3. 更新意圖 (加上一個微小的閾值防止抖動)
		if move_v3.length() > 0.01:
			intent.move_vector = move_v3.normalized()
		else:
			intent.move_vector = Vector3.ZERO
		
		# 4. 更新本地移動向量 (供動畫使用)
		if movement:
			movement.move_vector = Vector2(move_right - move_left, move_forward - move_back)

		
		# 判斷移動模式與速度
		if _is_action_pressed("sprint"):
			intent.mode = "sprint"
			intent.desired_speed = 8.0
		elif _is_action_pressed("crouch"):
			intent.mode = "crouch"
			intent.desired_speed = 2.5
		else:
			intent.mode = "walk"
			intent.desired_speed = 5.0
			
		if movement and movement.is_swimming:
			intent.mode = "swim"
			intent.desired_speed = 3.5
		
		# 動作標記
		intent.wants_jump = _is_action_just_pressed("jump", "ui_accept")
		intent.wants_interact = _is_action_just_pressed("interact")

func _get_action_strength(action: String, fallback: String = "") -> float:
	# 優先檢查自定義動作
	if InputMap.has_action(action):
		return Input.get_action_strength(action)
		
	# 如果沒有自定義動作，直接檢查鍵盤 (WASD)
	match action:
		"move_left": if Input.is_key_pressed(KEY_A): return 1.0
		"move_right": if Input.is_key_pressed(KEY_D): return 1.0
		"move_forward": if Input.is_key_pressed(KEY_W): return 1.0
		"move_back": if Input.is_key_pressed(KEY_S): return 1.0
	
	# 最後才檢查 ui_ 備選 (方向鍵)
	if fallback != "" and InputMap.has_action(fallback):
		return Input.get_action_strength(fallback)
	return 0.0

func _is_action_pressed(action: String, fallback: String = "") -> bool:
	if InputMap.has_action(action):
		return Input.is_action_pressed(action)
	if fallback != "" and InputMap.has_action(fallback):
		return Input.is_action_pressed(fallback)
	
	# 硬編碼最後備選
	match action:
		"sprint": return Input.is_key_pressed(KEY_SHIFT)
		"crouch": return Input.is_key_pressed(KEY_CTRL)
	return false

func _is_action_just_pressed(action: String, fallback: String = "") -> bool:
	if InputMap.has_action(action):
		return Input.is_action_just_pressed(action)
	if fallback != "" and InputMap.has_action(fallback):
		return Input.is_action_just_pressed(fallback)
	
	# 硬編碼最後備選
	match action:
		"jump": return Input.is_key_pressed(KEY_SPACE)
		"interact": return Input.is_key_pressed(KEY_E)
	return false
