@tool
class_name OceanWaterManager
extends Node3D

## WaterManager - Modular Interactive Water System (SWE + Gerstner)
## Manages GPU-based SWE simulation and provides height queries.

@export_group("Simulation Grid")
@export var grid_res: int = 128:
	set(v):
		grid_res = v
		_request_restart()
@export var use_lod: bool = false:
	set(v):
		use_lod = v
		if is_node_ready(): call_deferred("_setup_visuals")
@export var sea_size: Vector2 = Vector2(80.0, 80.0):
	set(v):
		if sea_size == v: return
		sea_size = v
		if is_node_ready() and has_node("WaterPlane"): $WaterPlane.mesh.size = sea_size
		_update_shader_params_deferred()
@export var propagation_speed: float = 20.0
@export var damping: float = 0.9 # Increased stability

@export_group("Physical Interaction")
@export var interact_strength: float = 50.0
@export var interact_radius: float = 0.5
@export var swe_strength: float = 1.0

@export_group("Environmental Effects")
@export var rain_intensity: float = 0.0:
	set(v): rain_intensity = clamp(v, 0.0, 1.0)

@export_group("Wind & Wave Properties")
@export var wind_strength: float = 1.0:
	set(v): wind_strength = v; _update_shader_params_deferred()
@export var wind_direction: Vector2 = Vector2(1.0, 0.5):
	set(v): wind_direction = v; _update_shader_params_deferred()
@export var wave_steepness: float = 0.25:
	set(v): wave_steepness = v; _update_shader_params_deferred()
@export var wave_length: float = 20.0:
	set(v): wave_length = v; _update_shader_params_deferred()
@export var horizontal_displacement_scale: float = 0.5:
	set(v): horizontal_displacement_scale = v; _update_shader_params_deferred()
@export var wave_chaos: float = 1.0:
	set(v):
		wave_chaos = v
		_update_shader_params_deferred()

@export var peak_sharpness: float = 1.0:
	set(v):
		peak_sharpness = v
		_update_shader_params_deferred()

# ==============================================================================
# Presets (Barrel Waves)
# ==============================================================================

@export_group("Preset Configurations")
@export var apply_deep_barrel: bool = false:
	set(v):
		if v and is_inside_tree():
			call_deferred("apply_deep_ocean_barrel_preset")
			apply_deep_barrel = false

@export var apply_surf_barrel: bool = false:
	set(v):
		if v and is_inside_tree():
			call_deferred("apply_surfing_barrel_preset")
			apply_surf_barrel = false

## 應用深海巨浪預設
func apply_deep_ocean_barrel_preset():
	wind_strength = 8.0
	wave_length = 80.0 # Increased from 40.0 to match wind scale
	wave_steepness = 0.18
	horizontal_displacement_scale = 0.7 # ✅ Lower for stability in big waves
	peak_sharpness = 1.8 # ✅ Reduced from 2.2 to prevent spikes
	wave_chaos = 0.25 # Reduced from 0.4 to prevent messy intersection
	
	rogue_wave_present = true
	rogue_wave_height = 6.0 # ✅ Reduced from 8.0
	rogue_wave_width = 40.0 # ✅ Increased width for smoother slope
	rogue_wave_speed = 12.0
	
	color_deep = Color(0.0, 0.1, 0.3)
	color_shallow = Color(0.0, 0.6, 0.8)
	foam_crest_strength = 5.0
	fresnel_strength = 0.9
	
	print("[WaterManager] Deep Ocean Barrel Preset Applied (Anti-Spike)")
	
	# Visual Fixes
	normal_scale = 0.7
	normal_tile = 10.0
	roughness = 0.25
	foam_jacobian_bias = 0.15
	normal_speed = 0.25
	
	# Reset fluid simulation to prevent artifact explosion from sudden parameter changes
	call_deferred("_reset_swe_texture")

## 應用衝浪巨浪預設
func apply_surfing_barrel_preset():
	wind_strength = 6.0
	wave_length = 50.0
	wave_steepness = 0.20
	horizontal_displacement_scale = 0.75 # ✅ Lower for stability
	peak_sharpness = 2.0 # ✅ Reduced from 2.8
	wave_chaos = 0.2
	
	rogue_wave_present = true
	rogue_wave_height = 5.0 # ✅ Reduced from 6.0
	rogue_wave_width = 50.0 # ✅ Increased width
	rogue_wave_speed = 10.0
	
	color_deep = Color(0.0, 0.2, 0.4)
	color_shallow = Color(0.0, 0.8, 0.9)
	foam_crest_strength = 4.0
	fresnel_strength = 0.8
	
	print("[WaterManager] Surfing Barrel Preset Applied (Anti-Spike)")

	# Visual Fixes
	normal_scale = 0.7
	normal_tile = 10.0
	roughness = 0.25
	foam_jacobian_bias = 0.15
	normal_speed = 0.25
	
	# Reset fluid simulation to prevent artifact explosion from sudden parameter changes
	call_deferred("_reset_swe_texture")

@export_group("Visual Style")
@export var color_deep: Color = Color(0.01, 0.2, 0.4): # Clear Blue
	set(v): color_deep = v; _update_shader_params_deferred()
@export var color_shallow: Color = Color(0.0, 0.9, 0.95): # Turquoise
	set(v): color_shallow = v; _update_shader_params_deferred()
@export var absorption_coeff: float = 0.5:
	set(v): absorption_coeff = v; _update_shader_params_deferred()
@export var color_foam: Color = Color(1.0, 1.0, 1.0):
	set(v): color_foam = v; _update_shader_params_deferred()
@export var foam_noise_tex: NoiseTexture2D:
	set(v): foam_noise_tex = v; _update_shader_params_deferred()

@export_subgroup("Reflections & PBR")
@export var metallic: float = 0.0:
	set(v): metallic = v; _update_shader_params_deferred()
@export var roughness: float = 0.25:
	set(v): roughness = v; _update_shader_params_deferred()
@export var specular: float = 0.6:
	set(v): specular = v; _update_shader_params_deferred()
@export_group("Atmospheric & Shading")
@export var fresnel_strength: float = 0.5:
	set(v):
		fresnel_strength = v
		_update_shader_params_deferred()

@export var reflection_strength: float = 0.4:
	set(v):
		reflection_strength = v
		_update_shader_params_deferred()

@export var sss_strength: float = 0.1:
	set(v):
		sss_strength = v
		_update_shader_params_deferred()

@export var sss_color: Color = Color(0.0, 0.6, 0.5, 1.0):
	set(v):
		sss_color = v
		_update_shader_params_deferred()
		
@export var edge_fade: float = 4.0:
	set(v):
		edge_fade = v
		_update_shader_params_deferred()

@export_subgroup("Horizon Damping")
@export var far_fade_start: float = 80.0:
	set(v): far_fade_start = v; _update_shader_params_deferred()
@export var far_fade_max: float = 120.0:
	set(v): far_fade_max = v; _update_shader_params_deferred()

@export_subgroup("Foam Settings")
@export var foam_shore_spread: float = 0.5:
	set(v): foam_shore_spread = v; _update_shader_params_deferred()
@export var foam_shore_strength: float = 1.0:
	set(v): foam_shore_strength = v; _update_shader_params_deferred()
@export var foam_crest_spread: float = 0.2:
	set(v): foam_crest_spread = v; _update_shader_params_deferred()
@export var foam_crest_strength: float = 0.8:
	set(v): foam_crest_strength = v; _update_shader_params_deferred()
@export var foam_wake_strength: float = 1.5:
	set(v): foam_wake_strength = v; _update_shader_params_deferred()
@export var foam_jacobian_bias: float = 0.1:
	set(v): foam_jacobian_bias = v; _update_shader_params_deferred()

@export_subgroup("Caustics")
@export var caustics_texture: Texture2D:
	set(v): caustics_texture = v; _update_shader_params_deferred()
@export var caustics_strength: float = 1.0:
	set(v): caustics_strength = v; _update_shader_params_deferred()
@export var caustics_scale: float = 0.5:
	set(v): caustics_scale = v; _update_shader_params_deferred()
@export var caustics_speed: float = 0.1:
	set(v): caustics_speed = v; _update_shader_params_deferred()

@export_subgroup("Detail Normals")
@export var normal_map1: Texture2D:
	set(v): normal_map1 = v; _update_shader_params_deferred()
@export var normal_map2: Texture2D:
	set(v): normal_map2 = v; _update_shader_params_deferred()
@export var normal_scale: float = 0.7:
	set(v): normal_scale = v; _update_shader_params_deferred()
@export var normal_speed: float = 0.25:
	set(v): normal_speed = v; _update_shader_params_deferred()
@export var normal_tile: float = 10.0:
	set(v): normal_tile = v; _update_shader_params_deferred()

@export_subgroup("Flow Map")
@export var flow_map: Texture2D:
	set(v): flow_map = v; _update_shader_params_deferred()
@export var flow_speed: float = 0.05:
	set(v): flow_speed = v; _update_shader_params_deferred()
@export var flow_strength: float = 0.5:
	set(v): flow_strength = v; _update_shader_params_deferred()

@export var debug_show_markers: bool = false:
	set(v): debug_show_markers = v; _update_shader_params_deferred()

@export_group("Debug Tools")
@export var debug_view: bool = false:
	set(v):
		debug_view = v
		_update_shader_params_deferred()

