extends Node
class_name WorldEventBus

signal event_emitted(event_type: String, payload: Dictionary)

func emit_event(event_type: String, payload: Dictionary) -> void:
    emit_signal("event_emitted", event_type, payload)
