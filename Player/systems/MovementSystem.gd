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
        if intent == null or movement == null or pending == null:
            continue
        var direction = intent.move_vector
        if direction.length() > 1.0:
            direction = direction.normalized()
        pending.velocity = direction * intent.desired_speed
        movement.mode = intent.mode
        movement.speed = pending.velocity.length()