@export var debug_mesh_only: bool = false:
	set(v):
		debug_mesh_only = v
		_update_shader_params_deferred()


@export var fft_scale: float = 1.0:
	set(v):
		fft_scale = v
		_update_shader_params_deferred()

@export var show_wireframe: bool = false:
	set(v):
		show_wireframe = v
		_update_shader_params_deferred()


@export_group("Debug Actions")
@export var restart_simulation: bool = false:
	set(v):
		if v and is_inside_tree():
			call_deferred("_request_restart")

# Internal State
var physics_time: float = 0.0
var accumulated_time: float = 0.0
var _time: float = 0.0 # Legacy wall time

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var fft_init_shader: RID
var fft_init_pipeline: RID
var fft_update_shader: RID
var fft_update_pipeline: RID
var fft_butterfly_shader: RID
var fft_butterfly_pipeline: RID
var fft_displace_shader: RID
var fft_displace_pipeline: RID

var sim_texture_A: RID
var sim_texture_B: RID
var fft_h0_texture: RID
var fft_ht_texture: RID
var fft_ping_texture: RID
var fft_pong_texture: RID
var fft_displace_texture: RID
var fft_displace_tex: Texture2DRD

var interaction_buffer: RID
var visual_texture: ImageTexture
var uniform_set_A: RID
var uniform_set_B: RID
var current_sim_idx: int = 0
var has_submitted: bool = false
var sim_image: Image

# Cached Uniform Sets to prevent RID leaks
var fft_init_set: RID
var fft_update_set: RID
var fft_butterfly_sets = [] # [ht_ping, ping_pong, pong_ping]
var fft_displace_sets = [] # [ping_disp, pong_disp]
var vortex_sets = [] # [sim_A, sim_B]
var waterspout_sets = [] # [sim_A, sim_B]

const MAX_INTERACTIONS = 128

# External Interactions (List of dictionaries: {uv, strength, radius})
var interaction_points: Array = []

# Updated Paths for NewStructure
# Updated Paths for NewStructure
const SOLVER_PATH = "res://NewWaterSystem/Core/Shaders/Internal/water_interaction.glsl"
const SURFACE_SHADER_PATH = "res://NewWaterSystem/Core/Shaders/Surface/ocean_surface.gdshader"
const VORTEX_SHADER_PATH = "res://NewWaterSystem/Weather/Shaders/Vortex.glsl"
const WATERSPOUT_SHADER_PATH = "res://NewWaterSystem/Weather/Shaders/Waterspout.glsl"

const FFT_INIT_PATH = "res://NewWaterSystem/Core/Shaders/Internal/OceanFFT_Init.glsl"
const FFT_UPDATE_PATH = "res://NewWaterSystem/Core/Shaders/Internal/OceanFFT_Update.glsl"
const FFT_BUTTERFLY_PATH = "res://NewWaterSystem/Core/Shaders/Internal/OceanFFT_Butterfly.glsl"
const FFT_DISPLACE_PATH = "res://NewWaterSystem/Core/Shaders/Internal/OceanFFT_Displace.glsl"


# Weather System RIDs
var weather_texture: RID
var weather_image: Image
var weather_visual_tex: ImageTexture
var vortex_shader_rid: RID
var vortex_pipeline_rid: RID
var waterspout_shader_rid: RID
var waterspout_pipeline_rid: RID
var vortex_params_buffer: RID
var waterspout_params_buffer: RID
var weather_uniform_set: RID

# Active Skills State
var active_vortex = null # {position: Vector2, radius: float, intensity: float, speed: float, depth: float}
var active_waterspout = null # {position: Vector2, radius: float, intensity: float, speed: float}

var envelope_texture: ImageTexture

var _is_initialized: bool = false

var _idle_timer: float = 0.0

func _update_shader_params_deferred():
	if is_inside_tree():
		call_deferred("_update_shader_parameters")


func _request_restart():
	print("[WaterManager] Requesting simulation restart...")
	_cleanup()
	_setup_simulation()
	_bake_obstacles()
	_setup_visuals()
	_update_shader_parameters()
	interaction_points.clear()
	print("[WaterManager] Restart complete.")

@export var storm_mode: bool = false:
	set(v):
		storm_mode = v
		if v:
			_apply_storm_preset()
		_update_shader_params_deferred()

func _apply_storm_preset():
	# 移除手動 wave_length 調整 -> 錯誤：Shader 用的是硬編碼波長，仍需此參數縮放視覺！
	# JONSWAP (CPU) 會自動調整，但 Shader (GPU) 需要 wave_length 作為基準
	wind_strength = 3.5 # 35 m/s ≈ 12 級颱風
	wave_length = 120.0 # ✅ 恢復：對應高風速的波長基準
	wave_steepness = 0.35 # Reduced from 0.5 for stability
	peak_sharpness = 1.4 # Reduced from 1.8 for stability
	sss_color = Color(0.1, 0.8, 0.6) # More teal, less green
	foam_crest_strength = 4.0
	fresnel_strength = 0.7 # Reduced from 1.2
	reflection_strength = 0.6 # Reduced from 0.8
	sss_strength = 0.4 # Reduced from 1.0
	print("[WaterManager] Storm Mode - JONSWAP 自动调整波长分布 (Refined).")

func _ready():
	_is_initialized = false
	add_to_group("WaterSystem_Managers")
	_cleanup()
	_setup_simulation()
	
	await get_tree().process_frame
	_bake_obstacles()
	_setup_visuals()
	
	_init_foam_noise()
	_init_caustics_noise()
	_init_default_normals()
	_generate_envelope_texture()
	
	_init_default_normals()
	_generate_envelope_texture()
	
	# Safe Async Wait
	if is_inside_tree():
		if normal_map1 and normal_map1 is NoiseTexture2D:
			# Verify first pixel to ensure it's not white/empty
			var start_time = Time.get_ticks_msec()
			while not normal_map1.get_image() and (Time.get_ticks_msec() - start_time < 2000):
				await get_tree().process_frame
			
			if normal_map1.get_image():
				var img = normal_map1.get_image()
				var pixel = img.get_pixel(0, 0)
				print("[WaterManager] Normal Map 1 READY! Pixel(0,0): ", pixel)
			else:
				print("[WaterManager] Normal Map 1 Timeout!")

		if normal_map2 and normal_map2 is NoiseTexture2D:
			while not normal_map2.get_image():
				await get_tree().process_frame
			print("[WaterManager] Normal Map 2 READY!")
	
	if foam_noise_tex:
		if not foam_noise_tex.changed.is_connected(_update_shader_params_deferred):
			foam_noise_tex.changed.connect(_update_shader_params_deferred)
			
	if caustics_texture and caustics_texture is NoiseTexture2D:
		if not caustics_texture.changed.is_connected(_update_shader_params_deferred):
			caustics_texture.changed.connect(_update_shader_params_deferred)
			
	if normal_map1 and normal_map1 is NoiseTexture2D:
		if not normal_map1.changed.is_connected(_update_shader_params_deferred):
			normal_map1.changed.connect(_update_shader_params_deferred)
			
	if normal_map2 and normal_map2 is NoiseTexture2D:
		if not normal_map2.changed.is_connected(_update_shader_params_deferred):
			normal_map2.changed.connect(_update_shader_params_deferred)
	
	_update_shader_parameters()
	
	# ========== 視覺平衡優化 ==========
	print("[WaterManager] Applying balanced visual settings...")
	
	# 法線系統（柔和但有細節）
	normal_scale = 0.7 # 適中的凹凸感
	normal_tile = 10.0 # 更密集的紋理
	normal_speed = 0.25 # 稍慢的動態
	
	# PBR 材質（平衡反射和粗糙度）
	roughness = 0.25 # 適中的粗糙度
	metallic = 0.0 # 海水不應該是金屬
	specular = 0.6 # 適中的鏡面反射
	
	# 泡沫系統（避免過度）
	foam_jacobian_bias = 0.15 # 稍微寬鬆的閾值
	foam_crest_strength = 1.5 # 適中的泡沫強度
	
	# FFT 細節（在 _update_shader_parameters 中會用到）
	fft_scale = 1.0 # 標準強度
	
	# 強制更新
	_update_shader_parameters()
	
	print("[WaterManager] Visual settings applied: normal_scale=%.2f, roughness=%.2f" % [normal_scale, roughness])
	# ================================
	
	_is_initialized = true

# ==============================================================================
# Physics & Buoyancy Interface (CPU Side)
# ==============================================================================

# ==============================================================================
# JONSWAP Wave Spectrum Generator
# ==============================================================================

# 物理常數
const GRAVITY = 9.81
const TWO_PI = 6.283185307
const JONSWAP_GAMMA = 3.3 # 峰值增強因子

# 緩存結構
var _jonswap_cache = {
	"layers": [], # 波浪層數組
	"wind_hash": 0, # 參數哈希值
	"last_update": 0.0, # 最後更新時間（調試用）
	"hit_count": 0, # 緩存命中次數（調試用）
	"miss_count": 0 # 緩存未命中次數（調試用）
}

