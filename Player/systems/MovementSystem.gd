extends RefCounted
class_name MovementSystem

var ecs_world: Node = null
var movement_profile: MovementProfile = null

func set_world(world: Node) -> void:
	ecs_world = world

func update(delta: float) -> void:
	if ecs_world == null:
		return
	if not ecs_world.has_method("get_entities_with"):
		return
	var entities = ecs_world.get_entities_with([
		"MovementIntentComponent",
		"MovementState",
        "PendingVelocityComponent"
	])
	for entity_id in entities:
		var intent = ecs_world.get_component(entity_id, "MovementIntentComponent")
		var movement = ecs_world.get_component(entity_id, "MovementState")
		var pending = ecs_world.get_component(entity_id, "PendingVelocityComponent")
		var physics = ecs_world.get_component(entity_id, "PhysicsComponent")
		
		if intent == null or movement == null or pending == null:
			continue
			
		# 1. 處理水平移動 (使用 move_toward 增加平滑感)
		var direction = intent.move_vector
		var desired_velocity = Vector3(
			direction.x * intent.desired_speed,
			0.0,
			direction.z * intent.desired_speed
		)

		var current_velocity = Vector3(pending.velocity.x, 0.0, pending.velocity.z)
		var has_input = direction.length() > 0.01

		# 加速/減速 平滑係數 (從 MovementProfile 讀取)
		var accel = movement_profile.acceleration if movement_profile else 14.0
		var decel = movement_profile.deceleration if movement_profile else 18.0
		var reverse_accel = movement_profile.reverse_acceleration if movement_profile else 26.0
		var rate = decel
		if has_input:
			if current_velocity.length() > 0.01 and current_velocity.dot(desired_velocity) < 0.0:
				rate = reverse_accel
			else:
				rate = accel

		var blended_velocity = current_velocity.move_toward(desired_velocity, rate * delta)
		pending.velocity.x = blended_velocity.x
		pending.velocity.z = blended_velocity.z
		
		# 2. 處理跳躍
		if intent.wants_jump and (physics and physics.is_grounded):
			pending.velocity.y = 4.5 # 直接設定向上衝量
		elif physics:
			# 在空中時保留現有的垂直速度 (由重力系統處理)
			pending.velocity.y = physics.velocity.y
			
		movement.mode = intent.mode
		movement.speed = Vector3(pending.velocity.x, 0, pending.velocity.z).length()
		# move_vector 由 InputSystem 設定 (本地輸入方向)
