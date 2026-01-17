@tool
class_name WeatherController
extends Node

@export var water_manager: OceanWaterManager
@export var sun_light: DirectionalLight3D
@export var world_env: WorldEnvironment

@export_group("Weather Profiles")
@export var default_weather: Resource # WeatherState
@export var storm_weather: Resource # WeatherState

@export_group("Configuration")
@export var vfx_config: WeatherConfig
@export var use_state_machine: bool = false

signal weather_changed(from_state: WeatherState, to_state: WeatherState, duration: float)
signal weather_transition_completed(state: WeatherState)
signal storm_triggered(lightning: bool, tornado: bool)

@export_group("Time of Day")
@export_range(0, 1) var current_time_of_day: float = 0.3: # 0.0 to 1.0
	set(v):
		current_time_of_day = fmod(v, 1.0)
		_update_lighting()
@export var time_speed: float = 0.01

# Active (Interpolated) State
var active_wind_strength: float = 1.0
var active_wind_direction: Vector2 = Vector2(1, 0)
var active_wave_steepness: float = 0.25
var active_sky_color: Color = Color(0.3, 0.5, 0.8)
var active_fog_density: float = 0.001
var active_rain_intensity: float = 0.0

var _active_state: ActiveWeatherState = ActiveWeatherState.new()

var _current_state: Resource # WeatherState
var _tween: Tween

var _rain_controller: RainController
var _lightning_system: LightningSystem
var _tornado_controller: TornadoController
var _lightning_timer: float = 0.0
var _tornado_timer: float = 0.0

var _cached_env: Environment
var _cached_sky: ProceduralSkyMaterial

var _cached_wind_strength: float = -1.0
var _cached_wind_direction: Vector2 = Vector2(1e6, 1e6)
var _cached_wave_steepness: float = -1.0
var _cached_fog_density: float = -1.0
var _cached_rain_intensity: float = -1.0

func manual_lightning():
	if _lightning_system:
		_lightning_system.trigger_flash()

func manual_tornado(duration: float = 20.0):
	if _tornado_controller:
		var radius := vfx_config.tornado_manual_spawn_radius if vfx_config else 15.0
		var rand_pos = Vector3(randf_range(-radius, radius), 0, randf_range(-radius, radius))
		_tornado_controller.start_tornado(rand_pos, duration)

func _ready():
	_rain_controller = find_child("RainController")
	_lightning_system = find_child("LightningSystem")
	_tornado_controller = find_child("TornadoController")

	if world_env and world_env.environment:
		_cached_env = world_env.environment
		_cached_sky = _cached_env.sky.sky_material if _cached_env.sky else null

	# Initialize active state from default values
	_active_state.wind_strength = active_wind_strength
	_active_state.wind_direction = active_wind_direction
	_active_state.wave_steepness = active_wave_steepness
	_active_state.sky_color = active_sky_color
	_active_state.fog_density = active_fog_density
	_active_state.rain_intensity = active_rain_intensity

	if default_weather:
		apply_weather(default_weather, 0.0)
	_update_lighting()

func _process(delta):
	if not Engine.is_editor_hint():
		current_time_of_day = fmod(current_time_of_day + time_speed * delta, 1.0)
	
	# Constant updates for systems that need interpolated values
	_apply_active_state_to_systems()
	
	if not Engine.is_editor_hint():
		_handle_weather_vfx(delta)