## JONSWAP 頻譜能量密度函數
## @param freq: 波浪頻率 (Hz)
## @param wind_speed: 風速 (m/s)
## @return: 該頻率處的能量密度 (m²·s)
func _calculate_jonswap_spectrum(freq: float, wind_speed: float) -> float:
	var omega = TWO_PI * freq
	var omega_p = 0.855 * GRAVITY / wind_speed # 峰值角頻率
	
	# Phillips 頻譜基礎項
	var alpha = 0.076 * pow(wind_speed * wind_speed / (freq * GRAVITY), 0.22)
	var exp_term = exp(-1.25 * pow(omega_p / omega, 4.0))
	
	# JONSWAP 峰值增強
	var sigma = 0.07 if omega <= omega_p else 0.09
	var gamma_exp = exp(-pow(omega - omega_p, 2.0) / (2.0 * sigma * sigma * omega_p * omega_p))
	var gamma_term = pow(JONSWAP_GAMMA, gamma_exp)
	
	# 完整頻譜
	return alpha * pow(GRAVITY, 2.0) / pow(omega, 5.0) * exp_term * gamma_term

## 生成物理驅動的波浪層參數
## @return: Array of [wavelength_mult, steepness_mult, speed_mult, angle_offset]
func _generate_jonswap_wave_layers() -> Array:
	var layers = []
	var wind_speed = max(wind_strength * 10.0, 1.0) # 轉換為 m/s，最小 1m/s
	
	# 頻率採樣範圍（覆蓋主要能量區域）
	const FREQ_MIN = 0.05 # 20秒週期（長波浪）
	const FREQ_MAX = 1.2 # 0.83秒週期（短波浪）
	const FREQ_STEP = (FREQ_MAX - FREQ_MIN) / 8.0
	
	# ===== 新增：自適應安全係數 (Scheme B) =====
	# 高風速下更保守（防止破碎）
	var safety_factor = 1.0
	
	# === 修改：提高閾值，允許更陡的波浪 (Scheme 2) ===
	if wind_speed > 50.0: # 提高閾值 (原25.0)
		safety_factor = 0.85 # 從 0.7 提高到 0.85
	elif wind_speed > 30.0: # 提高閾值 (原15.0)
		safety_factor = 0.95 # 從 0.85 提高到 0.95
	# ===================================
	
	for i in range(8):
		var freq = FREQ_MIN + i * FREQ_STEP
		
		# 1. 從頻譜計算能量
		var energy = _calculate_jonswap_spectrum(freq, wind_speed)
		
		# 2. 能量 → 振幅（方差積分）
		var amplitude = sqrt(2.0 * energy * FREQ_STEP)
		
		# 3. 波長（深水色散關係）
		var wavelength = GRAVITY / (TWO_PI * freq * freq)
		
		# 4. 物理限制：Stokes 破碎條件
		# Stokes 理論極限：H/λ = 0.142
		# 實際海洋觀測：H/λ ≈ 0.10-0.12（更保守）
		
		# === 修改：允許更陡的波浪 (Scheme 2) ===
		var max_amplitude = 0.15 * wavelength * safety_factor # 從 0.12 提高到 0.15 (Scheme 2 relaxation)
		amplitude = min(amplitude, max_amplitude)
		
		# 5. 計算陡峭度（用於 Gerstner）
		var k = TWO_PI / wavelength
		var steepness = k * amplitude # Q = kA
		
		# 6. 相速度（深水波）
		var phase_speed = sqrt(GRAVITY / k)
		
		# 7. 歸一化參數（相對於 wave_length 基準）
		var wavelength_mult = wavelength / max(wave_length, 1.0)
		var steepness_mult = steepness # 已經是無量綱
		var speed_mult = phase_speed / sqrt(GRAVITY / (TWO_PI / wave_length))
		
		# 8. 隨機相位分佈（保持視覺多樣性）
		var angle_offset = randf() * TWO_PI
		
		layers.append([wavelength_mult, steepness_mult, speed_mult, angle_offset])
	
	return layers

## 獲取優化的波浪層（帶緩存）
## @return: 波浪層參數數組
func _get_optimized_wave_layers() -> Array:
	# 快速哈希檢查（避免浮點比較誤差）
	# var current_hash = hash([wind_strength, wave_length]) # Use custom hash if unstable
	var current_hash = int(wind_strength * 1000) * 10000 + int(wave_length * 1000)
	
	if current_hash == _jonswap_cache.wind_hash:
		_jonswap_cache.hit_count += 1
		return _jonswap_cache.layers # ✅ 緩存命中（零消耗）
	
	# 緩存未命中，重新計算
	_jonswap_cache.miss_count += 1
	_jonswap_cache.layers = _generate_jonswap_wave_layers()
	_jonswap_cache.wind_hash = current_hash
	_jonswap_cache.last_update = Time.get_ticks_msec() / 1000.0
	
	print("[JONSWAP] 波浪層已更新 | 風速: %.1f m/s | 緩存命中率: %.1f%%" % [
		wind_strength * 10.0,
		100.0 * float(_jonswap_cache.hit_count) / max(float(_jonswap_cache.hit_count + _jonswap_cache.miss_count), 1.0)
	])
	
	return _jonswap_cache.layers


## Returns the water height at a specific global position (y-coordinate).
## Includes Gerstner waves, Rogue Wave, and SWE height (if accessible).
## Note: Does NOT include FFT high-frequency details as they are GPU-only.
func get_wave_height_at(global_pos: Vector3) -> float:
	var total_height = global_position.y # Start at water level
	
	# 1. Sync Time
	# We use the same time variable as the shader
	# Use physics_time if in physics frame to ensure query stability
	var t = physics_time
	if not Engine.is_in_physics_frame():
		t += (accumulated_time)
	
	var world_pos_2d = Vector2(global_pos.x, global_pos.z)
	
	# 2. Gerstner Waves (Low Frequency) with Jacobian Check
	if wind_strength > 0.001:
		# 1. 檢查 Jacobian
		# Note: Jacobian check is expensive, maybe skip for simple buoyant objects?
		# For now, enable it as per "Final Protection" scheme.
		var jac = _calculate_gerstner_jacobian(world_pos_2d, t)
		
		# 2. 如果接近折疊（J < 0.2），降低波高
		# ✅ Scheme D: 更寬柔的衰減 (0.1 - 0.5)
		var safety_mult = smoothstep(0.1, 0.5, jac)
		
		# 3. 應用安全係數
		total_height += _calculate_gerstner_height(world_pos_2d, t) * safety_mult
	
	# 3. Rogue Wave
	if rogue_wave_present:
		total_height += _calculate_rogue_wave_height(world_pos_2d)
		
	# 4. SWE Simulation Height (Optional/Advanced)
	# ... (Sim reading omitted)
	
	return total_height

func _calculate_gerstner_height(pos_xz: Vector2, t: float) -> float:
	var height_accum = 0.0
	var base_angle = atan2(wind_direction.y, wind_direction.x)
	
	# ✅ 使用 JONSWAP 動態生成的波浪層
	var wave_layers = _get_optimized_wave_layers()
	
	# == 方案 A 修改開始 ==
	# 計算總陡峭度（用於安全檢查）
	var total_steepness = 0.0
	for layer in wave_layers:
		# JONSWAP 返回的 layer[1] 已經是物理 Q 值
		# 不應該再乘以 wind_strength！
		total_steepness += layer[1]
	
	# 全局安全縮放（Stokes 極限：總 Q < 1.0）
	var safety_scale = 1.0
	if total_steepness > 0.75: # 保守限制 0.75 而非 1.0
		safety_scale = 0.75 / total_steepness
	
	# 疊加 8 層波浪
	for i in range(wave_layers.size()):
		var layer = wave_layers[i]
		var w_len = layer[0] * wave_length
		
		# ✅ Scheme A: 物理正確的陡度疊加 (Energy Conservation)
		# 使用 sqrt(wave_steepness) 作為全局能量縮放，而非直接乘法
		var w_steep = layer[1] * sqrt(wave_steepness) * safety_scale
		
		var w_speed = layer[2]
		var w_angle = base_angle + layer[3] * wave_chaos
		
		var k = 2.0 * PI / w_len
		var c = sqrt(9.81 / k) * w_speed
		
		var d = Vector2(cos(w_angle), sin(w_angle))
		var f = k * (d.dot(pos_xz) - c * t)
		
		# 從陡峭度計算振幅
		var a = (w_steep / k) if k > 0.001 else 0.0
		
		# Trochoidal 高度
		var h = sin(f)
		
		# ✅ Scheme B: 長波變形，短波保持平滑 (Shape Refinement)
		# 僅對前 4 層 (長波) 應用銳化，避免高頻噪聲
		if peak_sharpness != 1.0 and i <= 3:
			var s = h * 0.5 + 0.5
			h = pow(s, peak_sharpness) * 2.0 - 1.0
		
		height_accum += a * h
	
	return height_accum

