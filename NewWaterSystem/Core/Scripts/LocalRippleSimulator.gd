class_name LocalRippleSimulator
extends Node

## Far Cry 5 風格局部高解析度漣漪模擬
## 256×256 SubViewport 覆蓋玩家周圍 10m×10m
## 用 ping-pong 波動方程產生 per-pixel 法線擾動

const RESOLUTION: int = 256
const WORLD_SIZE: float = 10.0  # 10m × 10m 覆蓋範圍

@export var follow_target: Node3D
@export var damping: float = 0.997
@export var wave_speed: float = 0.4

var viewport: SubViewport
var sim_rect: ColorRect
var sim_material: ShaderMaterial
var output_texture: ViewportTexture

# 衝擊點佇列（每幀最多 8 個）
var _pending_impulses: Array[Vector4] = []
var _center_world: Vector2 = Vector2.ZERO  # 模擬區域的世界中心

func _ready():
	_create_viewport()
	print("[LocalRipple] Initialized %dx%d, %.1fm coverage" % [RESOLUTION, RESOLUTION, WORLD_SIZE])

func _process(_delta):
	_update_center()
	_flush_impulses()

## 外部 API：在世界座標加入衝擊
func add_impulse(world_pos: Vector3, strength: float = 0.5, radius_m: float = 0.3):
	var uv = world_to_uv(world_pos)
	# 只有在覆蓋範圍內才加
	if uv.x < -0.1 or uv.x > 1.1 or uv.y < -0.1 or uv.y > 1.1:
		return
	var radius_uv = radius_m / WORLD_SIZE
	_pending_impulses.append(Vector4(uv.x, uv.y, strength, radius_uv))

## 世界座標 → 模擬 UV [0,1]
func world_to_uv(world_pos: Vector3) -> Vector2:
	var local = Vector2(world_pos.x, world_pos.z) - _center_world
	return local / WORLD_SIZE + Vector2(0.5, 0.5)

## 取得模擬中心的世界座標
func get_center() -> Vector2:
	return _center_world

func _create_viewport():
	viewport = SubViewport.new()
	viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	viewport.transparent_bg = false
	# 16-bit 精度避免量化偽影
	viewport.use_hdr_2d = true
	
	sim_rect = ColorRect.new()
	sim_rect.anchors_preset = Control.PRESET_FULL_RECT
	sim_rect.size = Vector2(RESOLUTION, RESOLUTION)
	
	var shader = load("res://NewWaterSystem/Core/Shaders/Simulation/local_ripple_sim.gdshader")
	sim_material = ShaderMaterial.new()
	sim_material.shader = shader
	sim_material.set_shader_parameter("damping", damping)
	sim_material.set_shader_parameter("wave_speed", wave_speed)
	sim_material.set_shader_parameter("impulse_count", 0)
	
	sim_rect.material = sim_material
	viewport.add_child(sim_rect)
	add_child(viewport)
	
	output_texture = viewport.get_texture()

func _update_center():
	if not follow_target or not is_instance_valid(follow_target):
		return
	_center_world = Vector2(follow_target.global_position.x, follow_target.global_position.z)

func _flush_impulses():
	var count = mini(_pending_impulses.size(), 8)
	
	if count > 0:
		var arr: Array = []
		for i in range(8):
			if i < count:
				var imp = _pending_impulses[i]
				arr.append(imp)
			else:
				arr.append(Vector4(0, 0, 0, 0))
		sim_material.set_shader_parameter("impulses", arr)
	
	sim_material.set_shader_parameter("impulse_count", count)
	_pending_impulses.clear()
