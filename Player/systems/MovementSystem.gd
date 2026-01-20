extends RefCounted
class_name MovementSystem

var ecs_world: Node = null

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
        var target_vx = direction.x * intent.desired_speed
        var target_vz = direction.z * intent.desired_speed
        
        # 加速/減速 平滑係數 (可根據需求調整或移至組件)
        var accel = 15.0 if direction.length() > 0 else 10.0
        pending.velocity.x = move_toward(pending.velocity.x, target_vx, accel * delta)
        pending.velocity.z = move_toward(pending.velocity.z, target_vz, accel * delta)
        
        # 2. 處理跳躍
        if intent.wants_jump and (physics and physics.is_grounded):
            pending.velocity.y = 4.5 # 直接設定向上衝量
        elif physics:
            # 在空中時保留現有的垂直速度 (由重力系統處理)
            pending.velocity.y = physics.velocity.y
            
        movement.mode = intent.mode
        movement.speed = Vector3(pending.velocity.x, 0, pending.velocity.z).length()