## 計算帶傾斜效果的 Gerstner 波高 (Scheme 2: Shader 增強)
## @param pos_xz: 世界坐標 XZ
## @param t: 時間
## @param tilt_factor: 傾斜係數 (0.0-1.0)
## @return: [height, tilt_offset_x, tilt_offset_z]
func _calculate_gerstner_height_with_tilt(pos_xz: Vector2, t: float, tilt_factor: float = 0.0) -> Dictionary:
	var height_accum = 0.0
	var tilt_offset = Vector2.ZERO
	var base_angle = atan2(wind_direction.y, wind_direction.x)
	
	var wave_layers = _get_optimized_wave_layers()
	
	# 計算安全縮放
	var total_steepness = 0.0
	for layer in wave_layers:
		total_steepness += layer[1]
	var safety_scale = 1.0
	if total_steepness > 0.75:
		safety_scale = 0.75 / total_steepness
	
	for i in range(wave_layers.size()):
		var layer = wave_layers[i]
		var w_len = layer[0] * wave_length
		# ✅ Scheme A: 物理正確的陡度疊加
		var w_steep = layer[1] * sqrt(wave_steepness) * safety_scale
		var w_speed = layer[2]
		var w_angle = base_angle + layer[3] * wave_chaos
		
		var k = 2.0 * PI / w_len
		var c = sqrt(9.81 / k) * w_speed
		var d = Vector2(cos(w_angle), sin(w_angle))
		var f = k * (d.dot(pos_xz) - c * t)
		var a = (w_steep / k) if k > 0.001 else 0.0
		
		# === 新增：波浪形狀修改 ===
		var h = sin(f)
		
		# 1. 不對稱峰值（模擬波浪前傾）
		# ✅ Scheme B: 僅對長波應用 (Layers 0-3)
		if peak_sharpness != 1.0 and i <= 3:
			var s = h * 0.5 + 0.5
			# 使用不對稱函數
			if h > 0.0: # 波峰
				h = pow(s, peak_sharpness) * 2.0 - 1.0
			else: # 波谷（保持平緩）
				h = pow(s, peak_sharpness * 0.7) * 2.0 - 1.0
		
		# 2. 傾斜偏移（創建"捲曲"效果）
		if tilt_factor > 0.0 and h > 0.3: # 只在波峰附近傾斜
			# 計算傾斜方向（波浪前進方向）
			var tilt_strength = a * h * tilt_factor * smoothstep(0.3, 1.0, h)
			tilt_offset += d * tilt_strength
		
		height_accum += a * h
	
	return {
		"height": height_accum,
		"tilt": tilt_offset
	}

## 公開接口：獲取帶傾斜的波高
func get_wave_height_with_tilt(global_pos: Vector3, tilt_factor: float = 0.0) -> Dictionary:
	var t = physics_time
	if not Engine.is_in_physics_frame():
		t += accumulated_time
	
	var world_pos_2d = Vector2(global_pos.x, global_pos.z)
	var result = {"height": global_position.y, "tilt": Vector2.ZERO}
	
	if wind_strength > 0.001:
		var gerstner = _calculate_gerstner_height_with_tilt(world_pos_2d, t, tilt_factor)
		
		# Jacobian 安全檢查
		var jac = _calculate_gerstner_jacobian(world_pos_2d, t)
		# ✅ Scheme D: 更寬柔的衰減 (0.1 - 0.5)
		var safety_mult = smoothstep(0.1, 0.5, jac)
		
		result.height += gerstner.height * safety_mult
		result.tilt = gerstner.tilt * safety_mult
	
	if rogue_wave_present:
		result.height += _calculate_rogue_wave_height(world_pos_2d)
	
	return result

## 計算 Gerstner 波的 Jacobian 行列式（檢測折疊）
## 返回值 < 0 表示波形自相交
func _calculate_gerstner_jacobian(pos_xz: Vector2, t: float) -> float:
	var wave_layers = _get_optimized_wave_layers()
	var base_angle = atan2(wind_direction.y, wind_direction.x)
	
	# Jacobian 初始為單位矩陣的行列式 = 1.0
	var jacobian = 1.0
	
	var total_steepness = 0.0
	for layer in wave_layers:
		total_steepness += layer[1]
	var safety_scale = 1.0
	if total_steepness > 0.75:
		safety_scale = 0.75 / total_steepness

	for layer in wave_layers:
		var w_len = layer[0] * wave_length
		# ✅ Scheme A: 物理正確的陡度疊加
		var w_steep = layer[1] * sqrt(wave_steepness) * safety_scale
		var w_speed = layer[2]
		var w_angle = base_angle + layer[3] * wave_chaos
		
		var k = 2.0 * PI / w_len
		var c = sqrt(9.81 / k) * w_speed
		var d = Vector2(cos(w_angle), sin(w_angle))
		var f = k * (d.dot(pos_xz) - c * t)
		# A = Steepness / k
		var a = (w_steep / k) if k > 0.001 else 0.0
		
		# Gerstner 波的 Jacobian 貢獻：
		# J *= (1 - k*A*cos(f))
		jacobian *= (1.0 - k * a * cos(f))
	
	return jacobian


func _calculate_rogue_wave_height(pos_xz: Vector2) -> float:
	if rogue_wave_height <= 0.01: return 0.0
	
	var center = _rogue_current_pos
	var height = rogue_wave_height
	var width = rogue_wave_width
	
	# Assume wave direction matches wind (as in shader)
	var wave_dir = wind_direction.normalized()
	
	var dist_long = (pos_xz - center).dot(wave_dir)
	var dist_lat = (pos_xz - center).dot(Vector2(-wave_dir.y, wave_dir.x))
	
	if abs(dist_long) > width or abs(dist_lat) > width * 2.0:
		return 0.0
		
	# Replicate Sech-Tanh envelope math
	# envelope texture maps [-Width, Width] -> [0, 1] UV -> Value
	
	# u goes from 0 to 1 across the width
	# dist_long goes from -width to +width? 
	# In shader: sample_envelope(dist_long, width)
	# float u = clamp((dist / width) * 0.5 + 0.5, 0.0, 1.0);
	var u = clamp((dist_long / width) * 0.5 + 0.5, 0.0, 1.0)
	
	# Math from _generate_envelope_texture
	var x = (u * 2.0 - 1.0) * 4.0 # Range [-4, 4]
	var sech = 2.0 / (exp(x) + exp(-x))
	var distortion = 1.0 - 0.3 * tanh(x)
	var val = sech * distortion
	val = clamp(val, 0.0, 1.0)
	
	# Lateral falloff (Smoothstep from shader)
	# smoothstep(width * 2.0, width, abs(dist_lat))
	var lat_falloff = smoothstep(width * 2.0, width, abs(dist_lat))
	
	# ========== 新增：二階平滑濾波 ==========
	# 使用 smoothstep 再次平滑，避免突變
	var final_envelope = smoothstep(0.0, 1.0, val * lat_falloff)
	# ======================================
	
	return final_envelope * height

func _init_default_normals():
	if not normal_map1:
		var noise1 = FastNoiseLite.new()
		noise1.seed = 12345
		noise1.frequency = 0.05
		var tex1 = NoiseTexture2D.new()
		tex1.width = 512
		tex1.height = 512
		tex1.seamless = true
		tex1.as_normal_map = true
		tex1.noise = noise1
		normal_map1 = tex1
		print("[WaterManager] Normal Map 1 created (Force Init): ", normal_map1)

	if not normal_map2:
		var noise2 = FastNoiseLite.new()
		noise2.seed = 67890
		noise2.frequency = 0.08
		var tex2 = NoiseTexture2D.new()
		tex2.width = 512
		tex2.height = 512
		tex2.seamless = true
		tex2.as_normal_map = true
		tex2.noise = noise2
		normal_map2 = tex2
		print("[WaterManager] Normal Map 2 created (Force Init): ", normal_map2)
	if not normal_map1:
		var noise1 = FastNoiseLite.new()
		noise1.seed = 12345
		noise1.frequency = 0.05
		var tex1 = NoiseTexture2D.new()
		tex1.width = 512
		tex1.height = 512
		tex1.seamless = true
		tex1.as_normal_map = true
		tex1.noise = noise1
		normal_map1 = tex1

	if not normal_map2:
		var noise2 = FastNoiseLite.new()
		noise2.seed = 67890
		noise2.frequency = 0.08
		var tex2 = NoiseTexture2D.new()
		tex2.width = 512
		tex2.height = 512
		tex2.seamless = true
		tex2.as_normal_map = true
		tex2.noise = noise2
		normal_map2 = tex2

func _init_caustics_noise():
	if not caustics_texture:
		var noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.frequency = 0.05
		
		var tex = NoiseTexture2D.new()
		tex.width = 512
		tex.height = 512
		tex.seamless = true
		tex.as_normal_map = false
		tex.noise = noise
		caustics_texture = tex

func _init_foam_noise():
	if not foam_noise_tex:
		foam_noise_tex = NoiseTexture2D.new()
		foam_noise_tex.width = 256
		foam_noise_tex.height = 256
		foam_noise_tex.seamless = true
		var noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.frequency = 0.05
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		foam_noise_tex.noise = noise

@export_subgroup("Rogue Wave")
@export var rogue_wave_present: bool = false:
	set(v): rogue_wave_present = v; _update_shader_params_deferred()
@export var rogue_wave_height: float = 4.0:
	set(v): rogue_wave_height = v; _update_shader_params_deferred()
@export var rogue_wave_width: float = 25.0:
	set(v): rogue_wave_width = v; _update_shader_params_deferred()
@export var rogue_wave_speed: float = 6.0:
	set(v): rogue_wave_speed = v; _update_shader_params_deferred()
@export var rogue_start_dist: float = 100.0 # Distance from center to start
@export var rogue_direction: Vector2 = Vector2(1.0, 0.5)

@export_group("LOD Settings")
@export var lod_scale: float = 1.0:
	set(v): lod_scale = v; _update_shader_params_deferred()

