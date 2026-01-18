extends SceneTree

func _init():
	print("Starting Geopolitics Phase 2 Test...")
	
	_test_seasonal_hazard()
	_test_culture_profile()
	_test_legal_system()
	
	print("Phase 2 Test Complete.")
	quit(0)

func _test_seasonal_hazard():
	var controller = SeasonalHazardController.new()
	controller.tick_interval = 0.1
	controller.seasonal_speed = 0.5
	
	var profile = HazardProfile.new()
	profile.region_id = "west_sea"
	profile.storm_level = 0.0
	profile.season_phase = 0.0
	
	var update_count = 0
	controller.hazard_updated.connect(func(region_id, storm_level):
		update_count += 1
		print("Hazard update:", region_id, " storm=", storm_level)
	)
	
	controller.register_region(profile)
	for i in range(5):
		controller._process(0.1)
	
	if update_count == 0:
		print("FAILURE: SeasonalHazard produced no updates.")
	else:
		print("SUCCESS: SeasonalHazard updates.")

func _test_culture_profile():
	var culture_controller = CultureController.new()
	var faction_a = FactionData.new()
	var faction_b = FactionData.new()
	
	var profile_a = CultureProfile.new()
	profile_a.honor = 0.8
	profile_a.chaos = 0.2
	profile_a.xenophobia = 0.4
	
	var profile_b = CultureProfile.new()
	profile_b.honor = 0.3
	profile_b.chaos = 0.7
	profile_b.xenophobia = 0.6
	
	culture_controller.register_faction(faction_a, profile_a)
	culture_controller.register_faction(faction_b, profile_b)
	
	var distance = culture_controller.get_culture_distance(faction_a, faction_b)
	print("Culture distance:", distance)
	
	if distance <= 0.0:
		print("FAILURE: Culture distance not computed.")
	else:
		print("SUCCESS: Culture distance computed.")

func _test_legal_system():
	var legal_system = LegalSystem.new()
	var legal_rules = LegalRules.new()
	
	var faction_a = FactionData.new()
	var faction_b = FactionData.new()
	
	var status = LegalStatus.new()
	status.embargo = false
	status.license_required = true
	status.blockade = false
	
	legal_system.set_status(faction_a, faction_b, status)
	var stored = legal_system.get_status(faction_a, faction_b)
	if stored == null:
		print("FAILURE: LegalStatus not stored.")
		return
	
	var allowed_without_license = legal_rules.is_trade_allowed(stored, false)
	var allowed_with_license = legal_rules.is_trade_allowed(stored, true)
	
	print("Trade allowed (no license):", allowed_without_license)
	print("Trade allowed (with license):", allowed_with_license)
	
	if allowed_without_license:
		print("FAILURE: License required but trade allowed.")
	elif not allowed_with_license:
		print("FAILURE: License provided but trade blocked.")
	else:
		print("SUCCESS: Legal rules validated.")
