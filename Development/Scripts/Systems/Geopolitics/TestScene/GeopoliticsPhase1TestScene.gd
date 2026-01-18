extends Node

func _ready() -> void:
	print("Starting Geopolitics Phase 1 Scene Test...")
	
	_test_message_queue()
	_test_logistics()
	_test_population_morale()
	
	print("Phase 1 Scene Test Complete.")
	get_tree().quit()

func _test_message_queue() -> void:
	var queue = MessageQueue.new()
	queue.tick_interval = 0.1
	
	var delivered = 0
	queue.message_delivered.connect(func(message):
		delivered += 1
		print("Message delivered:", message.message_id)
	)
	
	var message = MessageData.new()
	message.message_id = "msg_1"
	message.travel_time = 0.2
	message.decay = 0.0
	queue.enqueue_message(message)
	
	for i in range(5):
		queue._process(0.1)
	
	if delivered == 0:
		print("FAILURE: MessageQueue delivered no messages.")
	else:
		print("SUCCESS: MessageQueue delivered messages.")

func _test_logistics() -> void:
	var controller = LogisticsController.new()
	controller.tick_interval = 0.1
	
	var route = TradeRouteData.new()
	route.route_id = "route_1"
	route.travel_time = 0.2
	
	var arrived = 0
	controller.resource_arrived.connect(func(r, amount):
		arrived += 1
		print("Resource arrived:", r.route_id, " amount=", amount)
	)
	
	controller.dispatch_convoy(route, 10.0)
	for i in range(5):
		controller._process(0.1)
	
	if arrived == 0:
		print("FAILURE: Logistics delivered no convoys.")
	else:
		print("SUCCESS: Logistics delivered convoys.")

func _test_population_morale() -> void:
	var controller = PopulationController.new()
	controller.tick_interval = 0.1
	controller.fatigue_recovery = 0.05
	controller.morale_recovery = 0.05
	
	var faction = FactionData.new()
	var state = PopulationState.new()
	state.morale = 0.2
	state.war_fatigue = 0.5
	
	var updated = 0
	controller.morale_updated.connect(func(f, s):
		updated += 1
		print("Morale updated:", s.morale, " fatigue=", s.war_fatigue)
	)
	
	controller.register_faction(faction, state)
	controller.apply_war_event(faction, 0.2)
	for i in range(3):
		controller._process(0.1)
	
	if updated == 0:
		print("FAILURE: PopulationMorale produced no updates.")
	else:
		print("SUCCESS: PopulationMorale updates.")
