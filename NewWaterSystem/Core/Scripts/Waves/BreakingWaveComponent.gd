class_name BreakingWaveComponent
extends Node3D

## 管理單個破碎波浪的生命週期和形態

@export_group("Wave Shape")
@export var wave_height: float = 8.0
@export var wave_width: float = 30.0
@export var curl_strength: float = 0.7 # 0-1：捲曲強度
@export var break_point: float = 0.6 # 0-1：破碎點位置

@export_group("Motion")
@export var wave_speed: float = 8.0
@export var direction: Vector2 = Vector2(1, 0)
@export var lifespan: float = 10.0
@export var loop: bool = false # Debug: Loop the wave

var _age: float = 0.0
var _start_pos: Vector2
var _current_pos: Vector2
var _water_manager: OceanWaterManager

# 波浪狀態機
enum WaveState {BUILDING = 0, CURLING = 1, BREAKING = 2, DISSIPATING = 3}
var _state: WaveState = WaveState.BUILDING

func _ready():
	_current_pos = Vector2(global_position.x, global_position.z)
	_start_pos = _current_pos
	
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
	_current_pos += direction.normalized() * wave_speed * delta
	
	# 向 WaterManager 注入波浪數據
	_inject_wave_data()
	
	# 生成泡沫粒子
	if _state == WaveState.BREAKING:
		_spawn_foam_particles(delta)
	
	# 清理 or Loop
	if _age > lifespan:
		if loop:
			_age = 0.0
			_current_pos = _start_pos
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

func _get_state_multiplier() -> float:
	match _state:
		WaveState.BUILDING: return smoothstep(0.0, 0.3, _age / lifespan)
		WaveState.CURLING: return 1.0
		WaveState.BREAKING: return 1.0
		WaveState.DISSIPATING: return 1.0 - smoothstep(0.85, 1.0, _age / lifespan)
	return 1.0

func _get_curl_factor() -> float:
	# Curling 狀態達到最大捲曲
	if _state == WaveState.CURLING:
		return 1.0
	elif _state == WaveState.BREAKING:
		return 0.6 # 破碎時部分保持
	return 0.3

func _spawn_foam_particles(delta: float):
	# 在波峰產生泡沫粒子
	var foam_rate = 100.0 # 每秒粒子數
	var spawn_count = int(foam_rate * delta)
	var dir_norm = direction.normalized()
	
	# 計算波峰位置 (前進方向上的偏移)
	# 波浪中心 _current_pos
	# 波峰通常即是中心，或者稍微偏前/後取決於實現
	
	for i in range(spawn_count):
		# 沿著波浪寬度分佈 (垂直於前進方向)
		# 旋轉 90 度
		var tangent = Vector2(-dir_norm.y, dir_norm.x)
		var offset_width = randf_range(-wave_width * 0.4, wave_width * 0.4)
		var offset_pos = _current_pos + tangent * offset_width
		
		# 調用泡沫系統
		# 注意：Y 軸高度需要大致在波峰高度，這裡用 wave_height * 0.8
		_water_manager.spawn_foam_particle(
			Vector3(offset_pos.x, wave_height * 0.8 + global_position.y, offset_pos.y),
			Vector3(randf_range(-2, 2), randf_range(3, 8), randf_range(-2, 2)) # 簡單的隨機速度
		)
