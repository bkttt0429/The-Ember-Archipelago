extends RefCounted
class_name PhysicsInteractionSystem

var ecs_world: Node = null

func set_world(world: Node) -> void:
    ecs_world = world

func update(delta: float) -> void:
    if ecs_world == null:
        return
    if not ecs_world.has_method("get_entities_with"):
        return
    var entities = ecs_world.get_entities_with([
        "PendingVelocityComponent",
        "PhysicsComponent",
        "TransformComponent",
        "GroundingComponent"
    ])
    for entity_id in entities:
        var pending = ecs_world.get_component(entity_id, "PendingVelocityComponent")
        var physics = ecs_world.get_component(entity_id, "PhysicsComponent")
        var transform = ecs_world.get_component(entity_id, "TransformComponent")
        var grounding = ecs_world.get_component(entity_id, "GroundingComponent")
        
        if pending == null or physics == null or transform == null or grounding == null:
            continue
            
        # 1. 速度同步 (從 Pending 獲取位移意圖)
        physics.velocity.x = pending.velocity.x
        physics.velocity.z = pending.velocity.z
        
        # 2. 處理重力與跳躍衝量
        if not physics.is_grounded:
            physics.velocity.y -= 9.8 * physics.gravity_scale * delta
        else:
            # 在地面時，如果 Pending 有向上速度(跳躍)，優先套用
            if pending.velocity.y > 0:
                physics.velocity.y = pending.velocity.y
                pending.velocity.y = 0 # 清除衝量防止重複跳躍
            elif physics.velocity.y < 0:
                physics.velocity.y = -0.1 # 著地壓力

            
        # 3. 著地組件同步
        grounding.is_grounded = physics.is_grounded
        
        # 注意：對於 CharacterBody3D, 我們不在此直接修改 transform.position
        # 而是將計算好的 physics.velocity 交還給 Controller 呼叫 move_and_slide()
