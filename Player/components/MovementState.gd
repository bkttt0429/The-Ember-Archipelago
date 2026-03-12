extends RefCounted
class_name MovementState

var mode: String = "idle"
var speed: float = 0.0
var move_vector: Vector2 = Vector2.ZERO
var move_amount: float = 0.0 # 量化移動量 (0=靜止, 0.5=走路, 1=跑步)
var is_climbing: bool = false
var is_swimming: bool = false
