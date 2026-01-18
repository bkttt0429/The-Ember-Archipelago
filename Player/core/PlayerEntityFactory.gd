extends RefCounted
class_name PlayerEntityFactory

func build_player_entity() -> Dictionary:
    return {
        "MovementIntentComponent": MovementIntentComponent.new(),
        "MovementState": MovementState.new(),
        "PendingVelocityComponent": PendingVelocityComponent.new(),
        "GroundingComponent": GroundingComponent.new()
    }
