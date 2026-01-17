class_name ActiveWeatherState
extends RefCounted

var wind_strength: float = 1.0
var wind_direction: Vector2 = Vector2(1, 0)
var wave_steepness: float = 0.25
var sky_color: Color = Color(0.3, 0.5, 0.8)
var fog_density: float = 0.001
var rain_intensity: float = 0.0

func lerp_to(target: WeatherState, factor: float):
	if "wind_strength" in target:
		wind_strength = lerp(wind_strength, target.wind_strength, factor)
	if "wind_direction" in target:
		wind_direction = wind_direction.lerp(target.wind_direction, factor)
	if "wave_steepness" in target:
		wave_steepness = lerp(wave_steepness, target.wave_steepness, factor)
	if "sky_color" in target:
		sky_color = sky_color.lerp(target.sky_color, factor)
	if "fog_density" in target:
		fog_density = lerp(fog_density, target.fog_density, factor)
	if "rain_intensity" in target:
		rain_intensity = lerp(rain_intensity, target.rain_intensity, factor)

func set_from(state: WeatherState):
	if "wind_strength" in state:
		wind_strength = state.wind_strength
	if "wind_direction" in state:
		wind_direction = state.wind_direction
	if "wave_steepness" in state:
		wave_steepness = state.wave_steepness
	if "sky_color" in state:
		sky_color = state.sky_color
	if "fog_density" in state:
		fog_density = state.fog_density
	if "rain_intensity" in state:
		rain_intensity = state.rain_intensity

func duplicate() -> ActiveWeatherState:
	var new_state = ActiveWeatherState.new()
	new_state.wind_strength = wind_strength
	new_state.wind_direction = wind_direction
	new_state.wave_steepness = wave_steepness
	new_state.sky_color = sky_color
	new_state.fog_density = fog_density
	new_state.rain_intensity = rain_intensity
	return new_state
