extends CanvasLayer

## PerformanceOverlay - Simple performance monitor for the water system

var label: Label

func _ready():
	layer = 120 # High layer to be visible
	
	var control = Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	add_child(control)
	
	var panel = PanelContainer.new()
	control.add_child(panel)
	
	# Style the panel a bit
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	label = Label.new()
	label.text = "Performance Monitor"
	vbox.add_child(label)
	
	var storm_toggle = CheckBox.new()
	storm_toggle.text = "Storm Mode (Cinema Giant Waves)"
	storm_toggle.focus_mode = Control.FOCUS_NONE
	storm_toggle.toggled.connect(_on_storm_toggled)
	vbox.add_child(storm_toggle)

func _on_storm_toggled(button_pressed: bool):
	var managers = get_tree().get_nodes_in_group("WaterSystem_Managers")
	for m in managers:
		if "storm_mode" in m:
			m.storm_mode = button_pressed

func _process(_delta):
	if label:
		label.text = "Performance Monitor\nFPS: %d\nFrame Time: %.2f ms" % [
			Engine.get_frames_per_second(),
			1000.0 / max(Engine.get_frames_per_second(), 1.0)
		]
