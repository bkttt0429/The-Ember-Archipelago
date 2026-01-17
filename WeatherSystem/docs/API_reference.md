# 天氣系統 API 快速參考

## 📅 最後更新日期：2026-01-18

本文檔提供天氣系統所有 API 的快速參考，方便開發時快速查詢。

---

## WeatherController

### 屬性

| 屬性 | 類型 | 說明 | 預設值 |
|------|------|------|--------|
| `water_manager` | `OceanWaterManager` | 海水管理器引用 | `null` |
| `sun_light` | `DirectionalLight3D` | 太陽光源引用 | `null` |
| `world_env` | `WorldEnvironment` | 全局環境引用 | `null` |
| `default_weather` | `WeatherState` | 預設天氣狀態 | `null` |
| `storm_weather` | `WeatherState` | 暴風天氣狀態 | `null` |
| `vfx_config` | `WeatherConfig` | VFX 配置 | `null` |
| `use_state_machine` | `bool` | 是否使用狀態機 | `false` |
| `time_speed` | `float` | 時間流逝速度 | `0.01` |
| `current_time_of_day` | `float` | 當前時間 (0.0-1.0) | `0.3` |

### 活動狀態屬性

| 屬性 | 類型 | 說明 | 預設值 |
|------|------|------|--------|
| `active_wind_strength` | `float` | 當前風力強度 | `1.0` |
| `active_wind_direction` | `Vector2` | 當前風向 | `Vector2(1, 0)` |
| `active_wave_steepness` | `float` | 當前浪尖銳度 | `0.25` |
| `active_sky_color` | `Color` | 當前天空顏色 | `Color(0.3, 0.5, 0.8)` |
| `active_fog_density` | `float` | 當前霧密度 | `0.001` |
| `active_rain_intensity` | `float` | 當前雨強度 (0.0-1.0) | `0.0` |

### 方法

#### apply_weather

```gdscript
func apply_weather(state: WeatherState, duration: float = 5.0) -> void
```

**說明：** 應用指定的天氣狀態，並在指定時間內平滑過渡

**參數：**
- `state` - 目標天氣狀態
- `duration` - 過渡時間（秒），預設 5.0

**示例：**
```gdscript
weather_controller.apply_weather(storm_weather, 3.0)
```

---

#### manual_lightning

```gdscript
func manual_lightning() -> void
```

**說明：** 手動觸發閃電效果

**示例：**
```gdscript
weather_controller.manual_lightning()
```

---

#### manual_tornado

```gdscript
func manual_tornado(duration: float = 20.0) -> void
```

**說明：** 手動觸發龍捲風

**參數：**
- `duration` - 龍捲風持續時間（秒），預設 20.0

**示例：**
```gdscript
weather_controller.manual_tornado(30.0)
```

---

#### get_current_state

```gdscript
func get_current_state() -> WeatherState
```

**說明：** 獲取當前目標天氣狀態

**返回值：** 當前天氣狀態，如果未設置返回 `null`

**示例：**
```gdscript
var state = weather_controller.get_current_state()
if state:
    print("當前天氣: ", state.name)
```

---

#### get_active_state

```gdscript
func get_active_state() -> ActiveWeatherState
```

**說明：** 獲取當前插值後的實際狀態

**返回值：** 當前實際狀態對象

**示例：**
```gdscript
var active = weather_controller.get_active_state()
print("當前風速: ", active.wind_strength)
print("當前雨量: ", active.rain_intensity)
```

---

#### is_transitioning

```gdscript
func is_transitioning() -> bool
```

**說明：** 檢查是否正在進行天氣過渡

**返回值：** `true` 如果正在過渡

**示例：**
```gdscript
if not weather_controller.is_transitioning():
    weather_controller.apply_weather(new_weather)
```

---

#### get_weather_progress

```gdscript
func get_weather_progress() -> float
```

**說明：** 獲取天氣過渡進度

**返回值：** 進度值 `0.0-1.0`，1.0 表示完成

**示例：**
```gdscript
var progress = weather_controller.get_weather_progress()
print("過渡進度: ", progress * 100, "%")
```

---

### 信號

#### weather_changed

```gdscript
signal weather_changed(from_state: WeatherState, to_state: WeatherState, duration: float)
```

**說明：** 天氣狀態開始變化時觸發

**參數：**
- `from_state` - 原始天氣狀態
- `to_state` - 目標天氣狀態
- `duration` - 過渡時間