var _rogue_wave_timer: float = 0.0
var _rogue_current_pos: Vector2 = Vector2.ZERO

func _generate_envelope_texture():
	var width = 512
	var img = Image.create(width, 1, false, Image.FORMAT_R8) # Only need R8 for single channel envelope
	
	# Asymmetric Envelope Generation (Sech-based)
	# "Steep Front, Gentle Back"
	# Mapping [0, 1] texture to physical space. 
	# Let's assume the texture covers the range [-Width, Width] of the wave packet.
	
	for i in range(width):
		var u = float(i) / float(width)
		var x = (u * 2.0 - 1.0) * 4.0 # Range [-4, 4] effectively
		
		# Hyperbolic Secant (Sech = 1/cosh) for the main peak
		var sech = 2.0 / (exp(x) + exp(-x))
		
		# Tanh distortion for asymmetry
		# We want forward side (x > 0) to be steeper? Or backward? 
		# Usually rogue waves are "Holes in the sea" or "Wall of water".
		# Let's make it a sharp peak.
		var distortion = 1.0 - 0.3 * tanh(x)
		
		var val = sech * distortion
		
		# Normalize roughly to 0-1 range if needed, but Sech max is 1.
		# Clamp to valid range
		val = clamp(val, 0.0, 1.0)
		
		img.set_pixel(i, 0, Color(val, 0, 0, 1.0))
	
	envelope_texture = ImageTexture.create_from_image(img)
	_update_shader_params_deferred()

func _setup_simulation():
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	shader_rid = _load_compute_shader(SOLVER_PATH)
	if shader_rid.is_valid():
		pipeline_rid = rd.compute_pipeline_create(shader_rid)
	
	var fmt = RDTextureFormat.new()
	fmt.width = grid_res
	fmt.height = grid_res
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var data = PackedByteArray()
	data.resize(grid_res * grid_res * 16)
	data.fill(0)
	sim_texture_A = rd.texture_create(fmt, RDTextureView.new(), [data])
	sim_texture_B = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	var buffer_size = MAX_INTERACTIONS * 16
	interaction_buffer = rd.storage_buffer_create(buffer_size)

	var u_in_A = RDUniform.new()
	u_in_A.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_in_A.binding = 0
	u_in_A.add_id(sim_texture_A)
	
	var u_out_B = RDUniform.new()
	u_out_B.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out_B.binding = 1
	u_out_B.add_id(sim_texture_B)
	
	var u_buffer = RDUniform.new()
	u_buffer.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_buffer.binding = 2
	u_buffer.add_id(interaction_buffer)
	
	uniform_set_A = rd.uniform_set_create([u_in_A, u_out_B, u_buffer], shader_rid, 0)
	
	var u_in_B = RDUniform.new()
	u_in_B.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_in_B.binding = 0
	u_in_B.add_id(sim_texture_B)
	
	var u_out_A = RDUniform.new()
	u_out_A.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out_A.binding = 1
	u_out_A.add_id(sim_texture_A)
	
	uniform_set_B = rd.uniform_set_create([u_in_B, u_out_A, u_buffer], shader_rid, 0)
	
	sim_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAF)
	sim_image.fill(Color(0, 0, 0, 1))
	visual_texture = ImageTexture.create_from_image(sim_image)
	rd.texture_update(sim_texture_A, 0, sim_image.get_data())
	rd.texture_update(sim_texture_B, 0, sim_image.get_data())
	
	_setup_fft_pipeline()

func _load_compute_shader(path: String) -> RID:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f: return RID()
	var src = RDShaderSource.new()
	src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, f.get_as_text())
	var spirv = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("[WaterManager] Shader Error (%s): %s" % [path, spirv.compile_error_compute])
		return RID()
	return rd.shader_create_from_spirv(spirv)

func _bake_obstacles():
	if not is_inside_tree(): return
	var world = get_world_3d()
	if not world or not world.direct_space_state: return
	
	var space_state = world.direct_space_state
	var obstacles_hit = 0
	
	for y in range(grid_res):
		for x in range(grid_res):
			var col = sim_image.get_pixel(x, y)
			col.b = 0.0
			sim_image.set_pixel(x, y, col)
	
	for y in range(grid_res):
		for x in range(grid_res):
			var uv = Vector2(x, y) / float(grid_res)
			var local_pos = Vector3((uv.x - 0.5) * sea_size.x, 100.0, (uv.y - 0.5) * sea_size.y)
			var world_pos = to_global(local_pos)
			
			var query = PhysicsRayQueryParameters3D.create(world_pos, world_pos + Vector3.DOWN * 200.0)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			
			var result = space_state.intersect_ray(query)
			if result:
				if result.position.y > global_position.y - 2.0:
					var col = sim_image.get_pixel(x, y)
					col.b = 1.0
					sim_image.set_pixel(x, y, col)
					obstacles_hit += 1
	
	if rd:
		rd.texture_update(sim_texture_A, 0, sim_image.get_data())
		rd.texture_update(sim_texture_B, 0, sim_image.get_data())
	visual_texture.update(sim_image)
	
	_setup_weather_pipeline()
	
	print("[WaterManager] Obstacles baked: ", obstacles_hit)

func _setup_weather_pipeline():
	if not rd: return
	
	# 1. Weather Influence Texture (RGBA16F)
	var fmt = RDTextureFormat.new()
	fmt.width = grid_res
	fmt.height = grid_res
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var data = PackedByteArray()
	data.resize(grid_res * grid_res * 8) # 2 bytes per channel * 4 channels
	data.fill(0)
	weather_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	weather_image = Image.create(grid_res, grid_res, false, Image.FORMAT_RGBAH)
	weather_image.fill(Color(0, 0, 0, 0))
	weather_visual_tex = ImageTexture.create_from_image(weather_image)
	
	# 2. Compile Vortex Shader
	if FileAccess.file_exists(VORTEX_SHADER_PATH):
		vortex_shader_rid = _load_compute_shader(VORTEX_SHADER_PATH)
		if vortex_shader_rid.is_valid():
			vortex_pipeline_rid = rd.compute_pipeline_create(vortex_shader_rid)
			vortex_params_buffer = rd.storage_buffer_create(64) # Buffer for VortexParams
			
	# 3. Compile Waterspout Shader
	if FileAccess.file_exists(WATERSPOUT_SHADER_PATH):
		waterspout_shader_rid = _load_compute_shader(WATERSPOUT_SHADER_PATH)
		if waterspout_shader_rid.is_valid():
			waterspout_pipeline_rid = rd.compute_pipeline_create(waterspout_shader_rid)
			waterspout_params_buffer = rd.storage_buffer_create(64) # Buffer for VortexParams
	
	# Cache Weather Uniform Sets
	if vortex_shader_rid.is_valid():
		for sim_tex in [sim_texture_A, sim_texture_B]:
			var u_swe = RDUniform.new(); u_swe.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_swe.binding = 0; u_swe.add_id(sim_tex)
			var u_weather = RDUniform.new(); u_weather.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_weather.binding = 1; u_weather.add_id(weather_texture)
			var u_params = RDUniform.new(); u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; u_params.binding = 2; u_params.add_id(vortex_params_buffer)
			vortex_sets.append(rd.uniform_set_create([u_swe, u_weather, u_params], vortex_shader_rid, 0))
	
	if waterspout_shader_rid.is_valid():
		for sim_tex in [sim_texture_A, sim_texture_B]:
			var u_swe = RDUniform.new(); u_swe.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_swe.binding = 0; u_swe.add_id(sim_tex)
			var u_weather = RDUniform.new(); u_weather.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_weather.binding = 1; u_weather.add_id(weather_texture)
			var u_params = RDUniform.new(); u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; u_params.binding = 2; u_params.add_id(waterspout_params_buffer)
			waterspout_sets.append(rd.uniform_set_create([u_swe, u_weather, u_params], waterspout_shader_rid, 0))

