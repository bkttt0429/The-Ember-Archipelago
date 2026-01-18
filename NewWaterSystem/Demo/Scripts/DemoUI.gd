extends CanvasLayer

@onready var manager: OceanWaterManager = $"../OceanWaterManager"

func _ready():
	_create_ui()

func _create_ui():
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = "NewWaterSystem Skills Demo"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# Waterspout
	var btn_spout = Button.new()
	btn_spout.text = "Spawn Waterspout (at Center)"
	btn_spout.pressed.connect(_on_spawn_spout)
	vbox.add_child(btn_spout)
	
	# Vortex
	var btn_vortex = Button.new()
	btn_vortex.text = "Spawn Vortex (at Center)"
	btn_vortex.pressed.connect(_on_spawn_vortex)
	vbox.add_child(btn_vortex)
	
	# Clear
	var btn_clear = Button.new()
	btn_clear.text = "Clear All Effects"
	btn_clear.pressed.connect(_on_clear)
	vbox.add_child(btn_clear)
	
	# Wireframe
	var btn_wire = Button.new()
	btn_wire.text = "Toggle Wireframe"
	btn_wire.pressed.connect(_on_toggle_wireframe)
	vbox.add_child(btn_wire)
	
	# Storm Mode Preset
	var btn_storm = Button.new()
	btn_storm.text = "Toggle Storm Mode (Giant Waves)"
	btn_storm.pressed.connect(_on_toggle_storm)
	vbox.add_child(btn_storm)
	
	# Instructions
	var lbl = Label.new()
	lbl.text = "\nLeft Click: Ripple\nR Key: Restart Simulation\nRight Click + Mouse: Rotate Camera\nWASD: Move Camera"
	vbox.add_child(lbl)

func _on_spawn_spout():
	manager.trigger_waterspout(manager.global_position, 8.0, 1.0, 5.0)

func _on_spawn_vortex():
	manager.trigger_vortex(manager.global_position, 10.0, 1.0, 2.0, 5.0)

func _on_clear():
	manager.clear_skills()

func _on_toggle_wireframe():
	manager.show_wireframe = !manager.show_wireframe

func _on_toggle_storm():
	manager.storm_mode = !manager.storm_mode
