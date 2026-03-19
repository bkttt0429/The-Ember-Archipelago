class_name FoamParticleManager
extends Node3D

@export var water_manager: OceanWaterManager
@export var particle_count: int = 6000
@export var particle_size: float = 1.0
@export var foam_texture: Texture2D

@export_group("Spawn")
@export var spawn_probability: float = 0.22
@export var max_spawns_per_frame: int = 96
@export var breaking_scan_density: int = 12
@export var spawn_height_offset: float = 0.2

@export_group("GPU-Friendly Culling")
@export var use_chunk_culling: bool = true
@export var chunk_size: float = 12.0
@export var max_render_distance: float = 120.0
@export var update_rate_far: int = 2
@export var update_rate_very_far: int = 4

var foam_multimesh: MultiMesh
var mesh_instance: MultiMeshInstance3D
var particles: Array = []
var _chunk_particles: Dictionary = {}
var _chunk_bounds: Dictionary = {}

const GRAVITY := -9.81
const DRAG := 0.5
const BUOYANCY := 12.0
const FAR_DISTANCE := 45.0
const VERY_FAR_DISTANCE := 80.0


func _ready():
	if not water_manager:
		water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers") as OceanWaterManager
	_setup_multimesh()


func _setup_multimesh():
	if mesh_instance:
		mesh_instance.queue_free()

	mesh_instance = MultiMeshInstance3D.new()
	mesh_instance.name = "FoamMultiMesh"
	add_child(mesh_instance)

	foam_multimesh = MultiMesh.new()
	foam_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	foam_multimesh.use_colors = true
	foam_multimesh.use_custom_data = true
	foam_multimesh.instance_count = particle_count
	foam_multimesh.visible_instance_count = 0

	var mesh = QuadMesh.new()
	mesh.size = Vector2(particle_size, particle_size)

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = foam_texture
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.5
	mat.distance_fade_max_distance = 2.0

	mesh.material = mat
	foam_multimesh.mesh = mesh
	mesh_instance.multimesh = foam_multimesh


func _physics_process(delta: float):
	if not water_manager:
		return

	_spawn_particles()
	_update_particles(delta)
	_rebuild_chunks()
	_render_particles()


func _spawn_particles():
	if particles.size() >= particle_count:
		return
	if not water_manager.has_method("get_breaking_wave_positions"):
		return

	var breaking_points = water_manager.get_breaking_wave_positions(breaking_scan_density)
	if breaking_points.is_empty():
		return

	var spawned := 0
	for pt in breaking_points:
		if particles.size() >= particle_count or spawned >= max_spawns_per_frame:
			break
		if randf() > spawn_probability:
			continue

		var vel = Vector3(
			(randf() - 0.5) * 2.5,
			3.0 + randf() * 2.5,
			(randf() - 0.5) * 2.5
		)

		particles.append({
			"pos": pt + Vector3(0.0, spawn_height_offset, 0.0),
			"vel": vel,
			"age": 0.0,
			"lifetime": 1.5 + randf() * 1.5,
			"scale": 1.0 + randf() * 0.5,
			"random": randf(),
			"chunk_key": _world_to_chunk(pt),
		})
		spawned += 1


func _update_particles(delta: float):
	var half_sea = water_manager.sea_size * 0.5
	var manager_pos = water_manager.global_position
	var cam = get_viewport().get_camera_3d()
	var frame = Engine.get_physics_frames()

	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["age"] += delta
		if p["age"] >= p["lifetime"]:
			particles.remove_at(i)
			continue

		var local_pos = Vector2(p["pos"].x - manager_pos.x, p["pos"].z - manager_pos.z)
		if abs(local_pos.x) > half_sea.x or abs(local_pos.y) > half_sea.y:
			particles.remove_at(i)
			continue

		if cam and not _should_update_particle(cam.global_position.distance_to(p["pos"]), frame):
			particles[i] = p
			continue

		var vel: Vector3 = p["vel"]
		var pos: Vector3 = p["pos"]
		vel.y += GRAVITY * delta
		vel.x -= vel.x * DRAG * delta
		vel.z -= vel.z * DRAG * delta
		pos += vel * delta

		var water_height = water_manager.get_wave_height_at(pos)
		if pos.y < water_height:
			pos.y = lerp(pos.y, water_height, 0.8)
			vel.y += BUOYANCY * delta
			vel.y *= 0.5

		p["pos"] = pos
		p["vel"] = vel
		p["chunk_key"] = _world_to_chunk(pos)
		particles[i] = p


func _render_particles():
	if not foam_multimesh:
		return

	var cam = get_viewport().get_camera_3d()
	var visible_particles: Array = particles
	if cam and use_chunk_culling:
		visible_particles = _collect_visible_particles(cam)

	var count = min(visible_particles.size(), foam_multimesh.instance_count)
	foam_multimesh.visible_instance_count = count

	for i in range(count):
		var p = visible_particles[i]
		var t = Transform3D()
		t.origin = p["pos"]
		var life_pct = p["age"] / p["lifetime"]
		var scale_val = (sin(life_pct * PI) * 0.8 + 0.2) * p["scale"]
		t = t.scaled(Vector3(scale_val, scale_val, scale_val))
		foam_multimesh.set_instance_transform(i, t)

		var alpha = smoothstep(1.0, 0.75, life_pct)
		foam_multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, alpha))
		foam_multimesh.set_instance_custom_data(i, Color(life_pct, p["random"], 0.0, 1.0))


func _rebuild_chunks():
	_chunk_particles.clear()
	_chunk_bounds.clear()

	for i in range(particles.size()):
		var p = particles[i]
		var key: Vector2i = p["chunk_key"] if p.has("chunk_key") else _world_to_chunk(p["pos"])
		if not _chunk_particles.has(key):
			_chunk_particles[key] = []
			_chunk_bounds[key] = AABB(p["pos"], Vector3.ZERO)
		_chunk_particles[key].append(i)
		_chunk_bounds[key] = (_chunk_bounds[key] as AABB).expand(p["pos"])


func _collect_visible_particles(cam: Camera3D) -> Array:
	var visible: Array = []
	var cam_pos = cam.global_position

	for key in _chunk_particles.keys():
		var bounds: AABB = _chunk_bounds[key]
		var center = bounds.get_center()
		var dist = cam_pos.distance_to(center)
		if dist > max_render_distance:
			continue
		if cam.is_position_behind(center):
			continue

		var indices: Array = _chunk_particles[key]
		for idx in indices:
			visible.append(particles[idx])
			if visible.size() >= foam_multimesh.instance_count:
				return visible

	return visible


func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / max(chunk_size, 0.001))),
		int(floor(pos.z / max(chunk_size, 0.001)))
	)


func _should_update_particle(dist: float, frame: int) -> bool:
	if dist > VERY_FAR_DISTANCE:
		return frame % max(update_rate_very_far, 1) == 0
	if dist > FAR_DISTANCE:
		return frame % max(update_rate_far, 1) == 0
	return true
