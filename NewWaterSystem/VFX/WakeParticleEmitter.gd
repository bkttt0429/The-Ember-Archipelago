@tool
extends Node3D
class_name WakeParticleEmitter
## 使用 GPUParticles3D 生成船隻尾跡泡沫
## 有設計過的消散邏輯：爆發 → 擴散 → 碎裂 → 溶解

@export_group("Emission")
@export var emit_rate: float = 60.0 ## 每秒發射的泡沫粒子數
@export var particle_lifetime: float = 6.0 ## 每顆泡沫的存活時間（秒）
@export var wake_width: float = 1.0 ## 發射寬度（左右各半）
@export var min_speed: float = 0.5 ## 低於此速度不發射

@export_group("Size")
@export var particle_size_min: float = 0.08 ## 粒子最小大小
@export var particle_size_max: float = 0.4 ## 粒子最大大小

@export_group("Motion")
@export var spray_speed: float = 0.8 ## 往兩側噴散的速度
@export var turbulence_strength: float = 0.3 ## 泡沫漂流湍動強度
@export var drift_speed: float = 0.15 ## 泡沫被海流帶走的速度

@export_group("Appearance")
@export var foam_color: Color = Color(0.95, 0.97, 1.0, 0.75) ## 泡沫顏色

var _particles: GPUParticles3D
var _material: ParticleProcessMaterial
var _prev_pos: Vector3 = Vector3.ZERO
var _speed: float = 0.0

func _ready() -> void:
	_setup_particles()

func _setup_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "WakeFoamParticles"
	_particles.amount = int(emit_rate * particle_lifetime)
	_particles.lifetime = particle_lifetime
	_particles.randomness = 0.3 # 每顆粒子壽命有 ±30% 隨機，避免整批同時消失
	_particles.fixed_fps = 0
	_particles.interpolate = true
	_particles.emitting = true
	_particles.visibility_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 10, 160))
	
	# === 粒子處理材質 ===
	_material = ParticleProcessMaterial.new()
	_material.particle_flag_align_y = false
	_material.particle_flag_disable_z = false
	
	_material.direction = Vector3(0, 0, 0)
	_material.spread = 25.0
	_material.initial_velocity_min = 0.1
	_material.initial_velocity_max = spray_speed
	
	# 重力 = 0（泡沫貼水面）
	_material.gravity = Vector3(0, 0, 0)
	
	# =====================================================
	# 🎨 泡沫消散設計：四階段生命週期
	# =====================================================
	#
	# 階段 1 (0~10%): 爆發 (Burst)
	#   泡沫剛被船體打出來，快速膨脹到全尺寸
	#
	# 階段 2 (10~40%): 漂浮 (Float)  
	#   泡沫完整地漂浮在水面上，維持接近最大尺寸
	#   透明度緩慢下降（模擬水膜變薄）
	#
	# 階段 3 (40~75%): 碎裂 (Fragment)
	#   泡沫開始明顯縮小，像是大泡泡分裂成小泡泡
	#   透明度加速下降
	#
	# 階段 4 (75~100%): 溶解 (Dissolve)
	#   泡沫急速消失，最後一點殘留很快蒸發
	# =====================================================
	
	# 大小曲線 (Size over Lifetime)
	_material.scale_min = particle_size_min
	_material.scale_max = particle_size_max
	var scale_curve = CurveTexture.new()
	var s_curve = Curve.new()
	s_curve.add_point(Vector2(0.0, 0.1)) # 出生：很小
	s_curve.add_point(Vector2(0.08, 1.0)) # 爆發：快速膨脹到全尺寸
	s_curve.add_point(Vector2(0.35, 0.95)) # 漂浮：幾乎不縮小
	s_curve.add_point(Vector2(0.60, 0.6)) # 碎裂：開始明顯收縮
	s_curve.add_point(Vector2(0.80, 0.25)) # 碎裂末期：已經很小了
	s_curve.add_point(Vector2(1.0, 0.0)) # 溶解：完全消失
	scale_curve.curve = s_curve
	_material.scale_curve = scale_curve
	
	# 透明度曲線 (Alpha over Lifetime)
	_material.color = foam_color
	var alpha_curve = CurveTexture.new()
	var a_curve = Curve.new()
	a_curve.add_point(Vector2(0.0, 0.0)) # 出生：不可見（避免突然出現）
	a_curve.add_point(Vector2(0.05, 0.9)) # 爆發：快速變不透明
	a_curve.add_point(Vector2(0.30, 0.85)) # 漂浮：高不透明度維持
	a_curve.add_point(Vector2(0.55, 0.5)) # 碎裂開始：水膜變薄，透光
	a_curve.add_point(Vector2(0.75, 0.2)) # 碎裂末期：幾乎透明
	a_curve.add_point(Vector2(0.90, 0.05)) # 溶解：殘影
	a_curve.add_point(Vector2(1.0, 0.0)) # 完全消失
	alpha_curve.curve = a_curve
	_material.alpha_curve = alpha_curve
	
	# 隨機旋轉（每顆泡沫朝向不同）
	_material.angle_min = 0.0
	_material.angle_max = 360.0
	# 旋轉速度 - 泡沫會慢慢轉動（模擬海面微流）
	_material.angular_velocity_min = -15.0
	_material.angular_velocity_max = 15.0
	
	# 阻尼（模擬水面摩擦力讓泡沫減速）
	_material.damping_min = 2.0
	_material.damping_max = 5.0
	
	# 湍流 (Turbulence) - 讓泡沫在海面上不規則地漂動
	_material.turbulence_enabled = true
	_material.turbulence_noise_strength = turbulence_strength
	_material.turbulence_noise_speed_random = 0.5
	_material.turbulence_noise_speed = Vector3(drift_speed, 0, drift_speed)
	_material.turbulence_noise_scale = 4.0
	
	# 發射形狀：沿船寬的一條線
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_material.emission_box_extents = Vector3(wake_width, 0.02, 0.15)
	
	# 壽命隨機化 (讓泡沫不會同一時間全部消失)
	_material.lifetime_randomness = 0.3
	
	_particles.process_material = _material
	
	# === 使用扁平 SphereMesh 讓泡沫有立體感 ===
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.2 # 扁球體，像真的泡沫微微隆起
	sphere.radial_segments = 8
	sphere.rings = 4
	
	# PBR 材質（接受光照產生立體感）
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.roughness = 0.65 # 泡沫有一點光澤但不像鏡子
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	
	sphere.material = mat
	_particles.draw_pass_1 = sphere
	
	add_child(_particles)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	var parent = get_parent() as Node3D
	if not parent:
		return
	
	var current_pos = parent.global_position
	
	if _prev_pos != Vector3.ZERO:
		_speed = current_pos.distance_to(_prev_pos) / max(delta, 0.001)
	_prev_pos = current_pos
	
	if _particles:
		_particles.emitting = _speed > min_speed
		
		# 根據速度動態調整發射密度（越快 = 越多泡沫）
		var speed_factor = clamp((_speed - min_speed) / 5.0, 0.0, 1.0)
		_particles.amount = max(16, int(emit_rate * particle_lifetime * speed_factor))
		
		# 跟著父節點
		_particles.global_position = current_pos + Vector3(0, 0.05, 0)
		
		# 粒子往船的後方噴出
		if _speed > min_speed:
			var move_dir = (current_pos - _prev_pos).normalized()
			_material.direction = - move_dir * 0.5 + Vector3(0, 0.05, 0)
