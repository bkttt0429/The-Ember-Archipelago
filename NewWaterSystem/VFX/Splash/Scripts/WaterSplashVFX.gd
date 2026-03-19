class_name WaterSplashVFX
extends Node3D

## ★ 水花 VFX v3 — 完整落水效果
## 7 層構成：衝擊環 → 皇冠(alpha侵蝕) → 中心水柱 → 一次水珠 → 二次水珠 → 泡沫斑 → 水霧
## 用法：WaterSplashVFX.spawn(get_tree(), pos, impact_velocity)

@export var impact_scale: float = 1.0

var _crown_mesh: MeshInstance3D
var _crown_material: ShaderMaterial
var _decal_mesh: MeshInstance3D
var _decal_material: ShaderMaterial
var _impact_ring: MeshInstance3D
var _water_column: MeshInstance3D       # ★ 新增：中心水柱
var _foam_decal: MeshInstance3D         # ★ 新增：泡沫斑
var _time: float = 0.0
var _lifetime: float = 3.0

static func spawn(tree: SceneTree, world_pos: Vector3, impact_velocity: float = 3.0) -> WaterSplashVFX:
	var vfx = WaterSplashVFX.new()
	vfx.impact_scale = clampf(impact_velocity / 5.0, 0.5, 3.0)
	tree.current_scene.add_child(vfx)
	vfx.global_position = world_pos
	vfx.add_to_group("WaterSplashVFX")
	return vfx

func _ready():
	_create_impact_ring()
	_create_crown_mesh()
	_create_water_column()    # ★ 新增
	_create_ripple_decal()
	_create_foam_decal()      # ★ 新增
	_create_droplets()
	_create_secondary_drops() # ★ 新增
	_create_mist()
	get_tree().create_timer(_lifetime).timeout.connect(queue_free)

func _process(delta):
	_time += delta
	_update_crown()
	_update_decal()
	_update_impact_ring()
	_update_water_column()
	_update_foam_decal()

# ===========================================
# 0. 瞬間衝擊環
# ===========================================
func _create_impact_ring():
	_impact_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.01
	torus.outer_radius = 0.15 * impact_scale
	torus.rings = 32
	torus.ring_segments = 8
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.9)
	mat.metallic = 0.3
	mat.roughness = 0.05
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus.material = mat
	_impact_ring.mesh = torus
	_impact_ring.position = Vector3(0, 0.02, 0)
	_impact_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_impact_ring)

func _update_impact_ring():
	if not _impact_ring or not _impact_ring.visible: return
	var expand = 1.0 + _time * 12.0 * impact_scale
	_impact_ring.scale = Vector3(expand, 1.0, expand)
	var ring_mat = _impact_ring.mesh.material as StandardMaterial3D
	if ring_mat:
		ring_mat.albedo_color = Color(0.85, 0.95, 1.0, clampf(1.0 - _time / 0.3, 0.0, 1.0) * 0.8)
	if _time > 0.3:
		_impact_ring.visible = false

# ===========================================
# 1. Decal 漣漪
# ===========================================
func _create_ripple_decal():
	_decal_mesh = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	_decal_mesh.mesh = quad
	var shader = load("res://NewWaterSystem/VFX/Splash/Shaders/ripple_decal.gdshader")
	_decal_material = ShaderMaterial.new()
	_decal_material.shader = shader
	_decal_material.set_shader_parameter("time", 0.0)
	_decal_material.set_shader_parameter("ring_count", 4.0)
	_decal_material.set_shader_parameter("ring_speed", 2.0)
	_decal_material.set_shader_parameter("normal_intensity", 0.6)
	_decal_mesh.mesh.material = _decal_material
	_decal_mesh.position = Vector3(0, 0.02, 0)
	_decal_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_decal_mesh)

func _update_decal():
	if not _decal_material: return
	_decal_material.set_shader_parameter("time", _time)
	var expand = 1.0 + _time * 2.5 * impact_scale
	_decal_mesh.scale = Vector3(expand, 1, expand)

