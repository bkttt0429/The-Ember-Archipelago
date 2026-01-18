class_name MessageData
extends Resource

## 情報消息資料結構

@export var message_id: String = ""
@export var source: String = ""
@export var target: String = ""
@export var truth: float = 1.0
@export var urgency: float = 0.5
@export var decay: float = 0.01
@export var travel_time: float = 5.0
@export var payload: Dictionary = {}
