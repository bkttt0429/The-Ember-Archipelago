extends RefCounted
class_name InputSystem

var ecs_world: Node = null

func set_world(world: Node) -> void:
    ecs_world = world

func update(delta: float) -> void:
    if ecs_world == null:
        return
    if not ecs_world.has_method("get_entities_with"):
        return
    var entities = ecs_world.get_entities_with(["MovementIntentComponent"])
    var input_vector = Vector2(
        Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
        Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
    )
    for entity_id in entities:
        var intent = ecs_world.get_component(entity_id, "MovementIntentComponent")
        if intent == null:
            continue
        intent.move_vector = Vector3(input_vector.x, 0.0, input_vector.y)
        intent.desired_speed = 5.0
        intent.mode = "walk"
        intent.wants_jump = Input.is_action_just_pressed("jump")
        intent.wants_sprint = Input.is_action_pressed("sprint")
        intent.wants_crouch = Input.is_action_pressed("crouch")
        intent.wants_slide = Input.is_action_pressed("slide")
