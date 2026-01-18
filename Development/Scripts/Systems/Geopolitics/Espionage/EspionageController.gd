class_name EspionageController
extends Node

## 間諜與滲透 (MVP)

signal false_info_injected(action: EspionageAction, message: MessageData)

@export var tick_interval: float = 5.0

var _queue: Array[EspionageAction] = []
var _accumulator: float = 0.0

func queue_action(action: EspionageAction) -> void:
	if action == null:
		return
	_queue.append(action)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	if _queue.is_empty():
		return
	var action = _queue.pop_front()
	if randf() > action.success_rate:
		return
	var message = MessageData.new()
	message.message_id = "espionage_%s" % action.action_type
	message.source = action.source
	message.target = action.target
	message.truth = 0.4
	message.urgency = 0.5
	message.decay = 0.02
	message.travel_time = 0.5
	message.payload = action.payload
	var queue = get_node_or_null("/root/MessageQueue")
	if queue != null:
		queue.enqueue_message(message)
	false_info_injected.emit(action, message)
