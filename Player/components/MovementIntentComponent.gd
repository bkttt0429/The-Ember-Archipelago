extends RefCounted
class_name MovementIntentComponent

var move_vector: Vector3 = Vector3.ZERO
var desired_speed: float = 0.0
var mode: String = "walk"
var wants_sprint: bool = false
var wants_crouch: bool = false
var wants_jump: bool = false
var wants_slide: bool = false
var wants_interact: bool = false