func _setup_fft_pipeline():
	if not rd: return
	
	var fmt = RDTextureFormat.new()
	fmt.width = grid_res
	fmt.height = grid_res
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT # Complex: (h_re, h_im, h0_re, h0_im)
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	var data = PackedByteArray()
	data.resize(grid_res * grid_res * 16)
	data.fill(0)
	
	fft_h0_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	fft_ht_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	fft_ping_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	fft_pong_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	fft_displace_texture = rd.texture_create(fmt, RDTextureView.new(), [data])
	
	fft_init_shader = _load_compute_shader(FFT_INIT_PATH)
	if fft_init_shader.is_valid(): fft_init_pipeline = rd.compute_pipeline_create(fft_init_shader)
	fft_update_shader = _load_compute_shader(FFT_UPDATE_PATH)
	if fft_update_shader.is_valid(): fft_update_pipeline = rd.compute_pipeline_create(fft_update_shader)
	fft_butterfly_shader = _load_compute_shader(FFT_BUTTERFLY_PATH)
	if fft_butterfly_shader.is_valid(): fft_butterfly_pipeline = rd.compute_pipeline_create(fft_butterfly_shader)
	fft_displace_shader = _load_compute_shader(FFT_DISPLACE_PATH)
	if fft_displace_shader.is_valid(): fft_displace_pipeline = rd.compute_pipeline_create(fft_displace_shader)
	
	# Cache FFT Uniform Sets
	if fft_init_shader.is_valid():
		var u_h0 = RDUniform.new(); u_h0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_h0.binding = 0; u_h0.add_id(fft_h0_texture)
		fft_init_set = rd.uniform_set_create([u_h0], fft_init_shader, 0)
	
	if fft_update_shader.is_valid():
		var u_h0 = RDUniform.new(); u_h0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_h0.binding = 0; u_h0.add_id(fft_h0_texture)
		var u_ht = RDUniform.new(); u_ht.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_ht.binding = 1; u_ht.add_id(fft_ht_texture)
		fft_update_set = rd.uniform_set_create([u_h0, u_ht], fft_update_shader, 0)
		
	if fft_butterfly_shader.is_valid():
		var pairs = [[fft_ht_texture, fft_ping_texture], [fft_ping_texture, fft_pong_texture], [fft_pong_texture, fft_ping_texture]]
		for p in pairs:
			var u_in = RDUniform.new(); u_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_in.binding = 0; u_in.add_id(p[0])
			var u_out = RDUniform.new(); u_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_out.binding = 1; u_out.add_id(p[1])
			fft_butterfly_sets.append(rd.uniform_set_create([u_in, u_out], fft_butterfly_shader, 0))
			
	if fft_displace_shader.is_valid():
		for tex in [fft_ping_texture, fft_pong_texture]:
			var u_fft = RDUniform.new(); u_fft.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_fft.binding = 0; u_fft.add_id(tex)
			var u_disp = RDUniform.new(); u_disp.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u_disp.binding = 1; u_disp.add_id(fft_displace_texture)
			fft_displace_sets.append(rd.uniform_set_create([u_fft, u_disp], fft_displace_shader, 0))
	
	_run_fft_init()
	
	fft_displace_tex = Texture2DRD.new()
	fft_displace_tex.texture_rd_rid = fft_displace_texture
	

func _run_fft_init():
	if not fft_init_shader.is_valid(): return
	
	if not fft_init_set.is_valid(): return
	var u_set = fft_init_set
	
	var pc = StreamPeerBuffer.new()
	pc.put_32(grid_res)
	pc.put_float(max(sea_size.x, sea_size.y))
	pc.put_float(wind_strength)
	pc.put_float(0.0) # Padding for vec2 alignment
	pc.put_float(wind_direction.x)
	pc.put_float(wind_direction.y)
	pc.put_float(0.0) # time
	pc.put_float(0.0) # Padding to 32 bytes
	
	if not fft_init_pipeline.is_valid(): return
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, fft_init_pipeline)
	rd.compute_list_bind_uniform_set(cl, u_set, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()

func _setup_visuals():
	var lod_node = get_node_or_null("OceanLOD")
	var mesh_inst = get_node_or_null("WaterPlane")

	if use_lod:
		if mesh_inst: mesh_inst.visible = false
		if not lod_node:
			lod_node = Node3D.new()
			lod_node.name = "OceanLOD"
			lod_node.set_script(load("res://NewWaterSystem/Core/Scripts/OceanLODManager.gd"))
			add_child(lod_node)
			lod_node.water_manager = self
		else:
			if lod_node.has_method("rebuild"):
				lod_node.rebuild()
		lod_node.visible = true
	else:
		if lod_node: lod_node.visible = false
		if not mesh_inst:
			mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "WaterPlane"
			var mesh = PlaneMesh.new()
			mesh.size = sea_size
			mesh.subdivide_depth = grid_res - 1
			mesh.subdivide_width = grid_res - 1
			mesh_inst.mesh = mesh
			add_child(mesh_inst)
		mesh_inst.visible = true
		mesh_inst.mesh.size = sea_size
		if mesh_inst.mesh is PlaneMesh:
			mesh_inst.mesh.subdivide_width = grid_res - 1
			mesh_inst.mesh.subdivide_depth = grid_res - 1
		
	var target_mesh = lod_node.cascades[0] if use_lod and not lod_node.cascades.is_empty() else mesh_inst
	if not target_mesh: return
	
	var mat = target_mesh.get_surface_override_material(0)
	if not mat or not mat is ShaderMaterial:
		mat = ShaderMaterial.new()
		if FileAccess.file_exists(SURFACE_SHADER_PATH):
			mat.shader = load(SURFACE_SHADER_PATH)
		else:
			print("[WaterManager] Warning: Surface shader not found at ", SURFACE_SHADER_PATH)
		mesh_inst.set_surface_override_material(0, mat)

func _update_shader_parameters():
	if not is_inside_tree(): return
	var mesh_inst = get_node_or_null("WaterPlane")
	if not mesh_inst: return
	var mat = mesh_inst.get_surface_override_material(0)
	if not mat: return
	
	mat.set_shader_parameter("swe_texture", visual_texture)
	mat.set_shader_parameter("fft_texture", fft_displace_tex)
	mat.set_shader_parameter("weather_influence", weather_visual_tex)
	mat.set_shader_parameter("sea_size", sea_size)
	mat.set_shader_parameter("manager_world_pos", global_position)
	
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("wind_dir", wind_direction)
	mat.set_shader_parameter("wave_steepness", wave_steepness)
	mat.set_shader_parameter("wave_length", wave_length)
	mat.set_shader_parameter("horizontal_displacement_scale", horizontal_displacement_scale)
	mat.set_shader_parameter("wave_chaos", wave_chaos)
	mat.set_shader_parameter("swe_strength", swe_strength)
	mat.set_shader_parameter("debug_show_markers", debug_show_markers)
	mat.set_shader_parameter("color_deep", color_deep)
	mat.set_shader_parameter("color_shallow", color_shallow)
	mat.set_shader_parameter("absorption_coeff", absorption_coeff)
	mat.set_shader_parameter("color_foam", color_foam)
	mat.set_shader_parameter("foam_noise", foam_noise_tex)
	mat.set_shader_parameter("envelope_tex", envelope_texture)
	
	mat.set_shader_parameter("metallic", metallic)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("specular", specular)
	mat.set_shader_parameter("fresnel_strength", fresnel_strength)
	mat.set_shader_parameter("reflection_strength", reflection_strength)
	mat.set_shader_parameter("peak_sharpness", peak_sharpness)
	mat.set_shader_parameter("sss_strength", sss_strength)
	mat.set_shader_parameter("sss_color", sss_color)
	mat.set_shader_parameter("edge_scale", edge_fade)
	
	mat.set_shader_parameter("foam_shore_spread", foam_shore_spread)
	mat.set_shader_parameter("foam_shore_strength", foam_shore_strength)
	mat.set_shader_parameter("foam_crest_spread", foam_crest_spread)
	mat.set_shader_parameter("foam_wake_strength", foam_wake_strength)
	mat.set_shader_parameter("storm_mode", storm_mode)
	mat.set_shader_parameter("foam_jacobian_bias", foam_jacobian_bias)
	
	mat.set_shader_parameter("caustics_texture", caustics_texture)
	mat.set_shader_parameter("caustics_strength", caustics_strength)
	mat.set_shader_parameter("caustics_scale", caustics_scale)
	mat.set_shader_parameter("caustics_speed", caustics_speed)
	
	mat.set_shader_parameter("normal_map1", normal_map1)
	mat.set_shader_parameter("normal_map2", normal_map2)
	mat.set_shader_parameter("normal_scale", normal_scale)
	mat.set_shader_parameter("normal_speed", normal_speed)
	mat.set_shader_parameter("normal_tile", normal_tile)
	
	# Debug print for visuals (Run once or spammed? Call deferred is better, but this is safe here)
	if debug_view:
		print("[Shader] Normals -> Map1: ", normal_map1, " | Map2: ", normal_map2, " | Scale: ", normal_scale)
	mat.set_shader_parameter("show_wireframe", show_wireframe)
	mat.set_shader_parameter("fft_scale", fft_scale)
	mat.set_shader_parameter("lod_scale", lod_scale)
	
	mat.set_shader_parameter("flow_map", flow_map)
	mat.set_shader_parameter("flow_speed", flow_speed)
	mat.set_shader_parameter("flow_strength", flow_strength)
	mat.set_shader_parameter("far_fade_start", far_fade_start)
	mat.set_shader_parameter("far_fade_max", far_fade_max)
	mat.set_shader_parameter("debug_view", debug_view)
	mat.set_shader_parameter("debug_mesh_only", debug_mesh_only)
	
	# Initial Rogue Wave State
	if rogue_wave_present:
		mat.set_shader_parameter("rogue_wave_data", Vector4(_rogue_current_pos.x, _rogue_current_pos.y, rogue_wave_height, rogue_wave_width))
	else:
		mat.set_shader_parameter("rogue_wave_data", Vector4(0, 0, 0, 1))
	
	if use_lod and has_node("OceanLOD"):
		for cascade in $OceanLOD.cascades:
			cascade.set_surface_override_material(0, mat)
	
	mat.set_shader_parameter("physics_time", physics_time)
	var render_alpha = accumulated_time / (1.0 / 60.0)
	mat.set_shader_parameter("render_alpha", render_alpha)

func _process(delta):
	if not rd or not _is_initialized: return
	
	accumulated_time += delta
	
	if interaction_points.is_empty() and active_vortex == null and active_waterspout == null:
		_idle_timer += delta
		if _idle_timer > 2.0:
			_reset_swe_texture()
			_idle_timer = 0.0
	else:
		_idle_timer = 0.0
	
	_time = Time.get_ticks_msec() / 1000.0
	
	var plane = get_node_or_null("WaterPlane")
	if plane:
		var mat = plane.get_surface_override_material(0)
		if mat:
			mat.set_shader_parameter("manager_world_pos", global_position)
			mat.set_shader_parameter("physics_time", physics_time)
			mat.set_shader_parameter("render_alpha", accumulated_time / (1.0 / 60.0))
	
	if has_submitted:
		# rd.sync() is not allowed on main device
		has_submitted = false
		
		# Update SWE Texture
		var result_texture = sim_texture_A if current_sim_idx == 0 else sim_texture_B
		if result_texture.is_valid():
			var data = rd.texture_get_data(result_texture, 0)
			if not data.is_empty():
				sim_image.set_data(grid_res, grid_res, false, Image.FORMAT_RGBAF, data)
				visual_texture.update(sim_image)
			
		# Update Weather Texture (Visual only for foam/color modulation)
		if weather_texture.is_valid():
			var w_data = rd.texture_get_data(weather_texture, 0)
			if not w_data.is_empty():
				weather_image.set_data(grid_res, grid_res, false, Image.FORMAT_RGBAH, w_data)
				weather_visual_tex.update(weather_image)
	
	var sim_delta = min(delta, 0.033)
	
	# Rogue Wave Animation
	if rogue_wave_present:
		_rogue_wave_timer += delta
		var dir_norm = rogue_direction.normalized()
		# Start from 'behind' and move 'forward'
		# Center point moves: StartPos + Dir * Speed * Time
		# Let's define StartPos as -Dir * StartDist relative to Manager
		var start_pos = global_position - Vector3(dir_norm.x, 0, dir_norm.y) * rogue_start_dist
		
		# Move wave across the domain
		var dist_travelled = _rogue_wave_timer * rogue_wave_speed
		
		# Reset if it goes too far (e.g. 2x start dist)
		if dist_travelled > rogue_start_dist * 3.0:
			_rogue_wave_timer = 0.0
			dist_travelled = 0.0
			
		var current_world_pos = start_pos + Vector3(dir_norm.x, 0, dir_norm.y) * dist_travelled
		_rogue_current_pos = Vector2(current_world_pos.x, current_world_pos.z)
		
		var mesh_inst = get_node_or_null("WaterPlane")
		if mesh_inst:
			var mat = mesh_inst.get_surface_override_material(0)
			if mat:
				# vec4: x, y, height, width
				mat.set_shader_parameter("rogue_wave_data", Vector4(_rogue_current_pos.x, _rogue_current_pos.y, rogue_wave_height, rogue_wave_width))
	else:
		_rogue_wave_timer = 0.0
		# Reset shader param to hide it
		var mesh_inst = get_node_or_null("WaterPlane")
		if mesh_inst:
			var mat = mesh_inst.get_surface_override_material(0)
			if mat:
				mat.set_shader_parameter("rogue_wave_data", Vector4(0, 0, 0, 1))

	_run_compute(sim_delta)
	interaction_points.clear()

func _physics_process(delta):
	physics_time += delta
	accumulated_time = 0.0
	
	_auto_adjust_for_safety()

	# GlobalWind Integration
	# Check if GlobalWind singleton exists (autoloaded name)
	if has_node("/root/GlobalWind"):
		var gw = get_node("/root/GlobalWind")
		if gw:
			# Smoothly interpolate towards global wind settings
			# Note: We use the existing setters which trigger shader updates
			if abs(wind_strength - gw.current_wind_strength) > 0.01:
				wind_strength = move_toward(wind_strength, gw.current_wind_strength, delta * 0.5)
			
			if not wind_direction.is_equal_approx(gw.current_wind_direction):
				wind_direction = wind_direction.lerp(gw.current_wind_direction, delta * 0.5).normalized()

## 自動優化參數（安全助手）
func _auto_adjust_for_safety():
	# === 修改：允許更高的陡峭度 ===
	if wind_strength > 8.0: # 從 5.0 提高到 8.0
		var adj_scale = 1.0 / (1.0 + (wind_strength - 8.0) * 0.03) # 減小懲罰係數
		wave_steepness = clamp(0.25 * adj_scale, 0.15, 0.30) # 提高上限
		peak_sharpness = clamp(3.0 * adj_scale, 1.5, 3.0) # 允許到 3.0


func trigger_ripple(world_pos: Vector3, strength: float = 1.0, radius: float = 0.05):
	var lp = to_local(world_pos)
	var uv = (Vector2(lp.x, lp.z) / sea_size) + Vector2(0.5, 0.5)
	var uv_radius = radius / max(sea_size.x, 1.0)
	var min_radius = 2.0 / float(grid_res)
	uv_radius = max(uv_radius, min_radius)
	interaction_points.append({"uv": uv, "strength": strength, "radius": uv_radius})

func trigger_vortex(world_pos: Vector3, radius: float = 10.0, intensity: float = 1.0, speed: float = 2.0, depth: float = 5.0):
	var lp = to_local(world_pos)
	active_vortex = {
		"position": Vector2(lp.x, lp.z),
		"radius": radius,
		"intensity": intensity,
		"speed": speed,
		"depth": depth
	}

func trigger_waterspout(world_pos: Vector3, radius: float = 8.0, intensity: float = 1.0, speed: float = 5.0):
	var lp = to_local(world_pos)
	active_waterspout = {
		"position": Vector2(lp.x, lp.z),
		"radius": radius,
		"intensity": intensity,
		"speed": speed
	}

func clear_skills():
	active_vortex = null
	active_waterspout = null
	# Reset weather texture
	if rd and weather_texture.is_valid():
		var data = PackedByteArray()
		data.resize(grid_res * grid_res * 8)
		data.fill(0)
		rd.texture_update(weather_texture, 0, data)

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var vp = get_viewport()
		var cam = vp.get_camera_3d() if vp else null
		if not cam: return
		
		var mpos = event.position
		var from = cam.project_ray_origin(mpos)
		var dir = cam.project_ray_normal(mpos)
		
		var plane = Plane(Vector3.UP, global_position.y)
		var hit = plane.intersects_ray(from, dir)
		
		if hit:
			trigger_ripple(hit, interact_strength, interact_radius)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_request_restart()
		elif event.keycode == KEY_J: # J = JONSWAP Debug
			_print_jonswap_debug()
		elif event.keycode == KEY_1:
			apply_deep_ocean_barrel_preset()
		elif event.keycode == KEY_2:
			apply_surfing_barrel_preset()

func _print_jonswap_debug():
	var layers = _get_optimized_wave_layers()
	print("=== JONSWAP 波浪層分析 ===")
	print("風速: %.1f m/s (%.0f 級風)" % [wind_strength * 10.0, _beaufort_scale(wind_strength * 10.0)])
	for i in range(layers.size()):
		var l = layers[i]
		print("  層 %d: λ=%.1fm, Q=%.3f, c=%.1fm/s" % [i + 1, l[0] * wave_length, l[1], l[2] * sqrt(9.81 * wave_length / TWO_PI)])
	print("緩存命中率: %.1f%%" % [100.0 * float(_jonswap_cache.hit_count) / max(float(_jonswap_cache.hit_count + _jonswap_cache.miss_count), 1.0)])

func _beaufort_scale(wind_speed_ms: float) -> int:
	var beaufort = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]
	for i in range(beaufort.size()):
		if wind_speed_ms < beaufort[i]:
			return i
	return 12

