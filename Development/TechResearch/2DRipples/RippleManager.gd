extends Sprite2D

const MAX_RIPPLES = 100
var ripples_data = [] # Array of Vector4 (x, y, time, padding)

func _ready():
	# Ensure material is unique to avoid sharing state if instanced
	if material:
		material = material.duplicate()
	set_process_input(true)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			add_ripple(get_local_mouse_position())

func add_ripple(local_pos: Vector2):
	# UV conversion depends on Sprite texture size and centering
	# Sprite2D usually centered. Local pos (0,0) is center.
	# TopLeft is (-w/2, -h/2).
	
	if not texture: return
	
	var tex_size = texture.get_size()
	
	# Map local pos to UV 0..1
	# local_pos.x is from -w/2 to w/2
	# uv.x = (local_pos.x + w/2) / w
	
	var uv_x = (local_pos.x + tex_size.x * 0.5) / tex_size.x
	var uv_y = (local_pos.y + tex_size.y * 0.5) / tex_size.y
	
	# Get shader TIME.
	# The shader uses TIME (seconds since engine start).
	# We need to match that. Time.get_ticks_msec() / 1000.0 is roughly generic time.
	# Ideally pass a custom 'time' uniform to sync perfectly, but TIME uniform works if consistent.
	# Use Time.get_ticks_msec() / 1000.0 is usually close to shader TIME.
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# However, gdshader TIME is distinct.
	# Better to pass a custom uniform "current_time" to shader in process,
	# OR rely on the offset.
	# Let's use custom time passing for precision control.
	
	var ripple = Vector4(uv_x, uv_y, current_time, 0.0)
	
	# Add to front (newest)
	ripples_data.push_front(ripple)
	
	# Limit size
	if ripples_data.size() > MAX_RIPPLES:
		ripples_data.resize(MAX_RIPPLES)
	
	_update_shader()

func _process(delta):
	# Update Time Scale? No, shader handles TIME.
	# But we computed StartTime using CPU Clock.
	# We need to make sure Shader compares CPU Clock.
	
	# Update Game Time for Shader Sync
	var t = Time.get_ticks_msec() / 1000.0
	material.set_shader_parameter("game_time", t)
	
	material.set_shader_parameter("ripple_count", ripples_data.size())
	material.set_shader_parameter("ripples", ripples_data)
	
	# NOTE: The shader I wrote uses `TIME`.
	# If I use `ripple.z` as CPU time, `TIME` might be diff.
	# Let's change the shader to use a `custom_time` uniform that I update.

func _update_shader():
	material.set_shader_parameter("ripples", ripples_data)
	material.set_shader_parameter("ripple_count", ripples_data.size())
