extends RefCounted
class_name MovementState

var mode: String = "idle"
var speed: float = 0.0
var move_vector: Vector2 = Vector2.ZERO
var is_climbing: bool = false
var is_swimming: bool = false
