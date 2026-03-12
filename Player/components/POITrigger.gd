extends Area3D
class_name POITrigger

## 興趣點觸發器 (Point of Interest Trigger)
## 當玩家進入區域時，自動註冊到 LookAtTargetManager

@export var poi_priority: int = 2 ## POI 優先級 (1-3)
@export var target_node: Node3D ## 實際要看向的節點 (如果為空則看向此 Area3D 中心)

var _registered: bool = false
var _target_manager: LookAtTargetManager

func _ready():
	# 連接信號
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D):
	if body is CharacterBody3D and body.has_method("get_instance_id"):
		# 假設玩家是 CharacterBody3D
		_target_manager = _find_look_at_manager(body)
		
		if _target_manager:
			var target = target_node if target_node else self
			_target_manager.register_poi(target, poi_priority)
			_registered = true
			print("[POITrigger] Player entered POI: %s" % name)

func _on_body_exited(body: Node3D):
	if body is CharacterBody3D and _registered and _target_manager:
		var target = target_node if target_node else self
		_target_manager.unregister_poi(target)
		_registered = false
		print("[POITrigger] Player exited POI: %s" % name)

func _find_look_at_manager(player: Node3D) -> LookAtTargetManager:
	# 在玩家節點下尋找 LookAtTargetManager
	for child in player.get_children():
		if child is LookAtTargetManager:
			return child
	return null
