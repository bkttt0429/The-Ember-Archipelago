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
    var entities = ecs_world.get_entities_with(["MovementState", "PhysicsComponent", "TransformComponent"])
    for entity_id in entities:
        var movement = ecs_world.get_component(entity_id, "MovementState")
        var physics = ecs_world.get_component(entity_id, "PhysicsComponent")
        var transform = ecs_world.get_component(entity_id, "TransformComponent")
        if movement == null or physics == null or transform == null:
            continue
        transform.position += physics.velocity * delta
        movement.speed = physics.velocity.length()
