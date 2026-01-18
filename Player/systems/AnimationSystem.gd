extends RefCounted
class_name AnimationSystem

var ecs_world: Node = null

func set_world(world: Node) -> void:
    ecs_world = world

func update(delta: float) -> void:
    if ecs_world == null:
        return
    if not ecs_world.has_method("get_entities_with"):
        return
    var entities = ecs_world.get_entities_with([
        "AnimationComponent",
        "MovementState",
        "GroundingComponent"
    ])
    for entity_id in entities:
        var animation = ecs_world.get_component(entity_id, "AnimationComponent")
        var movement = ecs_world.get_component(entity_id, "MovementState")
        var grounding = ecs_world.get_component(entity_id, "GroundingComponent")
        if animation == null or movement == null or grounding == null:
            continue
        animation.ik_targets["ground_normal"] = grounding.ground_normal
        animation.ik_targets["ground_point"] = grounding.ground_point
