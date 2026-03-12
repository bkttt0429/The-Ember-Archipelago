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

var _age: float = 0.0
var _current_pos: Vector2
var _water_manager # Removed type hint to avoid cyclic dependency with WaterManager

# 波浪狀態機
enum WaveState {BUILDING, CURLING, BREAKING, DISSIPATING}
var _state: WaveState = WaveState.BUILDING

func _ready():
    _water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers")
    if not _water_manager:
        _water_manager = get_node_or_null("/root/MainScene/OceanWaterManager")
        
    _current_pos = Vector2(global_position.x, global_position.z)

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
    global_position = Vector3(_current_pos.x, global_position.y, _current_pos.y)
    
    # 向 WaterManager 注入波浪數據
    _inject_wave_data()
    
    # 生成泡沫粒子
    if _state == WaveState.BREAKING:
        _spawn_foam_particles(delta)
    
    # 清理
    if _age > lifespan:
        queue_free()

func _inject_wave_data():
    # 將波浪參數傳遞給 Shader
    var shader_data = {
        "position": _current_pos,
        "height": wave_height * _get_state_multiplier(),
        "width": wave_width,
        "curl": curl_strength * _get_curl_factor(),
        "break_point": break_point,
        "state": _state
    }
    if _water_manager.has_method("set_breaking_wave_data"):
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
    
    for i in range(spawn_count):
        var offset = Vector2(randf_range(-wave_width * 0.5, wave_width * 0.5), 0)
        var spawn_pos = _current_pos + offset
        
        # 調用泡沫系統
        if _water_manager.has_method("spawn_foam_particle"):
            _water_manager.spawn_foam_particle(
                Vector3(spawn_pos.x, wave_height * 0.8, spawn_pos.y),
                Vector3(randf_range(-2, 2), randf_range(3, 8), randf_range(-2, 2))
            )
