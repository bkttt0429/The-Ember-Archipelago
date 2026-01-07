extends Node

@export var water_material: ShaderMaterial
@export var ripple_viewport: SubViewport
@export var ripple_area_size: float = 50.0 # World size covered by the viewport

func _ready():
	if water_material and ripple_viewport:
		# Pass the dynamic simulation texture to the water shader
		water_material.set_shader_parameter("ripple_map", ripple_viewport.get_texture())
		water_material.set_shader_parameter("ripple_map_size", ripple_area_size)

func apply_ripple(world_pos: Vector3, strength: float):
	# Convert World Pos to UV (Viewport Coordinates)
	# Assuming Water is centered at (0,0,0) for now, or use relative calculation via WaterManager
	var uv_x = (world_pos.x + ripple_area_size / 2.0) / ripple_area_size
	var uv_y = (world_pos.z + ripple_area_size / 2.0) / ripple_area_size
	
	if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
		print("Drawing Ripple Brush at: ", Vector2(uv_x, uv_y))
		_draw_brush_at(Vector2(uv_x, uv_y), strength)

func _draw_brush_at(uv: Vector2, strength: float):
	if !ripple_viewport: return
	
	# Instantiate a brush sprite in the viewport
	var brush_container = ripple_viewport.get_node("BrushContainer")
	var brush = Sprite2D.new()
	# Use a simple radial gradient texture for the brush
	brush.texture = load("res://WaterSystem/textures/ripple_brush.tres") 
	brush.modulate = Color(strength, 0, 0, 1)
	brush.scale = Vector2(0.1, 0.1) # Brush size relative to viewport
	brush.position = uv * Vector2(ripple_viewport.size)
	
	brush_container.add_child(brush)
	await get_tree().process_frame
	brush.queue_free() # Remove after one frame so it's an impulse
