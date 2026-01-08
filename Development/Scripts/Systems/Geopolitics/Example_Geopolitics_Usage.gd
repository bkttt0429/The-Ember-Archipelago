extends Node

const ResourceNode = preload("res://Development/Scripts/Systems/Geopolitics/ResourceNode.gd")

const GeopoliticsDebugViewScene = preload("res://Development/Scripts/Systems/Geopolitics/Debug/GeopoliticsDebugView.tscn")

func _ready():
	print("==========================================")
	print("Geopolitics System Verification Script")
	print("==========================================")
	
	# Wait a frame to ensure all autoloads (if any) are ready, though here we instance manually.
	await get_tree().process_frame
	run_test()

func setup_debug_view(graph):
	var debug_view = GeopoliticsDebugViewScene.instantiate()
	# Add to root (or any appropriate layer). Since this is Example_Geopolitics_Usage.gd which extends Node,
	# we can't add UI directly if we are not a CanvasItem or have no control parent.
	# But in a test scene, usually there is a CanvasLayer or we can add to root (which might cover everything if full rect).
	# This usage script is "Node".
	
	# Add to the Scene Tree Root to ensure it's on top
	get_tree().root.add_child(debug_view)
	debug_view.setup(graph)

func run_test():
	
	# 1. Setup GlobalBlackboard
	# Note: In a real game this is an Autoload. Here we instance it manually.
	var blackboard = GlobalBlackboard.new()
	
	# 2. Setup Factions
	var aurelian = FactionData.new()
	aurelian.faction_name = "Aurelian Hegemony (至高議會)"
	aurelian.personality_coefficients = {"aggression": 0.8, "trade_focus": 0.2}
	
	var iron_syndicate = FactionData.new()
	iron_syndicate.faction_name = "Iron Syndicate (鋼鐵兄弟會)"
	iron_syndicate.personality_coefficients = {"aggression": 0.4, "trade_focus": 0.8}
	
	var frostbane = FactionData.new()
	frostbane.faction_name = "Frostbane (寒霜大公國)"
	frostbane.personality_coefficients = {"aggression": 0.9, "trade_focus": 0.1}
	
	var player_faction = FactionData.new()
	player_faction.faction_name = "Player (Driftwood)"
	
	# 2.5 Setup Resource Nodes
	var coal_mine_alpha = ResourceNode.new()
	coal_mine_alpha.node_name = "Iron Depths Mine"
	coal_mine_alpha.resource_type = "coal"
	coal_mine_alpha.production_rate = 10.0
	
	var crystal_spire = ResourceNode.new()
	crystal_spire.node_name = "Frost Spire"
	crystal_spire.resource_type = "crystals"
	crystal_spire.production_rate = 5.0
	
	# Assign nodes
	# Iron Syndicate has Coal (Target)
	iron_syndicate.owned_nodes.append(coal_mine_alpha)
	# Frostbane has Crystals (Not what Aurelian needs)
	frostbane.owned_nodes.append(crystal_spire)
	
	# 3. Setup WorldGraph
	var graph = WorldGraph.new()
	graph.all_factions.assign([aurelian, iron_syndicate, frostbane, player_faction])
	
	# Connect Signals
	graph.invasion_declared.connect(_on_invasion_declared)
	graph.relation_changed.connect(_on_relation_changed)
	
	setup_debug_view(graph)
	
	print("\n[Setup] Factions initialized.")
	
	# Setting initial relations
	# Aurelian already dislikes Iron Syndicate
	graph.modify_relation(aurelian, iron_syndicate, -0.6)
	
	
	# 4. Simulate Scenario 1: Coal Shortage triggering Invasion
	print("\n--- SCENARIO 1: Coal Shortage ---")
	
	# Force shortage
	blackboard.coal_stock = 10 
	blackboard.check_resource_levels() 
	
	# Aurelian reacts
	print("Aurelian Hegemony is running out of coal...")
	var target = graph.find_invasion_target(aurelian, "coal")
	
	if target:
		graph.emit_signal("invasion_declared", aurelian, target, "resource_shortage:%s" % "coal")
		print(">> DECISION: %s decides to INVADE %s to secure coal!" % [aurelian.faction_name, target.faction_name])
	else:
		print(">> DECISION: No suitable target found.")

	# 5. Simulate Scenario 2: Player Tribute
	print("\n--- SCENARIO 2: Player Tribute ---")
	print("Initial Relation (Player -> Aurelian): %s" % player_faction.get_relation_to(aurelian))
	
	# Player gives an Ancient Core
	graph.process_tribute(player_faction, aurelian, "ancient_core")
	
	# Check result
	var final_rel = player_faction.get_relation_to(aurelian)
	print("Final Relation (Player -> Aurelian): %s" % final_rel)
	
	if final_rel["trade_status"] == graph.TRADE_STATUS_OPEN:
		print(">> RESULT: Trade Embargo Lifted!")
	
	print("\nVerification Complete. detailed logs in Output.")

func _on_invasion_declared(aggressor, target, reason):
	print(">>> [SIGNAL] WAR ALERT! %s declared war on %s due to %s" % [aggressor.faction_name, target.faction_name, reason])

func _on_relation_changed(faction_a, faction_b, value):
	print(">>> [SIGNAL] Relations Updated: %s and %s are now at %.2f" % [faction_a.faction_name, faction_b.faction_name, value])
