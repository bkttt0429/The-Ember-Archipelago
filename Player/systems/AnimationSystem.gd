extends RefCounted
class_name AnimationSystem

var ecs_world: Node = null
var _anim_tree: AnimationTree = null
var _initialized: bool = false

func set_world(world: Node) -> void:
	ecs_world = world
	_initialized = false

func _init_system():
	if not ecs_world: return
	
	# 1. 獲取 AnimationTree
	if ecs_world.get("animation_tree"):
		_anim_tree = ecs_world.get("animation_tree")
	
	if not _anim_tree: return
	
	# 2. 搜尋正確的 AnimationPlayer
	var anim_player = null
	if _anim_tree.has_node(_anim_tree.anim_player):
		anim_player = _anim_tree.get_node(_anim_tree.anim_player)
	
	if not anim_player:
		print("[AnimationSystem] Warning: AnimationPlayer path invalid, searching...")
		anim_player = _find_animation_player(ecs_world)
		if anim_player:
			_anim_tree.anim_player = _anim_tree.get_path_to(anim_player)
			print("[AnimationSystem] Auto-fixed path: ", _anim_tree.anim_player)

	if not anim_player:
		printerr("[AnimationSystem] Error: AnimationPlayer not found!")
		return

	# 獲取 Skeleton3D
	var skeleton = anim_player.get_parent().find_child("*Skeleton*", true, false)
	if not skeleton:
		# 嘗試找任何 Skeleton3D
		skeleton = _find_skeleton(ecs_world)
	
	if skeleton:
		print("[AnimationSystem] Target Skeleton: ", skeleton.get_path(), " (Name: ", skeleton.name, ")")
	else:
		print("[AnimationSystem] Warning: No Skeleton3D found!")

	# 3. 加載動畫庫 (散檔匯入)
	_load_animation_library(anim_player, skeleton)

	# 4. 構建狀態機 (如果尚未設置)
	if not _anim_tree.tree_root:
		_setup_animation_tree(anim_player)
	
	# 5. 啟動
	_anim_tree.active = true
	var playback = _anim_tree.get("parameters/playback")
	if playback and playback.get_current_node() == "":
		playback.start("Idle")
	
	_initialized = true

func _setup_animation_tree(anim_player: AnimationPlayer):
	print("[AnimationSystem] Building AnimationTree StateMachine...")
	var state_machine = AnimationNodeStateMachine.new()
	_anim_tree.tree_root = state_machine
	var animations = anim_player.get_animation_list()
	print("[AnimationSystem] Available Animations: ", animations)

	# 1. 建立 Idle
	var idle_node = AnimationNodeAnimation.new()
	for a in animations:
		if "idle" in a.to_lower():
			idle_node.animation = a
			break
	if idle_node.animation == "":
		for a in animations:
			if "pc_mx" in a:
				idle_node.animation = a
				break
	
	if idle_node.animation != "":
		state_machine.add_node("Idle", idle_node)

	# 2. 建立 Locomotion (BlendSpace2D)
	var locomotion_bs = AnimationNodeBlendSpace2D.new()
	locomotion_bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_DISCRETE
	_add_blend_points(locomotion_bs, animations)
	state_machine.add_node("Locomotion", locomotion_bs)
	
	# 3. 過渡設置
	var trans_idle_to_loco = AnimationNodeStateMachineTransition.new()
	trans_idle_to_loco.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_idle_to_loco.advance_condition = "is_moving"
	state_machine.add_transition("Idle", "Locomotion", trans_idle_to_loco)
	
	var trans_loco_to_idle = AnimationNodeStateMachineTransition.new()
	trans_loco_to_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_loco_to_idle.advance_condition = "not_moving"
	state_machine.add_transition("Locomotion", "Idle", trans_loco_to_idle)

	state_machine.set_graph_offset(Vector2(100, 100))

