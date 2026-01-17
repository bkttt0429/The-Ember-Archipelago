class_name GeopoliticsDebugView
extends ColorRect

const FactionNodeScene = preload("res://Development/Scripts/Systems/Geopolitics/Debug/FactionNodeUI.tscn")

@onready var factions_container = $FactionsContainer
@onready var status_label = $StatusLabel

var graph: WorldGraph
var ui_nodes: Dictionary = {} # FactionData -> GeopoliticsFactionNode

func setup(_graph: WorldGraph):
	graph = _graph
	
	# Clear existing
	for child in factions_container.get_children():
		child.queue_free()
	ui_nodes.clear()
	
	# Create nodes
	var center = get_viewport_rect().size / 2
	var radius = 250.0
	var count = graph.all_factions.size()
	var angle_step = TAU / count
	
	for i in range(count):
		var faction = graph.all_factions[i]
		var node_ui = FactionNodeScene.instantiate()
		factions_container.add_child(node_ui)
		node_ui.setup(faction)
		
		# Position in circle
		var angle = i * angle_step
		var pos = center + Vector2(cos(angle), sin(angle)) * radius
		node_ui.position = pos - node_ui.size / 2 # Center it
		
		ui_nodes[faction] = node_ui
	
	# Connect signals
	if not graph.relation_changed.is_connected(_on_relation_changed):
		graph.relation_changed.connect(_on_relation_changed)
	if not graph.invasion_declared.is_connected(_on_invasion_declared):
		graph.invasion_declared.connect(_on_invasion_declared)
	if not graph.trade_status_changed.is_connected(_on_trade_status_changed):
		graph.trade_status_changed.connect(_on_trade_status_changed)
	if graph.has_signal("tribute_offered") and not graph.tribute_offered.is_connected(_on_tribute_offered):
		graph.tribute_offered.connect(_on_tribute_offered)
		
	queue_redraw()

func _draw():
	if not graph: return
	
	for faction_a in ui_nodes:
		var node_a = ui_nodes[faction_a]
		# Use global rect/position to be safe, then subtract our own global position to get local
		var center_a = node_a.get_global_rect().get_center() - get_global_position()
		
		for faction_b in ui_nodes:
			if faction_a == faction_b: continue
			
			# Draw line A <-> B.
			# Using simple iteration will draw twice (A->B and B->A), which overlaps.
			# That's acceptable for debug.
			
			var rel = faction_a.get_relation_to(faction_b)
			var diplomacy = rel["diplomacy_value"]
			
			# Color: -1.0 (Red) -> 0.0 (Gray) -> 1.0 (Green)
			var color = Color.GRAY
			if diplomacy > 0:
				color = Color.GRAY.lerp(Color.GREEN, diplomacy)
			else:
				color = Color.GRAY.lerp(Color.RED, -diplomacy)
			
			var node_b = ui_nodes[faction_b]
			var center_b = node_b.get_global_rect().get_center() - get_global_position()
			
			draw_line(center_a, center_b, color, 2.0)

func _on_relation_changed(a, b, value):
	queue_redraw()

func _on_trade_status_changed(a, b, status):
	queue_redraw()

func _on_invasion_declared(aggressor, target, reason):
	status_label.text = "WAR ALERT: %s -> %s\n(%s)" % [aggressor.faction_name, target.faction_name, reason]
	status_label.modulate = Color(1, 0.2, 0.2) # Red
	queue_redraw()

func _on_tribute_offered(source, target, item):
	status_label.text = "TRIBUTE: %s -> %s\n(%s)" % [source.faction_name, target.faction_name, item]
	status_label.modulate = Color(0.2, 1, 0.2) # Green
	queue_redraw()