func apply_weather(state: Resource, duration: float = 5.0):
	if not state: return
	var old_state = _current_state
	_current_state = state

	if _tween:
		_tween.kill()

	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Tween all relevant properties
	if "wind_strength" in state:
		_tween.tween_property(self, "active_wind_strength", state.wind_strength, duration)
	if "wind_direction" in state:
		_tween.tween_property(self, "active_wind_direction", state.wind_direction, duration)
	if "wave_steepness" in state:
		_tween.tween_property(self, "active_wave_steepness", state.wave_steepness, duration)
	if "sky_color" in state:
		_tween.tween_property(self, "active_sky_color", state.sky_color, duration)
	if "fog_density" in state:
		_tween.tween_property(self, "active_fog_density", state.fog_density, duration)
	if "rain_intensity" in state:
		_tween.tween_property(self, "active_rain_intensity", state.rain_intensity, duration)

	weather_changed.emit(old_state, state, duration)

	var lightning_min := vfx_config.lightning_min_interval if vfx_config else 3.0
	var lightning_max := vfx_config.lightning_max_interval if vfx_config else 12.0
	_lightning_timer = randf_range(lightning_min, lightning_max)

	var tornado_min := vfx_config.tornado_min_interval if vfx_config else 10.0
	var tornado_max := vfx_config.tornado_max_interval if vfx_config else 30.0
	_tornado_timer = randf_range(tornado_min, tornado_max)
	
	# Stop ongoing tornado if clearing weather
	if not state.storm_mode and _tornado_controller:
		_tornado_controller.stop_tornado()

	print("[WeatherController] Transitioning to weather: ", state.name, " over ", duration, " seconds")

	# Emit completion signal when transition finishes
	_tween.tween_callback(func(): weather_transition_completed.emit(state))

func _handle_weather_vfx(delta: float):
	# 1. Lightning
	if _lightning_system and _current_state and "storm_mode" in _current_state and _current_state.storm_mode:
		_lightning_timer -= delta
		if _lightning_timer <= 0:
			if randf() < active_rain_intensity:
				_lightning_system.trigger_flash()
				storm_triggered.emit(true, false)
			var lightning_min := vfx_config.lightning_min_interval if vfx_config else 3.0
			var lightning_max := vfx_config.lightning_max_interval if vfx_config else 12.0
			_lightning_timer = randf_range(lightning_min, lightning_max)
	
	# 2. Tornado
	if _tornado_controller and _current_state and "storm_mode" in _current_state and _current_state.storm_mode:
		_tornado_timer -= delta
		if _tornado_timer <= 0:
			# Only spawn if no active tornado
			if not _tornado_controller.is_active():
				# Random position within water bounds (demo: near center)
				var radius_x := vfx_config.tornado_spawn_radius_x if vfx_config else -10.0
				var radius_z := vfx_config.tornado_spawn_radius_z if vfx_config else 10.0
				var rand_pos = Vector3(randf_range(radius_x, -radius_x), 0, randf_range(radius_x, radius_z))
				var duration_min := vfx_config.tornado_min_duration if vfx_config else 15.0
				var duration_max := vfx_config.tornado_max_duration if vfx_config else 40.0
				_tornado_controller.start_tornado(rand_pos, randf_range(duration_min, duration_max))
				storm_triggered.emit(false, true)
			var tornado_min := vfx_config.tornado_min_interval if vfx_config else 20.0
			var tornado_max := vfx_config.tornado_max_interval if vfx_config else 60.0
			_tornado_timer = randf_range(tornado_min, tornado_max)

func _apply_active_state_to_systems():
	# Sync active_* variables to _active_state
	if _active_state:
		_active_state.wind_strength = active_wind_strength
		_active_state.wind_direction = active_wind_direction
		_active_state.wave_steepness = active_wave_steepness
		_active_state.sky_color = active_sky_color
		_active_state.fog_density = active_fog_density
		_active_state.rain_intensity = active_rain_intensity

	# Update Global Wind (only if changed)
	if _cached_wind_strength != active_wind_strength or _cached_wind_direction != active_wind_direction:
		_cached_wind_strength = active_wind_strength
		_cached_wind_direction = active_wind_direction
		if Engine.has_singleton("GlobalWind"):
			var global_wind = Engine.get_singleton("GlobalWind")
			global_wind.current_wind_strength = active_wind_strength
			global_wind.current_wind_direction = active_wind_direction
		elif has_node("/root/GlobalWind"):
			var global_wind = get_node("/root/GlobalWind")
			global_wind.current_wind_strength = active_wind_strength
			global_wind.current_wind_direction = active_wind_direction

	# Update Water Manager (only if changed)
	if water_manager:
		if water_manager.wind_strength != active_wind_strength or water_manager.wind_direction != active_wind_direction:
			water_manager.wind_strength = active_wind_strength
			water_manager.wind_direction = active_wind_direction
		if _cached_wave_steepness != active_wave_steepness:
			_cached_wave_steepness = active_wave_steepness
			water_manager.wave_steepness = active_wave_steepness
		if "rain_intensity" in water_manager and _cached_rain_intensity != active_rain_intensity:
			water_manager.rain_intensity = active_rain_intensity

	# Update Rain Controller (only if changed)
	if _rain_controller and _cached_rain_intensity != active_rain_intensity:
		_cached_rain_intensity = active_rain_intensity
		_rain_controller.set_intensity(active_rain_intensity)

	# Environmental updates (only if changed)
	if _cached_env and _cached_fog_density != active_fog_density:
		_cached_fog_density = active_fog_density
		_cached_env.volumetric_fog_density = active_fog_density

