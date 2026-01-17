@tool
class_name WeatherStateMachine
extends Node

signal state_changed(old_state: WeatherState, new_state: WeatherState)

var _states: Dictionary = {}
var _current_state_key: String = ""
var _transitions: Dictionary = {}

func register_state(key: String, state: WeatherState):
	_states[key] = state

func add_transition(from: String, to: String, condition: Callable):
	if not _transitions.has(from):
		_transitions[from] = []
	_transitions[from].append({"to": to, "condition": condition})

func transition_to(key: String, duration: float = 5.0):
	if not _states.has(key):
		push_error("[WeatherStateMachine] State not found: ", key)
		return

	var old_state = get_current_state()
	_current_state_key = key
	state_changed.emit(old_state, _states[key])

func get_current_state() -> WeatherState:
	if _current_state_key.is_empty() or not _states.has(_current_state_key):
		return null
	return _states[_current_state_key]

func can_transition_to(key: String) -> bool:
	if not _transitions.has(_current_state_key):
		return false

	for transition in _transitions[_current_state_key]:
		if transition["to"] == key:
			return transition["condition"].call()
	return false

func check_transitions(delta: float = 0.0):
	if not _transitions.has(_current_state_key):
		return

	for transition in _transitions[_current_state_key]:
		if transition["condition"].call(delta):
			transition_to(transition["to"])
			return
