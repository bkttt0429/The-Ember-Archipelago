extends Node
class_name PlayerSimulationManager

var ecs_world: Node = null
var systems: Array = []
var process_systems: Array = []
var physics_systems: Array = []

func _ready() -> void:
    if ecs_world == null:
        ecs_world = get_node_or_null("/root/EcsWorld")
    _register_systems()
    _inject_world()
    _validate_systems()
    _assign_update_groups()

func _process(delta: float) -> void:
    for system in process_systems:
        system.update(delta)

func _physics_process(delta: float) -> void:
    for system in physics_systems:
        system.update(delta)

func set_world(world: Node) -> void:
    ecs_world = world

func _register_systems() -> void:
    systems = [
        InputSystem.new(),
        CommandQueueSystem.new(),
        MovementSystem.new(),
        PhysicsInteractionSystem.new(),
        WeaponActionSystem.new(),
        CombatSystem.new(),
        StaminaSystem.new(),
        SurvivalSystem.new(),
        DamageSystem.new(),
        InventorySystem.new(),
        InteractionSystem.new(),
        AnimationSystem.new(),
        CameraSystem.new(),
        NetworkSyncSystem.new(),
        UISyncSystem.new()
    ]

func _inject_world() -> void:
    if ecs_world == null:
        return
    for system in systems:
        if system.has_method("set_world"):
            system.set_world(ecs_world)

func _validate_systems() -> void:
    var required_order := [
        "InputSystem",
        "CommandQueueSystem",
        "MovementSystem",
        "PhysicsInteractionSystem",
        "WeaponActionSystem",
        "CombatSystem",
        "StaminaSystem",
        "SurvivalSystem",
        "DamageSystem",
        "InventorySystem",
        "InteractionSystem",
        "AnimationSystem",
        "CameraSystem",
        "NetworkSyncSystem",
        "UISyncSystem"
    ]
    for required_name in required_order:
        var found := false
        for system in systems:
            if system.get_class() == required_name:
                found = true
                break
        if not found:
            push_error("Missing system: %s" % required_name)

func _assign_update_groups() -> void:
    process_systems = []
    physics_systems = []
    for system in systems:
        var system_name: String = system.get_class()
        if system_name in [
            "MovementSystem",
            "PhysicsInteractionSystem",
            "WeaponActionSystem",
            "CombatSystem",
            "DamageSystem",
            "NetworkSyncSystem"
        ]:
            physics_systems.append(system)
        else:
            process_systems.append(system)