func _update_lighting():
	if not sun_light: return
	
	# Mapping: 0.5 (Noon), 0.0/1.0 (Midnight)
	var rot = (current_time_of_day * 360.0) + 90.0
	sun_light.rotation_degrees.x = rot
	
	var time_centered = (current_time_of_day - 0.5) * PI * 2.0
	var day_factor = cos(time_centered)
	
	# 1. Sun Intensity (modulated by rain/clouds)
	var weather_intensity_mult = clamp(1.0 - active_rain_intensity * 0.5, 0.2, 1.0)
	sun_light.light_energy = max(0.0, day_factor * 1.5) * weather_intensity_mult
	
	# 2. Sky & Environment Colors
	if _cached_env:
		var env = _cached_env
		var sky = _cached_sky

		var transition = clamp(day_factor + 0.2, 0.0, 1.0)
		
		# Night Colors
		var night_sky_top = Color(0.01, 0.01, 0.03)
		var night_sky_horizon = Color(0.02, 0.02, 0.05)
		var night_ambient = Color(0.01, 0.01, 0.02)
		
		# Day Colors (Modified by weather sky color)
		var day_sky_top = active_sky_color
		var day_sky_horizon = active_sky_color.lerp(Color(0.8, 0.9, 1.0), 0.5) # horizon is usually brighter
		var day_ambient = active_sky_color * 0.3
		
		# Sunset/Sunrise Tint
		if day_factor > -0.2 and day_factor < 0.3:
			var sunset_factor = clamp(1.0 - abs(day_factor * 3.0), 0.0, 1.0)
			day_sky_horizon = day_sky_horizon.lerp(Color(1.0, 0.4, 0.2), sunset_factor * weather_intensity_mult)
		
		# Apply Transitions
		if sky is ProceduralSkyMaterial:
			sky.sky_top_color = night_sky_top.lerp(day_sky_top, transition)
			sky.sky_horizon_color = night_sky_horizon.lerp(day_sky_horizon, transition)
			sky.ground_horizon_color = sky.sky_horizon_color
			sky.ground_bottom_color = night_sky_top
			
		env.ambient_light_color = night_ambient.lerp(day_ambient, transition)
		env.ambient_light_sky_contribution = clamp(day_factor, 0.0, 1.0)
		
		# Volumetric Fog
		if env.volumetric_fog_enabled:
			env.volumetric_fog_albedo = day_sky_horizon.lerp(night_sky_horizon, 1.0 - transition)
			env.volumetric_fog_density = active_fog_density # Use active fog density

	# 3. Sun Color
	if day_factor > 0:
		var sunset_lerp = clamp(1.0 - day_factor, 0.0, 1.0)
		var base_sun_color = Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.4, 0.1), sunset_lerp * 0.8)
		# Stormy sun is dimmer and more gray
		sun_light.light_color = base_sun_color.lerp(Color(0.6, 0.7, 0.8), active_rain_intensity * 0.5)

func get_current_state() -> WeatherState:
	return _current_state as WeatherState

func get_active_state() -> ActiveWeatherState:
	return _active_state

func is_transitioning() -> bool:
	return _tween and _tween.is_valid()

func get_weather_progress() -> float:
	if not _tween: return 1.0
	return 1.0 - _tween.get_total_elapsed_time() / _tween.get_total_duration()
