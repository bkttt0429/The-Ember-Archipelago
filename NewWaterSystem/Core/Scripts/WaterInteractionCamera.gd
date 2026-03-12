"""
Water Interaction Camera System
Captures player/object positions for dynamic water ripple generation

Uses stable 2D wave equation with proper ping-pong buffers for
realistic outward-propagating ripple rings.
"""
extends Node3D
class_name WaterInteractionCamera

## Viewport texture size for interaction capture
@export var capture_size: int = 256

## World size that the interaction camera covers
@export var world_size: float = 30.0

## Target to follow (usually the player)
@export var follow_target: Node3D

## Height above water for capture camera
@export var capture_height: float = 50.0

## Wave propagation speed (0.0-0.5 for stability)
@export_range(0.0, 0.5) var wave_speed: float = 0.3

## Wave damping (higher = faster decay)
@export_range(0.9, 0.999) var wave_damping: float = 0.98

## Ripple impulse strength when player moves
@export var impulse_strength: float = 0.5

## Show debug visualization of ripple texture
@export var debug_display: bool = false

# Internal components
var _subviewport: SubViewport
var _camera: Camera3D
var _interaction_texture: ViewportTexture

# Ping-pong height buffers for stable simulation
var _height_a: Image
var _height_b: Image
var _ping: int = 0 # Which buffer is current

var _ripple_texture: ImageTexture

# Water manager reference
var _water_manager: Node3D

# Track player position for movement detection
var _last_player_pos: Vector3 = Vector3.ZERO

# Debug visualization
var _debug_rect: TextureRect
var _debug_canvas: CanvasLayer


func _ready() -> void:
	_setup_capture_system()
	_setup_ripple_buffers()
	
	# Find water manager parent
	_water_manager = get_parent()
	
	# Setup debug visualization if enabled
	if debug_display:
		_setup_debug_display()


func _setup_debug_display() -> void:
	"""Create on-screen texture rect to visualize ripple buffer"""
	_debug_canvas = CanvasLayer.new()
	_debug_canvas.layer = 100 # On top of everything
	add_child(_debug_canvas)
	
	_debug_rect = TextureRect.new()
	_debug_rect.texture = _ripple_texture
	_debug_rect.custom_minimum_size = Vector2(256, 256)
	_debug_rect.position = Vector2(10, 10)
	_debug_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_debug_canvas.add_child(_debug_rect)
	
	# Add label
	var label := Label.new()
	label.text = "Ripple Buffer"
	label.position = Vector2(10, 270)
	_debug_canvas.add_child(label)


func _setup_capture_system() -> void:
	# Create SubViewport for capturing interactions
	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(capture_size, capture_size)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.transparent_bg = true
	_subviewport.disable_3d = false
	_subviewport.use_hdr_2d = false
	add_child(_subviewport)
	
	# Create orthographic camera
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = world_size
	_camera.near = 0.1
	_camera.far = capture_height * 2.0
	_camera.cull_mask = 1 << 19 # Layer 20 for water interaction objects
	_subviewport.add_child(_camera)
	
	# Position camera looking down
	_camera.rotation_degrees = Vector3(-90, 0, 0)
	_camera.position.y = capture_height
	
	# Get viewport texture
	_interaction_texture = _subviewport.get_texture()


func _setup_ripple_buffers() -> void:
	# Create two height buffers for ping-pong rendering
	# 0.5 = neutral height (no displacement)
	_height_a = Image.create(capture_size, capture_size, false, Image.FORMAT_RF)
	_height_b = Image.create(capture_size, capture_size, false, Image.FORMAT_RF)
	
	_height_a.fill(Color(0.5, 0.5, 0.5, 1.0))
	_height_b.fill(Color(0.5, 0.5, 0.5, 1.0))
	
	_ripple_texture = ImageTexture.create_from_image(_height_a)


func _process(_delta: float) -> void:
	if follow_target:
		_update_camera_position()
	
	_simulate_ripples()


func _update_camera_position() -> void:
	# Follow target horizontally, stay at fixed height
	var target_pos = follow_target.global_position
	global_position.x = target_pos.x
	global_position.z = target_pos.z