**示例：**
```gdscript
weather_controller.weather_changed.connect(_on_weather_changed)

func _on_weather_changed(from: WeatherState, to: WeatherState, duration: float):
    print("天氣從 ", from.name, " 切換到 ", to.name, "，預計 ", duration, " 秒完成")
```

---

#### weather_transition_completed

```gdscript
signal weather_transition_completed(state: WeatherState)
```

**說明：** 天氣過渡完成時觸發

**參數：**
- `state` - 完成後的天氣狀態

**示例：**
```gdscript
weather_controller.weather_transition_completed.connect(_on_transition_complete)

func _on_transition_complete(state: WeatherState):
    print("天氣過渡完成: ", state.name)
    # 可以在這裡觸發相關事件或 UI 更新
```

---

#### storm_triggered

```gdscript
signal storm_triggered(lightning: bool, tornado: bool)
```

**說明：** 風暴事件觸發時發出

**參數：**
- `lightning` - 是否有閃電
- `tornado` - 是否有龍捲風

**示例：**
```gdscript
weather_controller.storm_triggered.connect(_on_storm_event)

func _on_storm_event(has_lightning: bool, has_tornado: bool):
    if has_lightning:
        print("閃電觸發！")
        # 可以在這裡播放閃電音效或震動效果
    if has_tornado:
        print("龍捲風生成！")
        # 可以在這裡顯示警告 UI
```

---

## WeatherConfig

### 屬性

| 屬性 | 類型 | 說明 | 預設值 |
|------|------|------|--------|
| `lightning_min_interval` | `float` | 閃電最小間隔（秒） | `3.0` |
| `lightning_max_interval` | `float` | 閃電最大間隔（秒） | `12.0` |
| `tornado_min_interval` | `float` | 龍捲風最小生成間隔（秒） | `20.0` |
| `tornado_max_interval` | `float` | 龍捲風最大生成間隔（秒） | `60.0` |
| `tornado_min_duration` | `float` | 龍捲風最短持續時間（秒） | `15.0` |
| `tornado_max_duration` | `float` | 龍捲風最長持續時間（秒） | `40.0` |
| `tornado_spawn_radius_x` | `float` | 龍捲風生成 X 軸半徑 | `-10.0` |
| `tornado_spawn_radius_z` | `float` | 龍捲風生成 Z 軸半徑 | `10.0` |
| `tornado_manual_spawn_radius` | `float` | 手動觸發龍捲風半徑 | `15.0` |
| `default_transition_duration` | `float` | 預設過渡時間（秒） | `5.0` |

### 使用方式

在 Godot 編輯器中創建配置實例：
```
1. 在 Resources 文件夾右鍵 → 新建資源
2. 選擇 "WeatherConfig"
3. 調整參數值
4. 將配置連接到 WeatherController 的 vfx_config 屬性
```

---

## ActiveWeatherState

### 屬性

| 屬性 | 類型 | 說明 | 預設值 |
|------|------|------|--------|
| `wind_strength` | `float` | 風力強度 | `1.0` |
| `wind_direction` | `Vector2` | 風向 | `Vector2(1, 0)` |
| `wave_steepness` | `float` | 浪尖銳度 | `0.25` |
| `sky_color` | `Color` | 天空顏色 | `Color(0.3, 0.5, 0.8)` |
| `fog_density` | `float` | 霧密度 | `0.001` |
| `rain_intensity` | `float` | 雨強度 (0.0-1.0) | `0.0` |

### 方法

#### lerp_to

```gdscript
func lerp_to(target: WeatherState, factor: float) -> void
```

**說明：** 插值到目標狀態

**參數：**
- `target` - 目標天氣狀態
- `factor` - 插值因子 (0.0-1.0)

**示例：**
```gdscript
var active = ActiveWeatherState.new()
active.lerp_to(target_state, 0.1)  # 每幀移動 10%
```

---

#### set_from

```gdscript
func set_from(state: WeatherState) -> void
```

**說明：** 從 WeatherState 複製所有屬性值

**參數：**
- `state` - 來源天氣狀態

**示例：**
```gdscript
var active = ActiveWeatherState.new()
active.set_from(weather_state)
```

---

#### duplicate

```gdscript
func duplicate() -> ActiveWeatherState
```

**說明：** 創建狀態的深層複製

