class_name GaussianSprayManager
extends Node3D

@export var water_manager: Node
@export var max_splats: int = 4096
@export var base_size: float = 0.9

@export_group("Emission")
@export var spawn_probability: float = 0.28
@export var max_spawns_per_wave: int = 24
@export var crest_width_scale: float = 0.6
@export var upward_speed: Vector2 = Vector2(3.0, 8.0)
@export var lateral_speed: float = 2.5
@export var forward_speed: float = 4.0

@export_group("Lifetime")
@export var lifetime_range: Vector2 = Vector2(0.8, 2.0)
@export var gravity: float = 9.8
@export var drag: float = 0.35
@export var buoyancy_damping: float = 0.4

@export_group("Culling")
@export var chunk_size: float = 16.0
@export var max_render_distance: float = 140.0
@export var far_update_rate: int = 2
@export var very_far_update_rate: int = 4

var spray_multimesh: MultiMesh
var mesh_instance: MultiMeshInstance3D

# ═══════════ 優化：結構體取代 Dictionary ═══════════
class Splat:
	var pos: Vector3
	var vel: Vector3
	var age: float
	var lifetime: float
	var splat_size: float
	var alpha: float
	var random_val: float
	var chunk_key: Vector2i
	var alive: bool = true

# 物件池：預分配，swap-remove 管理
var _pool: Array[Splat] = []
var _alive_count: int = 0

# Chunk 空間索引（髒標記，不再每幀重建）
var _chunk_particles: Dictionary = {}  # Vector2i → Array[int]
var _chunk_bounds: Dictionary = {}     # Vector2i → AABB
var _chunks_dirty: bool = true

const FAR_DISTANCE := 50.0
const VERY_FAR_DISTANCE := 90.0


func _ready():
	if not water_manager:
		water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers")
	_init_pool()
	_setup_multimesh()


func _init_pool():
	_pool.resize(max_splats)
	for i in range(max_splats):
		_pool[i] = Splat.new()
	_alive_count = 0


func _setup_multimesh():
	if mesh_instance:
		mesh_instance.queue_free()

	mesh_instance = MultiMeshInstance3D.new()
	mesh_instance.name = "GaussianSprayMultiMesh"
	mesh_instance.layers = 1 << 20
	add_child(mesh_instance)

	spray_multimesh = MultiMesh.new()
	spray_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	spray_multimesh.use_colors = true
	spray_multimesh.use_custom_data = true
	spray_multimesh.instance_count = max_splats
	spray_multimesh.visible_instance_count = 0

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * base_size

	var mat := ShaderMaterial.new()
	mat.shader = load("res://NewWaterSystem/Core/Shaders/GaussianSpray.gdshader")
	quad.material = mat

	spray_multimesh.mesh = quad
	mesh_instance.multimesh = spray_multimesh


func _physics_process(delta: float):
	if not water_manager:
		return
	_spawn_from_breaking_waves()
	_update_splats(delta)
	if _chunks_dirty:
		_rebuild_chunks()
		_chunks_dirty = false
	_render_splats()


# ═══════════ Spawn（從池中取出空閒 Splat）═══════════
func _spawn_splat(p: Vector3, v: Vector3, lt: float, sz: float, a: float) -> void:
	if _alive_count >= max_splats:
		return
	var s: Splat = _pool[_alive_count]
	s.pos = p
	s.vel = v
	s.age = 0.0
	s.lifetime = lt
	s.splat_size = sz
	s.alpha = a
	s.random_val = randf()
	s.chunk_key = _world_to_chunk(p)
	s.alive = true
	_alive_count += 1
	_chunks_dirty = true


func _spawn_from_breaking_waves():
	if not water_manager.has_method("get_breaking_wave_emitters"):
		return
	var waves: Array = water_manager.get_breaking_wave_emitters()
	if waves.is_empty():
		return

	for wave in waves:
		if _alive_count >= max_splats:
			break
		if typeof(wave) != TYPE_DICTIONARY:
			continue

		var pos: Vector2 = wave.get("position", Vector2.ZERO)
		var direction: Vector2 = wave.get("direction", Vector2.RIGHT).normalized()
		var width: float = wave.get("width", 1.0)
		var height: float = wave.get("height", 1.0)
		var curl: float = wave.get("curl", 1.0)
		var state: int = wave.get("state", 0)
		var base_t: float = wave.get("base_t", 0.0)
		var energy: float = wave.get("energy", height * max(curl, 0.1))
		if state < 1:
			continue

		var tangent := Vector2(-direction.y, direction.x)
		var spawn_count := mini(max_spawns_per_wave, maxi(4, int(width * 0.15)))
		for i in range(spawn_count):
			if _alive_count >= max_splats:
				break
			if randf() > spawn_probability:
				continue

			var crest_offset := randf_range(-width * crest_width_scale, width * crest_width_scale)
			var forward_offset := randf_range(-width * 0.08, width * 0.18)
			var world_xz := pos + tangent * crest_offset + direction * forward_offset
			var world_pos := Vector3(
				world_xz.x,
				water_manager.get_wave_height_at(Vector3(world_xz.x, 0.0, world_xz.y)) + height * (0.5 + 0.3 * base_t),
				world_xz.y
			)

			var vel := Vector3(
				tangent.x * randf_range(-lateral_speed, lateral_speed) + direction.x * randf_range(0.5, forward_speed),
				randf_range(upward_speed.x, upward_speed.y) * max(curl, 0.5) * clampf(energy / maxf(height, 0.001), 0.7, 2.0),
				tangent.y * randf_range(-lateral_speed, lateral_speed) + direction.y * randf_range(0.5, forward_speed)
			)

			_spawn_splat(world_pos, vel, randf_range(lifetime_range.x, lifetime_range.y), base_size * randf_range(0.7, 1.8), randf_range(0.45, 0.9))


