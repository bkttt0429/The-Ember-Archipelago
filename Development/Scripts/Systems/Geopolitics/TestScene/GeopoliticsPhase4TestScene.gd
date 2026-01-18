extends Node

func _ready() -> void:
	print("Starting Geopolitics Phase 4 Scene Test...")
	
	_test_subgroups()
	_test_ideology()
	_test_espionage()
	
	print("Phase 4 Scene Test Complete.")
	get_tree().quit()

func _test_subgroups() -> void:
	var controller = FactionSubgroupController.new()
	controller.tick_interval = 0.1
	controller.conflict_threshold = 0.2
	
	var faction = FactionData.new()
	var group_a = SubgroupData.new()
	group_a.name = "guild"
	group_a.influence = 0.7
	group_a.tension = 0.3
	
	var group_b = SubgroupData.new()
	group_b.name = "military"
	group_b.influence = 0.3
	group_b.tension = 0.1
	
	var conflicts = {"count": 0}
	controller.internal_conflict.connect(func(f, tension):
		conflicts["count"] += 1
		print("Internal conflict:", tension)
	)
	
	controller.register_faction(faction, [group_a, group_b])
	for i in range(3):
		controller._process(0.1)
	
	if conflicts["count"] == 0:
		print("FAILURE: FactionSubgroups produced no conflict.")
	else:
		print("SUCCESS: FactionSubgroups emitted conflict.")

func _test_ideology() -> void:
	var controller = IdeologyController.new()
	var faction = FactionData.new()
	
	var profile = IdeologyProfile.new()
	profile.fanaticism = 0.8
	profile.doctrine = "militarist"
	profile.dogma_weight = 0.6
	
	controller.register_faction(faction, profile)
	var modifier = controller.get_modifier(faction)
	print("Ideology modifier:", modifier)
	
	if modifier["aggression"] <= 0.0:
		print("FAILURE: Ideology aggression modifier invalid.")
	else:
		print("SUCCESS: Ideology modifier computed.")

func _test_espionage() -> void:
	var message_queue = MessageQueue.new()
	message_queue.tick_interval = 0.1
	message_queue.message_delivered.connect(func(message):
		print("Message delivered:", message.message_id)
	)
	add_child(message_queue)
	
	var controller = EspionageController.new()
	controller.tick_interval = 0.1
	controller.false_info_injected.connect(func(action, message):
		print("False info injected:", action.action_type)
	)
	add_child(controller)
	
	var action = EspionageAction.new()
	action.action_type = "rumor"
	action.success_rate = 1.0
	action.payload = {"tension_delta": 2.0}
	
	controller.queue_action(action)
	for i in range(5):
		controller._process(0.1)
		message_queue._process(0.1)
