class_name PersonalMemoryController
extends Node

## 個體記憶 (MVP)

signal memory_updated(entity_id: String, record: PersonalMemoryRecord)

@export var tick_interval: float = 0.1
@export var record_limit: int = 10

var _memories: Dictionary = {}
var _accumulator: float = 0.0

func add_memory(record: PersonalMemoryRecord) -> void:
	if record == null:
		return
	if not _memories.has(record.entity_id):
		_memories[record.entity_id] = []
	_memories[record.entity_id].append(record)
	if _memories[record.entity_id].size() > record_limit:
		_memories[record.entity_id].pop_front()
	memory_updated.emit(record.entity_id, record)

func _process(delta: float) -> void:
	_accumulator += delta
	if _accumulator < tick_interval:
		return
	_accumulator -= tick_interval
	_tick()

func _tick() -> void:
	for entity_id in _memories.keys():
		for record in _memories[entity_id]:
			record.grudge = max(0.0, record.grudge - record.decay)