# ===========================================
# 2. Crown 皇冠（Alpha 侵蝕薄膜）
# ===========================================
func _create_crown_mesh():
	_crown_mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius    = 0.6 * impact_scale
	cyl.bottom_radius = 0.2 * impact_scale
	cyl.height = 1.0
	cyl.radial_segments = 48
	cyl.rings = 16
	var shader = load("res://NewWaterSystem/VFX/Splash/Shaders/splash_crown.gdshader")
	_crown_material = ShaderMaterial.new()
	_crown_material.shader = shader
	_crown_material.set_shader_parameter("time", 0.0)
	_crown_material.set_shader_parameter("crown_height", 1.5 * impact_scale)
	_crown_material.set_shader_parameter("crown_radius", 0.8 * impact_scale)
	_crown_material.set_shader_parameter("water_color", Color(0.55, 0.82, 1.0))
	_crown_material.set_shader_parameter("dissolve", 0.0)
	cyl.material = _crown_material
	_crown_mesh.mesh = cyl
	_crown_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crown_mesh)

func _update_crown():
	if not _crown_material: return
	_crown_material.set_shader_parameter("time", _time)
	var dissolve = clampf((_time - 0.3) / 0.6, 0.0, 1.0)
	_crown_material.set_shader_parameter("dissolve", dissolve)
	if dissolve >= 1.0 and _crown_mesh.visible:
		_crown_mesh.visible = false

# ===========================================
# ★ 3. 中心水柱（Worthington Jet）
# 落水後水面回彈的垂直柱狀水柱
# ===========================================
func _create_water_column():
	_water_column = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.04 * impact_scale
	cyl.bottom_radius = 0.12 * impact_scale  # 底粗頂細
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 6
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.75)
	mat.metallic = 0.1
	mat.roughness = 0.03
	mat.specular = 0.9
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.65, 0.85)
	mat.emission_energy_multiplier = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = mat
	
	_water_column.mesh = cyl
	_water_column.visible = false
	_water_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water_column)

func _update_water_column():
	if not _water_column: return
	
	# 水柱在皇冠坍塌後 (0.25s) 才出現，持續到 0.7s
	var col_start = 0.25
	var _col_peak  = 0.4
	var col_end   = 0.75
	
	if _time < col_start or _time > col_end:
		_water_column.visible = false
		return
	
	_water_column.visible = true
	var t = (_time - col_start) / (col_end - col_start)
	
	# 高度：快速上升 → 緩慢下落（拋物線）
	var rise = smoothstep(0.0, 0.35, t)
	var fall = smoothstep(0.5, 1.0, t)
	var height = 1.2 * impact_scale * rise * (1.0 - fall * 0.8)
	
	# 寬度：上升時收窄，下落時略寬
	var width = (0.8 + fall * 0.3) * impact_scale
	
	_water_column.scale = Vector3(width, maxf(height, 0.01), width)
	_water_column.position = Vector3(0, height * 0.5, 0)
	
	# Alpha 淡出
	var mat = _water_column.mesh.material as StandardMaterial3D
	if mat:
		var alpha = 0.75 * (1.0 - smoothstep(0.6, 1.0, t))
		mat.albedo_color = Color(0.7, 0.9, 1.0, alpha)

# ===========================================
# ★ 4. 泡沫斑（Foam Patch）
# 落水點殘留的白色泡沫圈
# ===========================================
func _create_foam_decal():
	_foam_decal = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.97, 1.0, 0.0)  # 開始不可見
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	quad.material = mat
	
	_foam_decal.mesh = quad
	_foam_decal.position = Vector3(0, 0.03, 0)
	_foam_decal.scale = Vector3(0.3, 1, 0.3) * impact_scale
	_foam_decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foam_decal)

func _update_foam_decal():
	if not _foam_decal: return
	
	# 泡沫在 0.2s 出現，0.5s 最亮，2.0s 消失
	var foam_appear = smoothstep(0.2, 0.5, _time)
	var foam_fade   = smoothstep(1.2, 2.5, _time)
	var alpha = foam_appear * (1.0 - foam_fade) * 0.5
	
	var mat = _foam_decal.mesh.material as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.95, 0.97, 1.0, alpha)
	
	# 緩慢擴張
	var size = (0.4 + _time * 0.8) * impact_scale
	_foam_decal.scale = Vector3(size, 1, size)