**返回值：** 新的 ActiveWeatherState 實例

**示例：**
```gdscript
var copy = original_state.duplicate()
```

---

## WeatherStateMachine

### 方法

#### register_state

```gdscript
func register_state(key: String, state: WeatherState) -> void
```

**說明：** 註冊一個天氣狀態

**參數：**
- `key` - 狀態鍵名
- `state` - 天氣狀態實例

**示例：**
```gdscript
state_machine.register_state("Clear", clear_weather)
state_machine.register_state("Storm", storm_weather)
```

---

#### add_transition

```gdscript
func add_transition(from: String, to: String, condition: Callable) -> void
```

**說明：** 添加狀態轉換規則

**參數：**
- `from` - 起始狀態鍵名
- `to` - 目標狀態鍵名
- `condition` - 轉換條件函數

**示例：**
```gdscript
# 基於時間的轉換
state_machine.add_transition("Clear", "Storm", func(delta): return randf() < 0.001)
state_machine.add_transition("Storm", "Clear", func(delta): return current_time_of_day > 0.5)

# 基於條件的轉換
state_machine.add_transition("Clear", "Storm", func(delta): return player_in_danger_zone())
```

---

#### transition_to

```gdscript
func transition_to(key: String, duration: float = 5.0) -> void
```

**說明：** 執行狀態轉換

**參數：**
- `key` - 目標狀態鍵名
- `duration` - 過渡時間（秒）

**示例：**
```gdscript
state_machine.transition_to("Storm", 3.0)
```

---

#### get_current_state

```gdscript
func get_current_state() -> WeatherState
```

**說明：** 獲取當前天氣狀態

**返回值：** 當前天氣狀態，如果未設置返回 `null`

**示例：**
```gdscript
var state = state_machine.get_current_state()
```

---

#### can_transition_to

```gdscript
func can_transition_to(key: String) -> bool
```

**說明：** 檢查是否可以轉換到指定狀態

**參數：**
- `key` - 目標狀態鍵名

**返回值：** `true` 如果可以轉換

**示例：**
```gdscript
if state_machine.can_transition_to("Storm"):
    state_machine.transition_to("Storm")
```

---

#### check_transitions

```gdscript
func check_transitions(delta: float = 0.0) -> void
```

**說明：** 檢查並執行自動轉換

**參數：**
- `delta` - 幀時間（秒）

**示例：**
```gdscript
func _process(delta):
    state_machine.check_transitions(delta)
```

---

### 信號

#### state_changed

```gdscript
signal state_changed(old_state: WeatherState, new_state: WeatherState)
```

**說明：** 狀態改變時觸發

**參數：**
- `old_state` - 原始狀態
- `new_state` - 新狀態

**示例：**
```gdscript
state_machine.state_changed.connect(_on_state_changed)

func _on_state_changed(old: WeatherState, new: WeatherState):
    print("狀態從 ", old.name, " 切換到 ", new.name)
```

---

## WeatherState

### 屬性

| 屬性 | 類型 | 說明 | 預設值 |
|------|------|------|--------|
| `name` | `String` | 狀態名稱 | `"Clear"` |
| `wind_strength` | `float` | 風力強度 | `1.0` |
| `wind_direction` | `Vector2` | 風向 | `Vector2(1, 0)` |
| `wave_steepness` | `float` | 浪尖銳度 | `0.25` |
| `sky_color` | `Color` | 天空顏色 | `Color(0.3, 0.5, 0.8)` |
| `fog_density` | `float` | 霧密度 | `0.001` |
| `rain_intensity` | `float` | 雨強度 | `0.0` |
| `storm_mode` | `bool` | 是否為風暴模式 | `false` |

### 使用方式

創建天氣狀態資源：
```
1. 在 Resources 文件夾右鍵 → 新建資源
2. 選擇 "WeatherState"
3. 設置屬性值
4. 保存為 .tres 文件
```

---

## TornadoController

### 方法

#### start_tornado

```gdscript
func start_tornado(pos: Vector3, duration: float = 30.0) -> void
```

**說明：** 啟動龍捲風

**參數：**
- `pos` - 龍捲風位置
- `duration` - 持續時間（秒）

**示例：**
```gdscript
tornado_controller.start_tornado(Vector3(0, 0, 0), 20.0)
```

---

#### stop_tornado

```gdscript
func stop_tornado() -> void
```

**說明：** 停止龍捲風

