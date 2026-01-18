extends Node

func _ready() -> void:
	print("Starting Geopolitics Phase 3 Scene Test...")
	
	_test_black_market()
	_test_industry_tech()
	_test_governance()
	
	print("Phase 3 Scene Test Complete.")
	get_tree().quit()

func _test_black_market() -> void:
	var controller = BlackMarketController.new()
	controller.tick_interval = 0.1
	
	var faction = FactionData.new()
	var deal = BlackMarketDeal.new()
	deal.resource_type = "coal"
	deal.price_multiplier = 1.5
	deal.risk = 0.3
	deal.set_meta("faction", faction)
	
	var triggered = {"count": 0}
	controller.illicit_trade_triggered.connect(func(f, d):
		triggered["count"] += 1
		print("Illicit trade:", d.resource_type)
	)
	
	controller.add_deal(deal)
	for i in range(3):
		controller._process(0.1)
	
	if triggered["count"] == 0:
		print("FAILURE: BlackMarket produced no trade.")
	else:
		print("SUCCESS: BlackMarket triggered trade.")

func _test_industry_tech() -> void:
	var controller = IndustryTechController.new()
	controller.tick_interval = 0.1
	
	var faction = FactionData.new()
	var state = IndustryTechState.new()
	state.tech_level = 1.0
	state.industry_capacity = 1.0
	
	var updates = {"count": 0}
	controller.tech_level_changed.connect(func(f, s):
		updates["count"] += 1
		print("Tech update:", s.tech_level, " cap=", s.industry_capacity)
	)
	
	controller.register_faction(faction, state)
	controller.apply_progress(faction, 0.5)
	for i in range(3):
		controller._process(0.1)
	
	if updates["count"] == 0:
		print("FAILURE: IndustryTech produced no updates.")
	else:
		print("SUCCESS: IndustryTech updates.")

func _test_governance() -> void:
	var controller = GovernanceController.new()
	controller.tick_interval = 0.1
	controller.pressure_threshold = 0.5
	
	var faction = FactionData.new()
	var state = GovernanceState.new()
	state.territory = 2.0
	state.stability = 0.2
	state.distance_factor = 1.5
	
	var pressure_hits = {"count": 0}
	controller.governance_pressure.connect(func(f, pressure):
		pressure_hits["count"] += 1
		print("Governance pressure:", pressure)
	)
	
	controller.register_faction(faction, state)
	for i in range(3):
		controller._process(0.1)
	
	if pressure_hits["count"] == 0:
		print("FAILURE: Governance pressure not emitted.")
	else:
		print("SUCCESS: Governance pressure emitted.")
