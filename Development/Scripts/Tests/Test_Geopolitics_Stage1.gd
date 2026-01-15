extends SceneTree

func _init():
	print("Starting Geopolitics Integration Test...")
	
	# Check if class exists
	if not ClassDB.class_exists("NPCAIController"):
		print("Error: NPCAIController class not found in ClassDB. GDExtension might not be loaded or compiled correctly.")
		quit(1)
		return

	# Instantiate
	var controller = ClassDB.instantiate("NPCAIController")
	
	if controller == null:
		print("Error: Failed to instantiate NPCAIController.")
		quit(1)
		return
		
	print("NPCAIController instantiated successfully.")

	# Add Agent
	var agent_name = "TestAgent"
	print("Adding agent: ", agent_name)
	controller.add_agent(agent_name, 1, 50) # FactionId 1 (Syndicate), Rank 50
	
	# Set SEC Profile
	var sec_data = {
		"truth_awareness": 0.5,
		"suffering_coefficient": 0.8,
		"wall_distrust_index": 0.2,
		"obedience": 0.9,
		"fear_threshold": 5.0
	}
	print("Setting SEC Profile: ", sec_data)
	controller.set_agent_sec_profile(agent_name, sec_data)
	
	# Get SEC Profile
	var retrieved_data = controller.get_agent_sec_profile(agent_name)
	print("Retrieved SEC Profile: ", retrieved_data)
	
	# Verification
	var passed = true
	var epsilon = 0.001
	
	if abs(retrieved_data.get("truth_awareness", -1.0) - sec_data["truth_awareness"]) > epsilon:
		print("Mismatch: truth_awareness")
		passed = false
	if abs(retrieved_data.get("suffering_coefficient", -1.0) - sec_data["suffering_coefficient"]) > epsilon:
		print("Mismatch: suffering_coefficient")
		passed = false
	
	if passed:
		print("SUCCESS: Data verification passed.")
	else:
		print("FAILURE: Data verification failed.")
		
	# Simulation Step
	print("Running simulation step...")
	# _process is not called automatically depending on how SceneTree runs in script mode
	# But we can call it manually for testing logic
	controller._process(0.1)
	
	# This prints to stdout, so we should see it
	controller.print_simulation_status()
	
	print("Test Complete.")
	quit(0)
