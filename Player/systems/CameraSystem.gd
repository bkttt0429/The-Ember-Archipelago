extends RefCounted
class_name CameraSystem

var ecs_world: Node = null


func set_world(world: Node) -> void:
	ecs_world = world

func update(delta: float) -> void:
	if not ecs_world: return
	
	var entities = ecs_world.get_entities_with(["TransformComponent"])
	for entity_id in entities:
		# 這裡可以實作進階相機邏輯，例如 FOV 隨速度變化、相機抖動等
		# 目前基礎旋轉已由 PlayerController 的 _unhandled_input 處理以保證低延遲
		var movement = ecs_world.get_component(entity_id, "MovementState")
		var camera_mount = ecs_world.get("camera_mount") as Node3D
		if movement and camera_mount:
			# 動態 FOV 效果 (衝刺時拉廣)
			var camera = camera_mount.get_child(0) as Camera3D
			if camera:
				var target_fov = 75.0
				if movement.mode == "sprint":
					target_fov = 85.0
				elif movement.mode == "swim":
					target_fov = 70.0
				
				camera.fov = lerp(camera.fov, target_fov, 5.0 * delta)
