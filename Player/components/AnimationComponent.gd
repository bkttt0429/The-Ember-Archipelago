extends RefCounted
class_name AnimationComponent

var anim_state: String = ""
var pose: String = ""
var is_combat: bool = false
var ik_targets: Dictionary = {}
var was_grounded: bool = true # 用於跳躍動畫狀態追蹤
