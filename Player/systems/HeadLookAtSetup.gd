extends Node
class_name HeadLookAtSetup

## 運行時添加 LookAtModifier3D 到骨架
## 這樣可以避免修改匯入的 FBX 場景

@export var target_distance: float = 10.0
@export var forward_axis: int = 2 # 0=X, 1=-X, 2=Y, 3=-Y, 4=Z, 5=-Z

var _skeleton: Skeleton3D
var _look_at_modifier: LookAtModifier3D
var _target_node: Node3D
var _player: CharacterBody3D

func _ready():
	await get_tree().create_timer(0.2).timeout
	_setup()

func _setup():
	_player = get_parent() as CharacterBody3D
	if not _player:
		push_error("[HeadLookAtSetup] Parent is not CharacterBody3D")
		return
	
	# 找到骨架
	_skeleton = _find_skeleton(_player)
	if not _skeleton:
		push_error("[HeadLookAtSetup] Could not find Skeleton3D")
		return
	
	# 檢查 Head 骨骼
	var head_idx = _skeleton.find_bone("Head")
	if head_idx < 0:
		push_error("[HeadLookAtSetup] Could not find Head bone")
		return
	
	# 創建目標節點
	_target_node = Node3D.new()
	_target_node.name = "LookAtTarget"
	_player.add_child(_target_node)
	_target_node.position = Vector3(0, 1.6, -target_distance)
	
	# 創建 LookAtModifier3D - 使用最小配置
	_look_at_modifier = LookAtModifier3D.new()
	_look_at_modifier.name = "HeadLookAt"
	_look_at_modifier.bone_name = "Head"
	_look_at_modifier.bone = head_idx
	
	# 只設定基本屬性，其他使用默認值
	if forward_axis >= 0 and forward_axis <= 5:
		_look_at_modifier.set("forward_axis", forward_axis)
	
	# 設定目標節點路徑
	_look_at_modifier.target_node = _look_at_modifier.get_path_to(_target_node)
	
	# 添加到骨架
	_skeleton.add_child(_look_at_modifier)
	
	print("[HeadLookAtSetup] LookAtModifier3D created! Target: %s" % _target_node.name)

func _process(_delta):
	if not _target_node or not _player:
		return
	
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	# 更新目標位置：從頭部沿相機方向延伸
	var head_pos = _player.global_position + Vector3(0, 1.6, 0)
	var camera_forward = - camera.global_transform.basis.z
	_target_node.global_position = head_pos + camera_forward * target_distance

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

func _exit_tree():
	if _look_at_modifier and is_instance_valid(_look_at_modifier):
		_look_at_modifier.queue_free()
	if _target_node and is_instance_valid(_target_node):
		_target_node.queue_free()