func _simulate_ripples() -> void:
	"""
	Stable 2D wave equation using ping-pong buffers.
	
	The wave equation: h_new = c² * (h_neighbors_avg - h) + 2*h - h_prev
	Simplified stable version: h_new = damping * (h_neighbors_avg * c + h * (2 - 4c)) + prev_contribution
	
	We use a simpler stable approach:
	h_new[x,y] = damping * ( 2*h[x,y] - h_prev[x,y] + c² * (h[x-1,y] + h[x+1,y] + h[x,y-1] + h[x,y+1] - 4*h[x,y]) )
	"""
	
	# Apply player ripple impulse first
	if follow_target:
		var player_pos := follow_target.global_position
		var movement := player_pos - _last_player_pos
		var move_speed := Vector2(movement.x, movement.z).length()
		
		# Only create ripples when player is moving
		if move_speed > 0.02:
			_add_ripple_impulse(player_pos, move_speed)
		
		_last_player_pos = player_pos
	
	# Get current and previous buffers
	var curr: Image = _height_a if _ping == 0 else _height_b
	var prev: Image = _height_b if _ping == 0 else _height_a
	
	# Create output buffer (will become prev next frame)
	var next: Image = Image.create(capture_size, capture_size, false, Image.FORMAT_RF)
	next.fill(Color(0.5, 0.5, 0.5, 1.0))
	
	var c2 := wave_speed * wave_speed
	
	# Wave propagation
	for y in range(1, capture_size - 1):
		for x in range(1, capture_size - 1):
			var h_curr: float = curr.get_pixel(x, y).r
			var h_prev: float = prev.get_pixel(x, y).r
			
			# Get neighbors from current buffer
			var h_l: float = curr.get_pixel(x - 1, y).r
			var h_r: float = curr.get_pixel(x + 1, y).r
			var h_u: float = curr.get_pixel(x, y - 1).r
			var h_d: float = curr.get_pixel(x, y + 1).r
			
			# Discrete Laplacian
			var laplacian: float = h_l + h_r + h_u + h_d - 4.0 * h_curr
			
			# Wave equation: h_new = 2*h - h_prev + c²*∇²h
			var h_new: float = 2.0 * h_curr - h_prev + c2 * laplacian
			
			# Apply damping
			h_new = 0.5 + wave_damping * (h_new - 0.5)
			
			# Clamp to valid range
			h_new = clamp(h_new, 0.0, 1.0)
			
			next.set_pixel(x, y, Color(h_new, 0, 0, 1))
	
	# Swap buffers: next becomes curr, curr becomes prev
	if _ping == 0:
		_height_b = next # prev slot gets the new result
	else:
		_height_a = next
	
	_ping = 1 - _ping
	
	# Update texture with the newest data
	_ripple_texture.update(next)


func _add_ripple_impulse(world_pos: Vector3, move_speed: float) -> void:
	"""Add a height displacement at the player position"""
	var rel_pos := world_pos - global_position
	
	# Convert to texture coordinates
	var px := int((rel_pos.x / world_size + 0.5) * capture_size)
	var py := int((rel_pos.z / world_size + 0.5) * capture_size)
	
	# Get current buffer to modify
	var curr: Image = _height_a if _ping == 0 else _height_b
	
	# Create ripple with soft falloff
	var radius := 12
	var strength: float = clamp(move_speed * impulse_strength, 0.0, 0.2)
	
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var tx := px + dx
			var ty := py + dy
			if tx >= 1 and tx < capture_size - 1 and ty >= 1 and ty < capture_size - 1:
				var dist: float = sqrt(float(dx * dx + dy * dy))
				if dist < radius:
					# Smooth cosine falloff
					var t: float = dist / float(radius)
					var falloff: float = 0.5 * (1.0 + cos(PI * t))
					
					# Push water DOWN (create depression that will ripple outward)
					var current_h: float = curr.get_pixel(tx, ty).r
					var new_h: float = current_h - strength * falloff
					curr.set_pixel(tx, ty, Color(clamp(new_h, 0.0, 1.0), 0, 0, 1))


func get_ripple_texture() -> ImageTexture:
	return _ripple_texture


func get_world_size() -> float:
	return world_size


func get_center_position() -> Vector3:
	return global_position