func _run_compute(dt):
	# 1. SWE Solver (Standard Interactions & Rain)
	var interact_count = min(interaction_points.size(), MAX_INTERACTIONS)
	if interact_count > 0:
		var floats = PackedFloat32Array()
		floats.resize(MAX_INTERACTIONS * 4)
		for i in range(interact_count):
			var p = interaction_points[i]
			var idx = i * 4
			floats[idx + 0] = p.uv.x
			floats[idx + 1] = p.uv.y
			floats[idx + 2] = p.strength
			floats[idx + 3] = p.radius
		var data_bytes = floats.to_byte_array()
		rd.buffer_update(interaction_buffer, 0, data_bytes.size(), data_bytes)
	
	var safe_dt = min(dt, 0.02)
	var pc = StreamPeerBuffer.new()
	pc.put_float(safe_dt)
	pc.put_float(damping)
	pc.put_float(propagation_speed)
	pc.put_32(interact_count)
	pc.put_float(rain_intensity)
	pc.put_float(_time)
	pc.put_float(sea_size.x)
	pc.put_float(sea_size.y)
	
	if not pipeline_rid.is_valid(): return
	var active_set = uniform_set_A if current_sim_idx == 0 else uniform_set_B
	if not active_set.is_valid(): return
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, active_set, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()
	
	_run_fft_pipeline(dt)
	
	# 2. Specialized Skills (Vortex/Waterspout)
	var current_swe = sim_texture_B if current_sim_idx == 0 else sim_texture_A # The one just written by SWE
	
	if active_vortex:
		_dispatch_vortex(current_swe)
	
	if active_waterspout:
		_dispatch_waterspout(current_swe)
		
	# _run_fft_displace() is already called inside _run_fft_pipeline

	has_submitted = true
	current_sim_idx = 1 - current_sim_idx


