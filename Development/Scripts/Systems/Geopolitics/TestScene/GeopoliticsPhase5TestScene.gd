extends Node

func _ready() -> void:
	print("Starting Geopolitics Phase 5 Scene Test...")
	
	_test_personal_memory()
	_test_multi_layer_blackboard()
	
	print("Phase 5 Scene Test Complete.")
	get_tree().quit()

func _test_personal_memory() -> void:
	var controller = PersonalMemoryController.new()
	controller.tick_interval = 0.1
	
	var updated = {"count": 0}
	controller.memory_updated.connect(func(entity_id, record):
		updated["count"] += 1
		print("Memory added:", entity_id, " event=", record.event)
	)
	add_child(controller)
	
	var record = PersonalMemoryRecord.new()
	record.entity_id = "npc_01"
	record.event = "ambush"
	record.grudge = 0.8
	record.decay = 0.1
	record.timestamp = 1.0
	
	controller.add_memory(record)
	for i in range(3):
		controller._process(0.1)
	
	if updated["count"] == 0:
		print("FAILURE: PersonalMemory produced no updates.")
	else:
		print("SUCCESS: PersonalMemory updates.")

func _test_multi_layer_blackboard() -> void:
	var blackboard = MultiLayerBlackboard.new()
	var layer = BlackboardLayer.new()
	layer.scope = "region_west"
	layer.truth_bias = 0.2
	
	var updates = {"count": 0}
	blackboard.layer_updated.connect(func(scope, updated_layer):
		updates["count"] += 1
		print("Layer updated:", scope, " data=", updated_layer.data)
	)
	add_child(blackboard)
	
	blackboard.register_layer(layer)
	blackboard.update_value("region_west", "storm", 0.7)
	
	if updates["count"] == 0:
		print("FAILURE: MultiLayerBlackboard produced no updates.")
	else:
		print("SUCCESS: MultiLayerBlackboard updates.")
