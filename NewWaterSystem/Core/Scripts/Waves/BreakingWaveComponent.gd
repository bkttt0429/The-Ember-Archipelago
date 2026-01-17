class_name BreakingWaveComponent
extends Node3D

## 管理單個破碎波浪的生命週期和形態

@export_group("Wave Shape")
@export var wave_height: float = 25.0
@export var wave_width: float = 50.0
@export var curl_strength: float = 1.5 # 0-1：捲曲強度
@export var break_point: float = 0.5 # 0-1：破碎點位置

@export_group("Motion")
@export var wave_speed: float = 12.0
@export var direction: Vector2 = Vector2(1, 0)
@export var lifespan: float = 15.0
@export var loop: bool = false # Debug: Loop the wave

var _age: float = 0.0
var _start_pos: Vector2
var _current_pos: Vector2
var _target_pos: Vector2 # 🔥 Smooth Movement Target
var _smooth_factor: float = 15.0
var _water_manager: OceanWaterManager

# 波浪狀態機
enum WaveState {BUILDING = 0, CURLING = 1, BREAKING = 2, DISSIPATING = 3}
var _state: WaveState = WaveState.BUILDING

func _ready():
	_current_pos = Vector2(global_position.x, global_position.z)
	_start_pos = _current_pos
	_target_pos = _current_pos # 🔥 Init Target
	
	# 1. 嘗試從群組獲取 (最穩健)
	_water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers")
	
	# 2. 如果沒有，嘗試父節點 (測試場景常用結構)
	if not _water_manager and get_parent().has_method("set_breaking_wave_data"):
		_water_manager = get_parent()
		
	# 3. 最後嘗試硬編碼路徑 (MainScene)
	if not _water_manager:
		_water_manager = get_node_or_null("/root/MainScene/OceanWaterManager")
	
	if not _water_manager:
		push_error("BreakingWaveComponent: Failed to find OceanWaterManager!")

func _physics_process(delta):
	if not _water_manager: return
	
	# 🚨 修復：可見性與距離剔除 (方案 5)
	if not is_visible_in_tree(): return
	
	var cam = get_viewport().get_camera_3d()
	if cam and global_position.distance_to(cam.global_position) > 400.0: # LOD 距離
		return
	
	_age += delta
	
	# 狀態轉換
	if _age < lifespan * 0.3:
		_state = WaveState.BUILDING
	elif _age < lifespan * 0.6:
		_state = WaveState.CURLING
	elif _age < lifespan * 0.85:
		_state = WaveState.BREAKING
	else:
		_state = WaveState.DISSIPATING
	
	# 位置更新
	# 🔥 修復：平滑位置更新（指數衰減插值）
	_target_pos += direction.normalized() * wave_speed * delta
	_current_pos = _current_pos.lerp(_target_pos, _smooth_factor * delta)
	
	# 向 WaterManager 注入波浪數據
	_inject_wave_data()
	
	# 生成泡沫粒子
	if _state == WaveState.BREAKING:
		_spawn_foam_particles(delta)
	
	# 清理 or Loop
	if _age > lifespan:
		if loop:
			_age = 0.0
			_target_pos = _start_pos
			_current_pos = _start_pos # 🔥 Reset both
			_state = WaveState.BUILDING
			# print("Wave Loop Reset")
		else:
			queue_free()

func _inject_wave_data():
	# print("Injecting Wave: Pos=", _current_pos, " State=", _state)
	# 將波浪參數傳遞給 Shader
	var shader_data = {
		"position": _current_pos,
		"height": wave_height * _get_state_multiplier(),
		"width": wave_width,
		"curl": curl_strength * _get_curl_factor(),
		"break_point": break_point,
		"state": int(_state),
		"direction": direction
	}
	_water_manager.set_breaking_wave_data(shader_data)
	
	# 🔥 Debug Print (Optional)
	# if Engine.get_frames_drawn() % 120 == 0:
	# 	print("💥 [Component] Height=%.1f | Curl=%.2f | Pos=%s" % [shader_data.height, shader_data.curl, shader_data.position])

func _get_state_multiplier() -> float:
	match _state:
		WaveState.BUILDING:
			return smoothstep(0.0, 0.3, _age / lifespan)
		WaveState.CURLING, WaveState.BREAKING:
			# 🔥 修復：防止狀態切換時的瞬間跳變
			# 如果 _age 剛好在臨界點，確保過渡到 1.0 是平滑的
			return clamp(lerp(0.0, 1.0, _age / (lifespan * 0.3)), 0.0, 1.0)
		WaveState.DISSIPATING:
			return 1.0 - smoothstep(0.8, 1.0, _age / lifespan)
	return 0.0

func _get_curl_factor() -> float:
	# Curling 狀態達到最大捲曲
	if _state == WaveState.CURLING:
		return 1.0
	elif _state == WaveState.BREAKING:
		return 0.6 # 破碎時部分保持
	return 0.3

func _spawn_foam_particles(delta: float):
	# 🔥 根據狀態調整生成率
	var foam_rate = 500.0 if _state == WaveState.BREAKING else 200.0
	
	# 🔥 Optimization: Distance check for foam details
	var cam = get_viewport().get_camera_3d()
	if cam:
		var dist = global_position.distance_to(cam.global_position)
		if dist > 150.0: return # Too far for foam
		if dist > 80.0: foam_rate *= 0.5 # Half rate for mid distance
		
	var spawn_count = int(foam_rate * delta)
	var dir_norm = direction.normalized()
	
	for i in range(spawn_count):
		var tangent = Vector2(-dir_norm.y, dir_norm.x)
		var offset_width = randf_range(-wave_width * 0.6, wave_width * 0.6) # 更寬分布
		var offset_pos = _current_pos + tangent * offset_width
		
		# 🔥 增加前方偏移（泡沫跟隨波浪前緣）
		var forward_offset = dir_norm * wave_width * 0.3 * randf()
		offset_pos += forward_offset
		
		# 🔥 更高的初始位置（模擬噴濺）
		var spawn_height = wave_height * randf_range(0.8, 1.5)
		
		_water_manager.spawn_foam_particle(
			Vector3(offset_pos.x, spawn_height + global_position.y, offset_pos.y),
			Vector3(
				randf_range(-5, 5), # 橫向擴散
				randf_range(5, 15), # 向上噴射
				randf_range(-5, 5)
			)
		)