# ===========================================
# 5. 一次水珠（Crown 飛出）
# ===========================================
func _create_droplets():
	var p = GPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = maxi(20, int(40 * impact_scale))
	p.lifetime = 1.2
	p.explosiveness = 0.95
	p.randomness = 0.4
	
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 55.0
	mat.initial_velocity_min = 4.0 * impact_scale
	mat.initial_velocity_max = 10.0 * impact_scale
	mat.gravity = Vector3(0, -14.0, 0)
	mat.damping_min = 0.5
	mat.damping_max = 1.5
	mat.scale_min = 0.025
	mat.scale_max = 0.07
	mat.particle_flag_align_y = true
	
	var ac = Curve.new()
	ac.add_point(Vector2(0.0, 0.0))
	ac.add_point(Vector2(0.02, 1.0))
	ac.add_point(Vector2(0.6, 0.8))
	ac.add_point(Vector2(1.0, 0.0))
	var act = CurveTexture.new()
	act.curve = ac
	mat.alpha_curve = act
	p.process_material = mat
	
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.02
	capsule.height = 0.08
	capsule.radial_segments = 6
	capsule.rings = 2
	var dmat = StandardMaterial3D.new()
	dmat.albedo_color = Color(0.8, 0.93, 1.0, 0.9)
	dmat.metallic = 0.0
	dmat.roughness = 0.03
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	capsule.material = dmat
	p.draw_pass_1 = capsule
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)

# ===========================================
# ★ 6. 二次水珠（水柱頂端掉落回水面）
# 延遲 0.35s 才發射，模擬回落
# ===========================================
func _create_secondary_drops():
	var p = GPUParticles3D.new()
	p.emitting = false  # 延遲發射
	p.one_shot = true
	p.amount = maxi(8, int(15 * impact_scale))
	p.lifetime = 0.6
	p.explosiveness = 0.7
	p.randomness = 0.6
	
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 0)  # 幾乎只往外散
	mat.spread = 80.0
	mat.initial_velocity_min = 1.0 * impact_scale
	mat.initial_velocity_max = 3.0 * impact_scale
	mat.gravity = Vector3(0, -18.0, 0)  # 重力更強 → 快速落下
	mat.scale_min = 0.015
	mat.scale_max = 0.04
	mat.particle_flag_align_y = true
	
	var ac = Curve.new()
	ac.add_point(Vector2(0.0, 0.0))
	ac.add_point(Vector2(0.05, 0.9))
	ac.add_point(Vector2(0.5, 0.7))
	ac.add_point(Vector2(1.0, 0.0))
	var act = CurveTexture.new()
	act.curve = ac
	mat.alpha_curve = act
	p.process_material = mat
	
	var sphere = SphereMesh.new()
	sphere.radius = 0.015
	sphere.height = 0.03
	sphere.radial_segments = 4
	sphere.rings = 2
	var dmat = StandardMaterial3D.new()
	dmat.albedo_color = Color(0.85, 0.95, 1.0, 0.8)
	dmat.roughness = 0.02
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = dmat
	p.draw_pass_1 = sphere
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# ★ 位置稍高（從水柱頂端發射）
	p.position = Vector3(0, 0.5 * impact_scale, 0)
	add_child(p)
	
	# 延遲 0.35s 後發射（等水柱升起）
	get_tree().create_timer(0.35).timeout.connect(func():
		if is_instance_valid(p): p.emitting = true)

# ===========================================
# 7. 水霧
# ===========================================
func _create_mist():
	var p = GPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = maxi(8, int(14 * impact_scale))
	p.lifetime = 0.7
	p.explosiveness = 0.6
	p.randomness = 0.7
	
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 0)
	mat.spread = 90.0
	mat.initial_velocity_min = 0.5 * impact_scale
	mat.initial_velocity_max = 2.5 * impact_scale
	mat.gravity = Vector3(0, -0.5, 0)
	mat.scale_min = 0.4 * impact_scale
	mat.scale_max = 0.9 * impact_scale
	
	var sc = Curve.new()
	sc.add_point(Vector2(0.0, 0.2))
	sc.add_point(Vector2(0.25, 0.8))
	sc.add_point(Vector2(1.0, 0.0))
	var sct = CurveTexture.new()
	sct.curve = sc
	mat.scale_curve = sct
	
	var ac = Curve.new()
	ac.add_point(Vector2(0.0, 0.0))
	ac.add_point(Vector2(0.06, 0.4))
	ac.add_point(Vector2(0.3, 0.25))
	ac.add_point(Vector2(1.0, 0.0))
	var act = CurveTexture.new()
	act.curve = ac
	mat.alpha_curve = act
	p.process_material = mat
	
	var quad = QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var mist_mat = StandardMaterial3D.new()
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mist_mat.albedo_color = Color(0.8, 0.92, 1.0, 0.35)
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist_mat.vertex_color_use_as_albedo = true
	mist_mat.no_depth_test = true
	quad.material = mist_mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
