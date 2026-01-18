class_name MessageQueue
extends Node

## 情報傳播與噪聲 (MVP)

signal message_delivered(message: MessageData)

@export var tick_interval: float = 1.0

var _queue: Array[MessageData] = []
var _accumulator: float = 0.0

func enqueue_message(message: MessageData) -> void:
	if message == null:
		return
	_queue.append(message)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	var delivered: Array[MessageData] = []
	for message in _queue:
		message.travel_time -= tick_interval
		message.truth = max(0.0, message.truth - message.decay * tick_interval)
		if message.travel_time <= 0.0:
			delivered.append(message)
	
	for message in delivered:
		_queue.erase(message)
		_apply_delivery(message)
		emit_signal("message_delivered", message)

func _apply_delivery(message: MessageData) -> void:
	var world_graph = get_node_or_null("/root/WorldGraph")
	if world_graph != null and message.payload.has("relation_delta"):
		var faction_a = message.payload.get("faction_a")
		var faction_b = message.payload.get("faction_b")
		if faction_a != null and faction_b != null:
			world_graph.modify_relation(faction_a, faction_b, message.payload["relation_delta"])
	
	var global_blackboard = get_node_or_null("/root/GlobalBlackboard")
	if global_blackboard != null and message.payload.has("tension_delta"):
		global_blackboard.adjust_tension(message.payload["tension_delta"])