func _dispatch_vortex(_swe_tex: RID):
	if not vortex_pipeline_rid.is_valid(): return
	
	# Update Params
	var params = PackedFloat32Array([
		active_vortex.position.x, active_vortex.position.y,
		active_vortex.radius, active_vortex.intensity,
		active_vortex.speed, active_vortex.depth,
		_time, sea_size.x
	])
	rd.buffer_update(vortex_params_buffer, 0, params.size() * 4, params.to_byte_array())
	
	var uniform_set = vortex_sets[current_sim_idx]
	if not uniform_set.is_valid(): return
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, vortex_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()
	# Note: Uniform set will be freed by Godot's internal tracking if not stored, 
	# but for compute it's better to keep it or free it properly.
	# rd.free_rid(set) # Can't free immediately if submitted

func _dispatch_waterspout(_swe_tex: RID):
	if not waterspout_pipeline_rid.is_valid(): return
	
	# Update Params
	var params = PackedFloat32Array([
		active_waterspout.position.x, active_waterspout.position.y,
		active_waterspout.radius, active_waterspout.intensity,
		active_waterspout.speed, _time,
		sea_size.x, 0.0 # Padding
	])
	rd.buffer_update(waterspout_params_buffer, 0, params.size() * 4, params.to_byte_array())
	
	var uniform_set = waterspout_sets[current_sim_idx]
	if not uniform_set.is_valid(): return
	
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, waterspout_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()

func _run_fft_pipeline(_dt):
	if not rd or not fft_update_shader.is_valid(): return
	
	if not fft_update_set.is_valid(): return
	var u_set_update = fft_update_set
	
	var pc = StreamPeerBuffer.new()
	pc.put_32(grid_res); pc.put_float(max(sea_size.x, sea_size.y)); pc.put_float(physics_time)
	pc.put_float(0.0) # Padding to 16 bytes
	
	if not fft_update_pipeline.is_valid(): return
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, fft_update_pipeline)
	rd.compute_list_bind_uniform_set(cl, u_set_update, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()

	# 2. Butterfly Passes (Iterative)
	var log2res = int(round(log(grid_res) / log(2)))
	var current_in = fft_ht_texture
	var current_out = fft_ping_texture
	
	# Row Passes
	for stage in range(log2res):
		var set_idx = 0 if current_in == fft_ht_texture else (1 if current_out == fft_pong_texture else 2)
		_dispatch_butterfly(current_in, current_out, stage, 0, set_idx) # 0 = Horizontal
		current_in = current_out
		current_out = fft_pong_texture if current_in == fft_ping_texture else fft_ping_texture
		
	# Column Passes
	for stage in range(log2res):
		var set_idx = 0 if current_in == fft_ht_texture else (1 if current_out == fft_pong_texture else 2)
		_dispatch_butterfly(current_in, current_out, stage, 1, set_idx) # 1 = Vertical
		current_in = current_out
		current_out = fft_pong_texture if current_in == fft_ping_texture else fft_ping_texture
		
	var u_set_disp = fft_displace_sets[0] if current_in == fft_ping_texture else fft_displace_sets[1]
	if not u_set_disp.is_valid(): return
	
	pc = StreamPeerBuffer.new()
	pc.put_32(grid_res); pc.put_float(max(sea_size.x, sea_size.y))
	pc.put_float(0.0); pc.put_float(0.0) # Padding to 16 bytes
	
	if not fft_displace_pipeline.is_valid(): return
	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, fft_displace_pipeline)
	rd.compute_list_bind_uniform_set(cl, u_set_disp, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()

func _dispatch_butterfly(_tex_in: RID, _tex_out: RID, stage: int, direction: int, set_idx: int):
	var u_set = fft_butterfly_sets[set_idx]
	
	var pc = StreamPeerBuffer.new()
	pc.put_32(stage); pc.put_32(direction)
	pc.put_float(0.0); pc.put_float(0.0) # Padding to 16 bytes
	
	if not fft_butterfly_pipeline.is_valid(): return
	var cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, fft_butterfly_pipeline)
	rd.compute_list_bind_uniform_set(cl, u_set, 0)
	rd.compute_list_set_push_constant(cl, pc.data_array, pc.data_array.size())
	rd.compute_list_dispatch(cl, int(grid_res / 8.0), int(grid_res / 8.0), 1)
	rd.compute_list_end()


func _reset_swe_texture():
	if not rd or not sim_image: return
	if not sim_texture_A.is_valid() or not sim_texture_B.is_valid(): return # Guard
	
	for y in range(grid_res):
		for x in range(grid_res):
			var col = sim_image.get_pixel(x, y)
			col.r = 0.0 # Height clear
			col.g = 0.0 # Velocity clear
			# col.b keep (obstacles)
			sim_image.set_pixel(x, y, col)
	rd.texture_update(sim_texture_A, 0, sim_image.get_data())
	rd.texture_update(sim_texture_B, 0, sim_image.get_data())
	visual_texture.update(sim_image)

func _cleanup():
	if rd:
		if has_submitted:
			# rd.sync() is not allowed on main device
			pass
		
		# 1. Free Uniform Sets (Dependencies First)
		if uniform_set_A.is_valid(): rd.free_rid(uniform_set_A)
		if uniform_set_B.is_valid(): rd.free_rid(uniform_set_B)
		if fft_init_set.is_valid(): rd.free_rid(fft_init_set)
		if fft_update_set.is_valid(): rd.free_rid(fft_update_set)
		
		for s in fft_butterfly_sets:
			if s.is_valid(): rd.free_rid(s)
		fft_butterfly_sets.clear()
		
		for s in fft_displace_sets:
			if s.is_valid(): rd.free_rid(s)
		fft_displace_sets.clear()
		
		for s in vortex_sets:
			if s.is_valid(): rd.free_rid(s)
		vortex_sets.clear()
		
		for s in waterspout_sets:
			if s.is_valid(): rd.free_rid(s)
		waterspout_sets.clear()
		

		# 2. Free Pipelines
		if pipeline_rid.is_valid(): rd.free_rid(pipeline_rid)
		if vortex_pipeline_rid.is_valid(): rd.free_rid(vortex_pipeline_rid)
		if waterspout_pipeline_rid.is_valid(): rd.free_rid(waterspout_pipeline_rid)
		if fft_init_pipeline.is_valid(): rd.free_rid(fft_init_pipeline)
		if fft_update_pipeline.is_valid(): rd.free_rid(fft_update_pipeline)
		if fft_butterfly_pipeline.is_valid(): rd.free_rid(fft_butterfly_pipeline)
		if fft_displace_pipeline.is_valid(): rd.free_rid(fft_displace_pipeline)

		
		# 3. Free Shaders
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		if vortex_shader_rid.is_valid(): rd.free_rid(vortex_shader_rid)
		if waterspout_shader_rid.is_valid(): rd.free_rid(waterspout_shader_rid)
		if fft_init_shader.is_valid(): rd.free_rid(fft_init_shader)
		if fft_update_shader.is_valid(): rd.free_rid(fft_update_shader)
		if fft_butterfly_shader.is_valid(): rd.free_rid(fft_butterfly_shader)
		if fft_displace_shader.is_valid(): rd.free_rid(fft_displace_shader)


		# 4. Free Textures & Buffers
		if sim_texture_A.is_valid(): rd.free_rid(sim_texture_A)
		if sim_texture_B.is_valid(): rd.free_rid(sim_texture_B)
		if weather_texture.is_valid(): rd.free_rid(weather_texture)
		if fft_h0_texture.is_valid(): rd.free_rid(fft_h0_texture)
		if fft_ht_texture.is_valid(): rd.free_rid(fft_ht_texture)
		if fft_ping_texture.is_valid(): rd.free_rid(fft_ping_texture)
		if fft_pong_texture.is_valid(): rd.free_rid(fft_pong_texture)
		if fft_displace_texture.is_valid(): rd.free_rid(fft_displace_texture)

		
		if vortex_params_buffer.is_valid(): rd.free_rid(vortex_params_buffer)
		if waterspout_params_buffer.is_valid(): rd.free_rid(waterspout_params_buffer)
		if interaction_buffer.is_valid(): rd.free_rid(interaction_buffer)
		
		# Do NOT free rd itself as it's the main device now
		rd = null
	
	has_submitted = false
	current_sim_idx = 0
	
	# Reset RIDs
	uniform_set_A = RID(); uniform_set_B = RID(); pipeline_rid = RID(); shader_rid = RID()
	vortex_shader_rid = RID(); vortex_pipeline_rid = RID()
	waterspout_shader_rid = RID(); waterspout_pipeline_rid = RID()
	fft_init_shader = RID(); fft_init_pipeline = RID()
	fft_update_shader = RID(); fft_update_pipeline = RID()
	fft_butterfly_shader = RID(); fft_butterfly_pipeline = RID()
	fft_displace_shader = RID(); fft_displace_pipeline = RID()

	
	sim_texture_A = RID(); sim_texture_B = RID(); weather_texture = RID()
	fft_h0_texture = RID(); fft_ht_texture = RID()
	fft_ping_texture = RID(); fft_pong_texture = RID(); fft_displace_texture = RID()

	
	vortex_params_buffer = RID(); waterspout_params_buffer = RID()
	interaction_buffer = RID()
	fft_init_set = RID(); fft_update_set = RID()

func _notification(what):
	if what == NOTIFICATION_PREDELETE: _cleanup()
