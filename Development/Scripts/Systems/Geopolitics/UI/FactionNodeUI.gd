class_name GeopoliticsFactionNode
extends PanelContainer

@onready var name_label = $VBoxContainer/NameLabel
@onready var info_label = $VBoxContainer/InfoLabel

var faction_data: FactionData

func setup(data: FactionData):
	faction_data = data
	name_label.text = data.faction_name
	
	var info_text = "Agg: %.1f | Trd: %.1f\n" % [
		data.personality_coefficients.get("aggression", 0.5), 
		data.personality_coefficients.get("trade_focus", 0.5)
	]
	
	if not data.owned_nodes.is_empty():
		info_text += "Resources:\n"
		for node in data.owned_nodes:
			# Use safe access as ResourceNode might strictly key
			if node.get("resource_type"):
				info_text += "- %s (%.0f)\n" % [node.resource_type, node.production_rate]
				
	info_label.text = info_text