**示例：**
```gdscript
tornado_controller.stop_tornado()
```

---

#### is_active

```gdscript
func is_active() -> bool
```

**說明：** 檢查龍捲風是否活躍

**返回值：** `true` 如果龍捲風正在運作

**示例：**
```gdscript
if tornado_controller.is_active():
    print("龍捲風正在運作！")
```

---

## RainController

### 方法

#### set_intensity

```gdscript
func set_intensity(val: float) -> void
```

**說明：** 設置雨量強度

**參數：**
- `val` - 雨量強度 (0.0-1.0)

**示例：**
```gdscript
rain_controller.set_intensity(0.8)  # 大雨
```

---

## LightningSystem

### 方法

#### trigger_flash

```gdscript
func trigger_flash() -> void
```

**說明：** 觸發閃電效果

**示例：**
```gdscript
lightning_system.trigger_flash()
```

---

## GlobalWind

### 屬性

| 屬性 | 類型 | 說明 | 預設值 |
|------|------|------|--------|
| `current_wind_strength` | `float` | 當前風力強度 | `1.0` |
| `current_wind_direction` | `Vector2` | 當前風向 | `Vector2(1.0, 0.0)` |

### 信號

#### wind_changed

```gdscript
signal wind_changed(new_direction: Vector2, new_strength: float)
```

**說明：** 風力改變時觸發

**參數：**
- `new_direction` - 新風向
- `new_strength` - 新風力強度

**示例：**
```gdscript
GlobalWind.wind_changed.connect(_on_wind_changed)

func _on_wind_changed(direction: Vector2, strength: float):
    print("風力改變: 方向=", direction, " 強度=", strength)
```

### 方法

#### get_wind_vector

```gdscript
func get_wind_vector() -> Vector2
```

**說明：** 獲取風向量

**返回值：** 風向量（方向 × 強度）

**示例：**
```gdscript
var wind_vector = GlobalWind.get_wind_vector()
```

---

## 使用示例

### 完整的天氣切換示例

```gdscript
extends Node3D

@onready var weather_controller = $WeatherController

func _ready():
    # 監聽天氣變化
    weather_controller.weather_changed.connect(_on_weather_changed)
    weather_controller.weather_transition_completed.connect(_on_transition_complete)
    weather_controller.storm_triggered.connect(_on_storm_event)

    # 載入天氣狀態
    var clear_weather = load("res://WeatherSystem/Resources/Clear.tres")
    var storm_weather = load("res://WeatherSystem/Resources/Storm.tres")

    # 切換到風暴天氣
    weather_controller.apply_weather(storm_weather, 5.0)

func _on_weather_changed(from: WeatherState, to: WeatherState, duration: float):
    print("天氣從 ", from.name, " 切換到 ", to.name)

func _on_transition_complete(state: WeatherState):
    print("天氣過渡完成: ", state.name)

func _on_storm_event(has_lightning: bool, has_tornado: bool):
    if has_lightning:
        play_lightning_sound()
    if has_tornado:
        show_tornado_warning()

func _process(delta):
    # 檢查當前狀態
    var active = weather_controller.get_active_state()
    if active.rain_intensity > 0.5:
        print("大雨中，注意安全！")
```

### 狀態機使用示例

```gdscript
extends Node3D

@onready var weather_controller = $WeatherController
var state_machine = WeatherStateMachine.new()

func _ready():
    # 註冊狀態
    state_machine.register_state("Clear", load("res://WeatherSystem/Resources/Clear.tres"))
    state_machine.register_state("Storm", load("res://WeatherSystem/Resources/Storm.tres"))

    # 添加轉換規則
    state_machine.add_transition("Clear", "Storm", func(delta): return randf() < 0.001)
    state_machine.add_transition("Storm", "Clear", func(delta): return weather_controller.current_time_of_day > 0.5)

    # 監聽狀態變化
    state_machine.state_changed.connect(_on_state_changed)

    # 初始狀態
    state_machine.transition_to("Clear")

func _process(delta):
    # 檢查自動轉換
    state_machine.check_transitions(delta)

func _on_state_changed(old: WeatherState, new: WeatherState):
    weather_controller.apply_weather(new, 5.0)
```

---

## 📖 更多資源

- `docs/optimization_log.md` - 詳細優化文檔
- `docs/progress_status.md` - 開發進度
- `Core/*.gd` - 原始碼文件
