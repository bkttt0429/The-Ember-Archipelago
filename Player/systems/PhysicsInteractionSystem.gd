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
        physics.velocity.x = pending.velocity.x
        physics.velocity.z = pending.velocity.z
        if not physics.is_grounded:
            physics.velocity.y -= 9.8 * physics.gravity_scale * delta
        transform.position += physics.velocity * delta
        if transform.position.y <= 0.0:
            transform.position.y = 0.0
            physics.velocity.y = 0.0
            physics.is_grounded = true
        else:
            physics.is_grounded = false
        grounding.is_grounded = physics.is_grounded
        grounding.ground_normal = Vector3.UP
        grounding.ground_point = transform.position
        grounding.slope_angle = 0.0
