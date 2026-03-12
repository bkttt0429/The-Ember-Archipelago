extends Node3D

## Motion Matching 測試用第三人稱攝影機
## 滑鼠控制旋轉，跟隨 MMCharacter

@export var sensitivity := 0.3
@export var follow_height := 1.8
@export var camera_distance := 4.0
@export var pitch_min := -30.0
@export var pitch_max := 45.0

var _character: Node # MMCharacter

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 自動尋找 MMCharacter
	var scene_root = get_tree().current_scene
	if scene_root:
		for child in scene_root.get_children():
			if child.get_class() == "MMCharacter":
				_character = child
				break
	print("[CAM] character = ", _character, " (", _character.get_class() if _character else "null", ")")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_event: InputEventMouseMotion = event
		var rot := mouse_event.relative * sensitivity * -1
		var current_rot := rotation_degrees
		current_rot.x += rot.y
		current_rot.x = clampf(current_rot.x, pitch_min, pitch_max)
		current_rot.y += rot.x
		rotation_degrees = current_rot

func _process(_delta: float) -> void:
	if !_character:
		return
	# 跟隨角色位置
	global_position = _character.global_position + Vector3(0, follow_height, 0)
	# 設定 strafe 面向方向 = 攝影機 Y 旋轉
	_character.set("strafe_facing", rotation.y)
