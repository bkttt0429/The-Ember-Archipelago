extends ColorRect

func _ready():
	# Ensure we have a unique material
	if not material:
		return
		
func _process(_delta):
	# Ping-pong or feedback loop
	# Grab the texture from the parent viewport
	var viewport = get_parent() as SubViewport
	if viewport:
		var tex = viewport.get_texture()
		material.set_shader_parameter("sim_buffer", tex)