# ═══════════ Update（swap-remove 死亡粒子）═══════════
func _update_splats(delta: float):
	var cam := get_viewport().get_camera_3d()
	var frame := Engine.get_physics_frames()
	var i := 0

	while i < _alive_count:
		var s: Splat = _pool[i]
		s.age += delta

		# 死亡 → swap with last alive, 不遞增 i
		if s.age >= s.lifetime:
			_alive_count -= 1
			if i < _alive_count:
				# Swap：把最後一個活的搬到當前位置
				var last: Splat = _pool[_alive_count]
				_pool[i] = last
				_pool[_alive_count] = s
			s.alive = false
			_chunks_dirty = true
			continue

		# 距離 LOD：遠處降低更新頻率
		if cam and not _should_update(cam.global_position.distance_to(s.pos), frame):
			i += 1
			continue

		# 物理更新
		s.vel.y -= gravity * delta
		s.vel -= s.vel * drag * delta
		s.pos += s.vel * delta

		# 水面碰撞
		if water_manager.has_method("get_wave_height_at"):
			var water_h: float = water_manager.get_wave_height_at(Vector3(s.pos.x, 0.0, s.pos.z))
			if s.pos.y < water_h:
				s.pos.y = water_h + 0.03
				s.vel *= buoyancy_damping
				s.vel.y = absf(s.vel.y) * 0.2

		var new_key := _world_to_chunk(s.pos)
		if new_key != s.chunk_key:
			s.chunk_key = new_key
			_chunks_dirty = true

		i += 1


# ═══════════ Render ═══════════
func _render_splats():
	if not spray_multimesh:
		return

	var cam := get_viewport().get_camera_3d()
	if not cam:
		spray_multimesh.visible_instance_count = 0
		return

	var cam_pos := cam.global_position
	var cam_basis := cam.global_transform.basis
	var right := cam_basis.x.normalized()
	var up := cam_basis.y.normalized()
	var fwd := cam_basis.z.normalized()

	var render_idx := 0
	var max_render := spray_multimesh.instance_count

	# 直接遍歷 alive 粒子，用 chunk 剔除
	for key in _chunk_particles.keys():
		if render_idx >= max_render:
			break
		# Chunk AABB 距離剔除
		if _chunk_bounds.has(key):
			var center: Vector3 = (_chunk_bounds[key] as AABB).get_center()
			if cam_pos.distance_to(center) > max_render_distance:
				continue
			if cam.is_position_behind(center):
				continue

		var indices: Array = _chunk_particles[key]
		for idx in indices:
			if render_idx >= max_render:
				break
			if idx >= _alive_count:
				continue
			var s: Splat = _pool[idx]
			var life_pct := s.age / maxf(s.lifetime, 0.001)
			var scale_val := s.splat_size * (0.35 + sin(life_pct * PI) * 0.9)

			spray_multimesh.set_instance_transform(render_idx, Transform3D(
				Basis(right * scale_val, up * scale_val, fwd), s.pos
			))
			var a := s.alpha * (1.0 - smoothstep(0.55, 1.0, life_pct))
			spray_multimesh.set_instance_color(render_idx, Color(1.0, 1.0, 1.0, a))
			spray_multimesh.set_instance_custom_data(render_idx, Color(life_pct, s.random_val, 0.0, 1.0))
			render_idx += 1

	spray_multimesh.visible_instance_count = render_idx


# ═══════════ Chunk 空間索引（只在髒時重建）═══════════
func _rebuild_chunks():
	_chunk_particles.clear()
	_chunk_bounds.clear()
	for i in range(_alive_count):
		var s: Splat = _pool[i]
		var key: Vector2i = s.chunk_key
		if not _chunk_particles.has(key):
			_chunk_particles[key] = []
			_chunk_bounds[key] = AABB(s.pos, Vector3.ZERO)
		(_chunk_particles[key] as Array).append(i)
		_chunk_bounds[key] = (_chunk_bounds[key] as AABB).expand(s.pos)


func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / maxf(chunk_size, 0.001))),
		int(floor(pos.z / maxf(chunk_size, 0.001)))
	)


func _should_update(dist: float, frame: int) -> bool:
	if dist > VERY_FAR_DISTANCE:
		return frame % maxi(very_far_update_rate, 1) == 0
	if dist > FAR_DISTANCE:
		return frame % maxi(far_update_rate, 1) == 0
	return true


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