func _load_animation_library(player: AnimationPlayer, skeleton: Skeleton3D):
	var base_path = "res://Player/assets/characters/player/motion/mx/stride8/"
	var subfolders = ["walk", "run"]
	
	if not player.has_animation_library(""):
		player.add_animation_library("", AnimationLibrary.new())
	
	var lib = player.get_animation_library("")
	
	for folder in subfolders:
		var full_path = base_path + folder + "/"
		var dir = DirAccess.open(full_path)
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".fbx") and not file_name.ends_with(".import"):
					var anim_name = file_name.get_basename()
					if not lib.has_animation(anim_name):
						var scene = load(full_path + file_name)
						if scene:
							var inst = scene.instantiate()
							var sub_player = _find_animation_player(inst)
							if sub_player:
								var anim_list = sub_player.get_animation_list()
								if anim_list.size() > 0:
									# 【關鍵】複製動畫資源以進行修改
									var anim = sub_player.get_animation(anim_list[0]).duplicate()
									_fix_animation_tracks(anim, skeleton)
									lib.add_animation(anim_name, anim)
									# print("[AnimationSystem] Loaded: ", anim_name)
							inst.queue_free()
				file_name = dir.get_next()

func _fix_animation_tracks(anim: Animation, skeleton: Skeleton3D):
	if not skeleton: return
	
	var bone_names = []
	for i in range(skeleton.get_bone_count()):
		bone_names.append(skeleton.get_bone_name(i))
	
	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		if ":" in path_str:
			var parts = path_str.split(":")
			var node_name = parts[0]
			var bone_name = parts[1]
			
			var target_node_name = skeleton.name # 強制使用目前 Skeleton 節點名稱
			var target_bone_name = bone_name
			var found_bone = false
			
			# 優先檢查原始名稱
			if bone_name in bone_names:
				found_bone = true
			else:
				# 嘗試修復名稱 (Mixamo 變體)
				var variants = [
					bone_name.replace("mixamorig1_", "mixamorig_"),
					bone_name.replace("mixamorig_", "mixamorig1_"),
					bone_name.replace("mixamorig1:", "mixamorig:"),
					bone_name.replace("mixamorig:", "mixamorig1:"),
					bone_name.split("_")[-1], # 最後一段名稱 (如 Hips)
					bone_name.split(":")[-1] # 最後一段名稱
				]
				
				for v in variants:
					if v in bone_names:
						target_bone_name = v
						found_bone = true
						break
				
				# 如果還是沒找到，嘗試模糊匹配
				if not found_bone:
					for bn in bone_names:
						if bone_name in bn or bn in bone_name:
							target_bone_name = bn
							found_bone = true
							break
			
			# 執行更新
			if found_bone:
				var new_path = target_node_name + ":" + target_bone_name
				if path_str != new_path:
					anim.track_set_path(i, NodePath(new_path))

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found: return found
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found: return found
	return null

func _add_blend_points(bs: AnimationNodeBlendSpace2D, anims: Array):
	var dirs = {
		"f": Vector2(0, 1), "b": Vector2(0, -1), "l": Vector2(-1, 0), "r": Vector2(1, 0),
		"fl": Vector2(-1, 1), "fr": Vector2(1, 1), "bl": Vector2(-1, -1), "br": Vector2(1, -1)
	}
	
	for dir_key in dirs.keys():
		var walk_target = "pc_mx_stride8_" + dir_key + "_walk"
		for a in anims:
			if walk_target in a:
				var node = AnimationNodeAnimation.new()
				node.animation = a
				bs.add_blend_point(node, dirs[dir_key])
				break

func update(_delta: float) -> void:
	if not _initialized:
		_init_system()
	
	if not ecs_world or not _anim_tree or not _initialized:
		return
	
	var entities = ecs_world.get_entities_with(["MovementState", "AnimationComponent", "PhysicsComponent"])
	for entity_id in entities:
		var movement = ecs_world.get_component(entity_id, "MovementState")
		var anim_comp = ecs_world.get_component(entity_id, "AnimationComponent")
		var physics = ecs_world.get_component(entity_id, "PhysicsComponent")
		
		if not movement or not anim_comp: continue
		
		_anim_tree.set("parameters/Locomotion/blend_position", movement.move_vector)
		
		var is_moving = movement.speed > 0.1
		_anim_tree.set("parameters/conditions/is_moving", is_moving)
		_anim_tree.set("parameters/conditions/not_moving", not is_moving)
		_anim_tree.set("parameters/conditions/is_airborne", not physics.is_grounded)
		
		var is_combat = anim_comp.get("is_combat")
		_anim_tree.set("parameters/conditions/is_combat", is_combat == true)
		
		_anim_tree.set("parameters/Locomotion/speed_scale", movement.speed / 5.0)
