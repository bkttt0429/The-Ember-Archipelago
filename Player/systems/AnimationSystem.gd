extends RefCounted
class_name AnimationSystem

const UNIVERSAL_LIB_PATH := "res://Player/universal_anim_lib.tres"

var ecs_world: Node = null
var _anim_tree: AnimationTree = null
var _anim_player: AnimationPlayer = null
var _initialized: bool = false
var _current_blend_pos: Vector2 = Vector2.ZERO
var _is_moving_state: bool = false # 用於遲滯判定

func set_world(world: Node) -> void:
	ecs_world = world
	_initialized = false

func _init_system():
	if not ecs_world:
		return

	_anim_tree = _resolve_animation_tree()
	if not _anim_tree:
		print("[AnimationSystem] Warning: AnimationTree not found!")
		return

	_anim_player = _resolve_animation_player(_anim_tree)
	if not _anim_player:
		print("[AnimationSystem] Warning: AnimationPlayer not found!")
		return

	var root_node: Node = null
	if _anim_tree.root_node != NodePath("") and _anim_tree.has_node(_anim_tree.root_node):
		root_node = _anim_tree.get_node(_anim_tree.root_node)
	if not root_node:
		root_node = ecs_world

	var skeleton = _find_skeleton(root_node)
	if skeleton:
		if skeleton.is_inside_tree():
			print("[AnimationSystem] Target Skeleton: ", skeleton.get_path(), " (Name: ", skeleton.name, ")")
		else:
			print("[AnimationSystem] Target Skeleton found but not in tree yet: ", skeleton.name)
	else:
		print("[AnimationSystem] Warning: No Skeleton3D found!")
		return

	_ensure_root_node(_anim_tree, skeleton)

	# 載入動畫庫
	_load_animation_library(_anim_player, skeleton)
	
	# 檢查場景是否已有設定好的 tree_root（優先使用場景配置）
	if _anim_tree.tree_root != null:
		print("[AnimationSystem] Using existing tree_root from scene (BlendTree/StateMachine)")
		_validate_animation_tree()
	else:
		# 如果沒有 tree_root，才用代碼構建
		print("[AnimationSystem] No tree_root found, building from code...")
		_setup_animation_tree(_anim_player)
		print("[AnimationSystem] AnimationTree state machine built from code.")

	# 啟用 AnimationTree
	_anim_tree.active = true
	print("[AnimationSystem] AnimationTree ENABLED")
	
	# 測試 track 路徑解析
	print("[AnimationSystem] --- Testing Track Resolution ---")
	var root = _anim_player.get_node(_anim_player.root_node)
	print("[AnimationSystem] AnimationPlayer root resolves to: ", root.name if root else "NULL")
	
	# 嘗試從 root 找到 GeneralSkeleton
	if root and root.has_node("GeneralSkeleton"):
		var skel = root.get_node("GeneralSkeleton")
		print("[AnimationSystem] ✓ Found GeneralSkeleton from root: ", skel.get_path())
		print("[AnimationSystem] GeneralSkeleton bone count: ", skel.get_bone_count())
		# 測試骨骼 Hips
		var hips_idx = skel.find_bone("Hips")
		print("[AnimationSystem] Hips bone index: ", hips_idx, " (expected >= 0)")
	else:
		print("[AnimationSystem] ✗ Cannot find GeneralSkeleton from root!")
		if root:
			print("[AnimationSystem] Root children: ", root.get_children())
	
	# 只禁用 PhysicalBoneSimulator3D（它會完全覆蓋動畫）
	# IK 修飾器應該在動畫之後疊加，不需要禁用
	if root and root.has_node("GeneralSkeleton"):
		var skel = root.get_node("GeneralSkeleton")
		for child in skel.get_children():
			if child is PhysicalBoneSimulator3D:
				child.active = false
				print("[AnimationSystem] Disabled PhysicalBoneSimulator3D: ", child.name)

	# 啟動狀態機到 movement（BlendSpace2D 已包含 Idle 和移動動畫）
	var playback = _anim_tree.get("parameters/playback")
	if playback:
		var current = playback.get_current_node()
		if current == "" or current == "Start":
			playback.start("movement")
			print("[AnimationSystem] Started playback from movement")

	_initialized = true

	print("[AnimationSystem] ✓ Animation System initialized successfully")
	print("[AnimationSystem] AnimationTree Active: ", _anim_tree.active)

func _setup_animation_tree(anim_player: AnimationPlayer):
	print("[AnimationSystem] Building AnimationTree StateMachine...")
	var state_machine = AnimationNodeStateMachine.new()
	_anim_tree.tree_root = state_machine
	
	# 檢測動畫庫並設定前綴
	var lib_prefix = ""
	var animations: Array = []
	
	# 優先使用 'movement' 動畫庫（這是 NewPlayer.tscn 中的庫名）
	if anim_player.has_animation_library("movement"):
		var lib = anim_player.get_animation_library("movement")
		animations = Array(lib.get_animation_list())
		lib_prefix = "movement/"
		print("[AnimationSystem] Using 'movement' library")
	elif anim_player.has_animation_library("movement_animations"):
		var lib = anim_player.get_animation_library("movement_animations")
		animations = Array(lib.get_animation_list())
		lib_prefix = "movement_animations/"
		print("[AnimationSystem] Using 'movement_animations' library")
	elif anim_player.has_animation_library(""):
		var lib = anim_player.get_animation_library("")
		animations = Array(lib.get_animation_list())
		lib_prefix = ""
		print("[AnimationSystem] Using default library")
	else:
		animations = Array(anim_player.get_animation_list())
		lib_prefix = ""
		print("[AnimationSystem] Using AnimationPlayer animation list")
	
	print("[AnimationSystem] Available Animations (%d):" % animations.size())
	for a in animations:
		print("  - ", a)

	# 1. 建立 Idle
	var idle_node = AnimationNodeAnimation.new()
	if "Idle" in animations:
		idle_node.animation = lib_prefix + "Idle"
	elif "idle" in animations:
		idle_node.animation = lib_prefix + "idle"
	else:
		# Fallback logic
		for a in animations:
			if "idle" in a.to_lower():
				idle_node.animation = lib_prefix + a
				break
	
	if idle_node.animation != "":
		state_machine.add_node("Idle", idle_node)

	# 2. 建立 Locomotion (BlendSpace2D)
	var locomotion_bs = AnimationNodeBlendSpace2D.new()
	locomotion_bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	_add_blend_points(locomotion_bs, animations)
	state_machine.add_node("Locomotion", locomotion_bs)

	
	# 3. 過渡設置
	# Start -> Idle (Auto)
	var trans_start_to_idle = AnimationNodeStateMachineTransition.new()
	trans_start_to_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	state_machine.add_transition("Start", "Idle", trans_start_to_idle)
	
	var trans_idle_to_loco = AnimationNodeStateMachineTransition.new()
	trans_idle_to_loco.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_idle_to_loco.advance_condition = "is_moving"
	trans_idle_to_loco.xfade_time = 0.2
	state_machine.add_transition("Idle", "Locomotion", trans_idle_to_loco)
	
	var trans_loco_to_idle = AnimationNodeStateMachineTransition.new()
	trans_loco_to_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	trans_loco_to_idle.advance_condition = "not_moving"
	trans_loco_to_idle.xfade_time = 0.2
	state_machine.add_transition("Locomotion", "Idle", trans_loco_to_idle)
	
	# 4. 建立 Jump 状态（如果有跳跃动画）
	# 嘗試多種命名格式: Jump01_Begin, Jump_Begin, JumpStart 等
	var jump_start_name = _find_animation_name(animations, "Jump01_Begin")
	if jump_start_name == "":
		jump_start_name = _find_animation_name(animations, "Jump_Begin")
	
	var jump_loop_name = _find_animation_name(animations, "Jump")
	
	var jump_land_name = _find_animation_name(animations, "Jump01_Land")
	if jump_land_name == "":
		jump_land_name = _find_animation_name(animations, "Jump_Land")
	
	var jump_start_anim = lib_prefix + jump_start_name if jump_start_name != "" else ""
	var jump_loop_anim = lib_prefix + jump_loop_name if jump_loop_name != "" else ""
	var jump_land_anim = lib_prefix + jump_land_name if jump_land_name != "" else ""
	
	print("[AnimationSystem] Jump animations: Start=%s, Loop=%s, Land=%s" % [jump_start_anim, jump_loop_anim, jump_land_anim])
	
	if jump_start_anim != "":
		# JumpStart 狀態
		var jump_start_node = AnimationNodeAnimation.new()
		jump_start_node.animation = jump_start_anim
		state_machine.add_node("JumpStart", jump_start_node)
		
		# JumpLoop 狀態
		if jump_loop_anim != "":
			var jump_loop_node = AnimationNodeAnimation.new()
			jump_loop_node.animation = jump_loop_anim
			state_machine.add_node("JumpLoop", jump_loop_node)
		
		# JumpLand 狀態
		if jump_land_anim != "":
			var jump_land_node = AnimationNodeAnimation.new()
			jump_land_node.animation = jump_land_anim
			state_machine.add_node("JumpLand", jump_land_node)
		
		# 跳躍狀態轉換
		# Idle/Locomotion -> JumpStart
		var trans_to_jump = AnimationNodeStateMachineTransition.new()
		trans_to_jump.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		trans_to_jump.advance_condition = "is_jumping"
		trans_to_jump.xfade_time = 0.1
		state_machine.add_transition("Idle", "JumpStart", trans_to_jump)
		
		var trans_loco_to_jump = AnimationNodeStateMachineTransition.new()
		trans_loco_to_jump.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
		trans_loco_to_jump.advance_condition = "is_jumping"
		trans_loco_to_jump.xfade_time = 0.1
		state_machine.add_transition("Locomotion", "JumpStart", trans_loco_to_jump)
		
		# JumpStart -> JumpLoop (自動，當動畫結束)
		if jump_loop_anim != "":
			var trans_start_to_loop = AnimationNodeStateMachineTransition.new()
			trans_start_to_loop.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
			trans_start_to_loop.xfade_time = 0.1
			state_machine.add_transition("JumpStart", "JumpLoop", trans_start_to_loop)
			
			# JumpLoop -> JumpLand (當觸地)
			if jump_land_anim != "":
				var trans_loop_to_land = AnimationNodeStateMachineTransition.new()
				trans_loop_to_land.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
				trans_loop_to_land.advance_condition = "is_landing"
				trans_loop_to_land.xfade_time = 0.1
				state_machine.add_transition("JumpLoop", "JumpLand", trans_loop_to_land)
				
				# JumpLand -> Idle (自動，當動畫結束)
				var trans_land_to_idle = AnimationNodeStateMachineTransition.new()
				trans_land_to_idle.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
				trans_land_to_idle.xfade_time = 0.2
				state_machine.add_transition("JumpLand", "Idle", trans_land_to_idle)
		
		print("[AnimationSystem] Jump states added to StateMachine")

	state_machine.set_graph_offset(Vector2(100, 100))
	return state_machine

func _validate_animation_tree():
	"""验证场景中的 AnimationTree 配置"""
	if not _anim_tree or not _anim_tree.tree_root:
		print("[AnimationSystem] Warning: No tree_root in AnimationTree")
		return
	
	var state_machine = _anim_tree.tree_root as AnimationNodeStateMachine
	if not state_machine:
		print("[AnimationSystem] Warning: tree_root is not AnimationNodeStateMachine")
		return
	
	# 检查必要的状态
	var required_states = ["Idle", "Locomotion"]
	var optional_states = ["JumpStart", "JumpLand"]
	
	print("[AnimationSystem] Validating AnimationTree configuration...")
	
	for state_name in required_states:
		if not state_machine.has_node(state_name):
			print("[AnimationSystem] ERROR: Missing required state: ", state_name)
		else:
			print("[AnimationSystem]   ✓ ", state_name)
	
	for state_name in optional_states:
		if state_machine.has_node(state_name):
			print("[AnimationSystem]   ✓ ", state_name, " (optional)")
	
	# 检查必要的条件参数（这些会在 update() 中设置）
	var required_conditions = ["is_moving", "not_moving"]
	var _optional_conditions = ["is_jumping", "is_landing", "is_airborne", "is_combat"]
	
	print("[AnimationSystem] Required conditions will be set by update():")
	for cond in required_conditions:
		print("[AnimationSystem]   - ", cond)
	
	print("[AnimationSystem] Scene configuration validated.")


func _load_animation_library(player: AnimationPlayer, skeleton: Skeleton3D):
	var movement_lib_path = "res://Player/assets/characters/player/motion/movement_animations.res"
	var skeleton_path = player.get_path_to(skeleton)
	
	# 檢查是否已經有 movement 庫（可能在場景中手動添加）
	if player.has_animation_library("movement"):
		print("[AnimationSystem] Using existing 'movement' library from scene")
		var existing_lib = player.get_animation_library("movement")
		# 不再運行時修復軌道 - movement.res 已經有正確的軌道路徑
		# 運行時修復會破壞已正確的路徑
		print("[AnimationSystem] Available animations: ", existing_lib.get_animation_list())
		return
	
	# 檢查是否已經有預設庫
	if player.has_animation_library(""):
		var default_lib = player.get_animation_library("")
		if default_lib.get_animation_list().size() > 0:
			print("[AnimationSystem] Using existing default library")
			print("[AnimationSystem] Available animations: ", default_lib.get_animation_list())
			return
	
	# 優先使用預建構的動畫庫
	if FileAccess.file_exists(movement_lib_path):
		var prebuilt_lib = load(movement_lib_path) as AnimationLibrary
		if prebuilt_lib:
			# 修復動畫軌道路徑 (從 GeneralSkeleton:Hips -> Skeleton3D:mixamorig1_Hips)
			for anim_name in prebuilt_lib.get_animation_list():
				var anim = prebuilt_lib.get_animation(anim_name)
				_fix_animation_tracks(anim, skeleton, skeleton_path)
			player.add_animation_library("", prebuilt_lib)
			print("[AnimationSystem] Loaded pre-built movement library: ", movement_lib_path)
			var skel_name = skeleton.name if skeleton else "NONE"
			print("[AnimationSystem] Fixed tracks for skeleton: ", skel_name)
			print("[AnimationSystem] Available animations: ", prebuilt_lib.get_animation_list())
			return
	
	print("[AnimationSystem] Pre-built library not found, loading from FBX...")
	
	# 備用：從 FBX 載入
	var human_anim_base = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/"
	var stride_base_path = "res://Player/assets/characters/player/motion/mx/stride8/"
	var loco_pack_path = stride_base_path + "Locomotion Pack/"
	
	if not player.has_animation_library(""):
		player.add_animation_library("", AnimationLibrary.new())
	
	var lib = player.get_animation_library("")
	
	# 1. 優先加載 "Human Animations"
	var human_walk_path = human_anim_base + "Movement/Walk/"
	var human_run_path = human_anim_base + "Movement/Run/"
	var human_idle_path = human_anim_base + "Idles/"
	
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(human_walk_path)):
		_load_fbx_folder(human_walk_path, lib, skeleton, skeleton_path)
		_load_fbx_folder(human_run_path, lib, skeleton, skeleton_path)
		# 加載 Idle01 作為預設 Idle
		var idle_file = human_idle_path + "HumanM@Idle01.fbx"
		if FileAccess.file_exists(idle_file):
			var scene = load(idle_file)
			if scene:
				var inst = scene.instantiate()
				var sub_player = _find_animation_player(inst)
				if sub_player:
					var anim_list = sub_player.get_animation_list()
					if anim_list.size() > 0:
						var anim = sub_player.get_animation(anim_list[0]).duplicate()
						_fix_animation_tracks(anim, skeleton, skeleton_path)
						anim.loop_mode = Animation.LOOP_LINEAR
						lib.add_animation("Idle", anim)
				inst.queue_free()

	# 2. 加載原有的 stride8 作為補充
	var subfolders = ["walk", "run"]
	for folder in subfolders:
		_load_fbx_folder(stride_base_path + folder + "/", lib, skeleton, skeleton_path)
		
	# 3. 兜底加載 Idle
	if not lib.has_animation("Idle"):
		var fallback_idle = "res://Player/assets/characters/player/motion/mx/Breathing Idle.fbx"
		_load_single_fbx_animation(fallback_idle, lib, skeleton, skeleton_path)
	
	# 4. 加載其他輔助動作 (Locomotion Pack)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(loco_pack_path)):
		_load_fbx_folder(loco_pack_path, lib, skeleton, skeleton_path, ["idle.fbx", "walking.fbx", "running.fbx"])
	
	# 5. 加載跳躍動畫 (Jump)
	var jump_path = human_anim_base + "Movement/Jump/"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(jump_path)):
		_load_fbx_folder(jump_path, lib, skeleton, skeleton_path)
		print("[AnimationSystem] Loaded Jump animations from: ", jump_path)
	
	# 6. 加載衝刺動畫 (Sprint)
	var sprint_path = human_anim_base + "Movement/Sprint/"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(sprint_path)):
		_load_fbx_folder(sprint_path, lib, skeleton, skeleton_path)
		print("[AnimationSystem] Loaded Sprint animations from: ", sprint_path)

func _load_single_fbx_animation(path: String, lib: AnimationLibrary, skeleton: Skeleton3D, skeleton_path: NodePath):
	if not FileAccess.file_exists(path): return

	var anim_name = path.get_file().get_basename()
	if lib.has_animation(anim_name): return

	var scene = load(path)
	if scene:
		var inst = scene.instantiate()
		var sub_player = _find_animation_player(inst)
		if sub_player:
			var anim_list = sub_player.get_animation_list()
			if anim_list.size() > 0:
				var anim = sub_player.get_animation(anim_list[0]).duplicate()
				_fix_animation_tracks(anim, skeleton, skeleton_path)
				anim.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(anim_name, anim)
		inst.queue_free()

func _load_fbx_folder(folder_path: String, lib: AnimationLibrary, skeleton: Skeleton3D, skeleton_path: NodePath, skip_files: Array = []):
	var dir = DirAccess.open(folder_path)
	if not dir: return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".fbx") and not file_name.ends_with(".import") and not skip_files.has(file_name):
			_load_single_fbx_animation(folder_path + file_name, lib, skeleton, skeleton_path)
		file_name = dir.get_next()

func _fix_animation_tracks(anim: Animation, skeleton: Skeleton3D, skeleton_path: NodePath):
	if not skeleton: return
	
	var bone_names = []
	for i in range(skeleton.get_bone_count()):
		bone_names.append(skeleton.get_bone_name(i))
	
	var skeleton_node_name = str(skeleton_path)
	if skeleton_node_name == "":
		skeleton_node_name = skeleton.name
	
	# 手動強制映射表 (B- Style -> Mannequin/Mixamo Style)
	# 根據 Human Animations FBX 的實際骨骼名稱
	var manual_map = {
		# 軀幹
		"B-root": "Hips", # 根骨骼映射到 Hips
		"B-hips": "Hips",
		"B-spine": "Spine",
		"B-chest": "Chest", # chest -> Chest
		"B-upperChest": "UpperChest",
		"B-spineProxy": "", # 忽略
		"B-neck": "Neck",
		"B-head": "Head",
		"B-jaw": "", # 忽略下巴
		
		# 左臂（注意：FBX 使用 upperArm 不是 upper_arm）
		"B-shoulder.L": "LeftShoulder",
		"B-upperArm.L": "LeftUpperArm", # 已修正
		"B-forearm.L": "LeftLowerArm",
		"B-hand.L": "LeftHand",
		"B-handProp.L": "", # 忽略道具骨骼
		
		# 右臂
		"B-shoulder.R": "RightShoulder",
		"B-upperArm.R": "RightUpperArm", # 已修正
		"B-forearm.R": "RightLowerArm",
		"B-hand.R": "RightHand",
		"B-handProp.R": "", # 忽略道具骨骼
		
		# 左腿
		"B-thigh.L": "LeftUpperLeg",
		"B-shin.L": "LeftLowerLeg",
		"B-foot.L": "LeftFoot",
		"B-toe.L": "LeftToes",
		
		# 右腿
		"B-thigh.R": "RightUpperLeg",
		"B-shin.R": "RightLowerLeg",
		"B-foot.R": "RightFoot",
		"B-toe.R": "RightToes",
		
		# 左手指
		"B-thumb01.L": "LeftHandThumb1", "B-thumb02.L": "LeftHandThumb2", "B-thumb03.L": "LeftHandThumb3",
		"B-indexFinger01.L": "LeftHandIndex1", "B-indexFinger02.L": "LeftHandIndex2", "B-indexFinger03.L": "LeftHandIndex3",
		"B-middleFinger01.L": "LeftHandMiddle1", "B-middleFinger02.L": "LeftHandMiddle2", "B-middleFinger03.L": "LeftHandMiddle3",
		"B-ringFinger01.L": "LeftHandRing1", "B-ringFinger02.L": "LeftHandRing2", "B-ringFinger03.L": "LeftHandRing3",
		"B-pinky01.L": "LeftHandPinky1", "B-pinky02.L": "LeftHandPinky2", "B-pinky03.L": "LeftHandPinky3",
		
		# 右手指
		"B-thumb01.R": "RightHandThumb1", "B-thumb02.R": "RightHandThumb2", "B-thumb03.R": "RightHandThumb3",
		"B-indexFinger01.R": "RightHandIndex1", "B-indexFinger02.R": "RightHandIndex2", "B-indexFinger03.R": "RightHandIndex3",
		"B-middleFinger01.R": "RightHandMiddle1", "B-middleFinger02.R": "RightHandMiddle2", "B-middleFinger03.R": "RightHandMiddle3",
		"B-ringFinger01.R": "RightHandRing1", "B-ringFinger02.R": "RightHandRing2", "B-ringFinger03.R": "RightHandRing3",
		"B-pinky01.R": "RightHandPinky1", "B-pinky02.R": "RightHandPinky2", "B-pinky03.R": "RightHandPinky3",
		
		# ============================================================
		# Humanoid Profile -> Mixamo 骨骼名稱映射
		# (movement_animations.res 使用 Humanoid 名稱，Human.fbx 使用 Mixamo 名稱)
		# ============================================================
		# 軀幹
		"Hips": "mixamorig1_Hips",
		"Spine": "mixamorig1_Spine",
		"Chest": "mixamorig1_Spine1",
		"UpperChest": "mixamorig1_Spine2",
		"Neck": "mixamorig1_Neck",
		"Head": "mixamorig1_Head",
		
		# 左臂
		"LeftShoulder": "mixamorig1_LeftShoulder",
		"LeftUpperArm": "mixamorig1_LeftArm",
		"LeftLowerArm": "mixamorig1_LeftForeArm",
		"LeftHand": "mixamorig1_LeftHand",
		
		# 右臂
		"RightShoulder": "mixamorig1_RightShoulder",
		"RightUpperArm": "mixamorig1_RightArm",
		"RightLowerArm": "mixamorig1_RightForeArm",
		"RightHand": "mixamorig1_RightHand",
		
		# 左腿
		"LeftUpperLeg": "mixamorig1_LeftUpLeg",
		"LeftLowerLeg": "mixamorig1_LeftLeg",
		"LeftFoot": "mixamorig1_LeftFoot",
		"LeftToes": "mixamorig1_LeftToeBase",
		
		# 右腿
		"RightUpperLeg": "mixamorig1_RightUpLeg",
		"RightLowerLeg": "mixamorig1_RightLeg",
		"RightFoot": "mixamorig1_RightFoot",
		"RightToes": "mixamorig1_RightToeBase",
		
		# 左手指
		"LeftThumbMetacarpal": "mixamorig1_LeftHandThumb1",
		"LeftThumbProximal": "mixamorig1_LeftHandThumb2",
		"LeftThumbDistal": "mixamorig1_LeftHandThumb3",
		"LeftIndexProximal": "mixamorig1_LeftHandIndex1",
		"LeftIndexIntermediate": "mixamorig1_LeftHandIndex2",
		"LeftIndexDistal": "mixamorig1_LeftHandIndex3",
		"LeftMiddleProximal": "mixamorig1_LeftHandMiddle1",
		"LeftMiddleIntermediate": "mixamorig1_LeftHandMiddle2",
		"LeftMiddleDistal": "mixamorig1_LeftHandMiddle3",
		"LeftRingProximal": "mixamorig1_LeftHandRing1",
		"LeftRingIntermediate": "mixamorig1_LeftHandRing2",
		"LeftRingDistal": "mixamorig1_LeftHandRing3",
		"LeftLittleProximal": "mixamorig1_LeftHandPinky1",
		"LeftLittleIntermediate": "mixamorig1_LeftHandPinky2",
		"LeftLittleDistal": "mixamorig1_LeftHandPinky3",
		
		# 右手指
		"RightThumbMetacarpal": "mixamorig1_RightHandThumb1",
		"RightThumbProximal": "mixamorig1_RightHandThumb2",
		"RightThumbDistal": "mixamorig1_RightHandThumb3",
		"RightIndexProximal": "mixamorig1_RightHandIndex1",
		"RightIndexIntermediate": "mixamorig1_RightHandIndex2",
		"RightIndexDistal": "mixamorig1_RightHandIndex3",
		"RightMiddleProximal": "mixamorig1_RightHandMiddle1",
		"RightMiddleIntermediate": "mixamorig1_RightHandMiddle2",
		"RightMiddleDistal": "mixamorig1_RightHandMiddle3",
		"RightRingProximal": "mixamorig1_RightHandRing1",
		"RightRingIntermediate": "mixamorig1_RightHandRing2",
		"RightRingDistal": "mixamorig1_RightHandRing3",
		"RightLittleProximal": "mixamorig1_RightHandPinky1",
		"RightLittleIntermediate": "mixamorig1_RightHandPinky2",
		"RightLittleDistal": "mixamorig1_RightHandPinky3"
	}

	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# 只處理骨架軌道
		if not ":" in path_str: continue
		
		var parts = path_str.split(":")
		var bone_name = parts[1]
		var found_bone_name = ""
		
		# 0. 先查手動表 (最快且最準)
		if manual_map.has(bone_name):
			var candidate = manual_map[bone_name]
			# 如果映射為空字串，表示要忽略此骨骼
			if candidate == "":
				anim.track_set_enabled(i, false)
				continue
			# 驗證此名稱是否存在於模型中 (考慮 mixamorig: 前綴的可能)
			if candidate in bone_names:
				found_bone_name = candidate
			elif ("mixamorig:" + candidate) in bone_names:
				found_bone_name = "mixamorig:" + candidate
		
		# 1. 直接匹配
		if found_bone_name == "" and bone_name in bone_names:
			found_bone_name = bone_name
		
		# 2. 清理前綴匹配
		if found_bone_name == "":
			var clean_name = bone_name.replace("B-", "").replace("mixamorig_", "").replace("mixamorig1_", "")
			if clean_name in bone_names:
				found_bone_name = clean_name
			elif ("mixamorig:" + clean_name) in bone_names:
				found_bone_name = "mixamorig:" + clean_name
			elif ("mixamorig1:" + clean_name) in bone_names:
				found_bone_name = "mixamorig1:" + clean_name
			elif ("mixamorig1_" + clean_name) in bone_names:
				found_bone_name = "mixamorig1_" + clean_name
		
		# 3. 執行替換
		if found_bone_name != "":
			var new_path = skeleton_node_name + ":" + found_bone_name
			if path_str != new_path:
				anim.track_set_path(i, NodePath(new_path))
			
			# 修正 Hips 位置 (避免角色浮空或鑽地，如果原動畫有位移)
			# 通常我們希望保留位移，但如果有問題可以試著禁用
			# if "Hips" in found_bone_name and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			# 	anim.track_set_enabled(i, false) 
		else:
			# 找不到骨頭，禁用軌道避免紅字
			if anim.track_get_type(i) == Animation.TYPE_POSITION_3D or anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
				# print("[AnimationSystem] Bone NOT found, disabling track: ", bone_name)
				anim.track_set_enabled(i, false)

func _resolve_animation_tree() -> AnimationTree:
	var tree_ref = ecs_world.get("animation_tree")
	if tree_ref is AnimationTree:
		return tree_ref
	if tree_ref is NodePath and ecs_world.has_node(tree_ref):
		return ecs_world.get_node(tree_ref)
	return _find_animation_tree(ecs_world)

func _resolve_animation_player(anim_tree: AnimationTree) -> AnimationPlayer:
	var anim_player: AnimationPlayer = null
	if anim_tree.anim_player != NodePath("") and anim_tree.has_node(anim_tree.anim_player):
		anim_player = anim_tree.get_node(anim_tree.anim_player)
	if not anim_player:
		var root_node: Node = null
		if anim_tree.root_node != NodePath("") and anim_tree.has_node(anim_tree.root_node):
			root_node = anim_tree.get_node(anim_tree.root_node)
		if root_node:
			anim_player = _find_animation_player(root_node)
	if not anim_player:
		anim_player = _find_animation_player(ecs_world)
	if anim_player and (anim_tree.anim_player == NodePath("") or not anim_tree.has_node(anim_tree.anim_player)):
		anim_tree.anim_player = anim_tree.get_path_to(anim_player)
		print("[AnimationSystem] Auto-fixed AnimationPlayer path: ", anim_tree.anim_player)
	return anim_player

func _ensure_root_node(anim_tree: AnimationTree, skeleton: Skeleton3D) -> void:
	if anim_tree.root_node == NodePath("") or not anim_tree.has_node(anim_tree.root_node):
		# 指向 skeleton 的父節點，這樣動畫 tracks 如 "GeneralSkeleton:Hips" 才能正確解析
		var skeleton_parent = skeleton.get_parent()
		if skeleton_parent:
			anim_tree.root_node = anim_tree.get_path_to(skeleton_parent)
		else:
			anim_tree.root_node = anim_tree.get_path_to(skeleton)

func _ensure_universal_library(player: AnimationPlayer) -> bool:
	if player.has_animation_library("universal_anim_lib"):
		return true
	var lib = load(UNIVERSAL_LIB_PATH)
	if lib and lib is AnimationLibrary:
		player.add_animation_library("universal_anim_lib", lib)
		return true
	return false

func _find_animation_tree(node: Node) -> AnimationTree:
	if node is AnimationTree: return node
	for child in node.get_children():
		var found = _find_animation_tree(child)
		if found: return found
	return null

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

func _find_animation_name(anims, target: String) -> String:
	# 精確匹配
	if target in anims:
		return target
	
	# 模糊匹配（包含關鍵字）
	for anim_name in anims:
		if target in anim_name:
			return anim_name
	
	# 不區分大小寫匹配
	var lower_target = target.to_lower()
	for anim_name in anims:
		if anim_name.to_lower() == lower_target or lower_target in anim_name.to_lower():
			return anim_name
	
	return ""

func _add_blend_point(bs: AnimationNodeBlendSpace2D, anim_name: String, position: Vector2) -> void:
	if anim_name == "": return
	var node = AnimationNodeAnimation.new()
	node.animation = anim_name
	bs.add_blend_point(node, position)

func _add_blend_points(bs: AnimationNodeBlendSpace2D, anims: Array):
	# 檢測庫前綴
	var lib_prefix = ""
	
	if _anim_player:
		if _anim_player.has_animation_library("movement"):
			lib_prefix = "movement/"
			print("[AnimationSystem] Using library prefix: 'movement/'")
		elif _anim_player.has_animation_library("movement_animations"):
			lib_prefix = "movement_animations/"
			print("[AnimationSystem] Using library prefix: 'movement_animations/'")
	
	# 方向向量映射（X 左右，Y 前後）
	var dir_vectors = {
		"Forward": Vector2(0, 1),
		"Backward": Vector2(0, -1),
		"Left": Vector2(-1, 0),
		"Right": Vector2(1, 0),
		"ForwardLeft": Vector2(-1, 1).normalized(),
		"ForwardRight": Vector2(1, 1).normalized(),
		"BackwardLeft": Vector2(-1, -1).normalized(),
		"BackwardRight": Vector2(1, -1).normalized()
	}
	
	# Stride8 格式的縮寫映射
	var stride8_mapping = {
		"Forward": "f", "Backward": "b", "Left": "l", "Right": "r",
		"ForwardLeft": "fl", "ForwardRight": "fr", "BackwardLeft": "bl", "BackwardRight": "br"
	}
	
	print("[AnimationSystem] Mapping 8-way BlendSpace...")
	print("[AnimationSystem] Available animations: ", anims.size())
	var mapped_walk = 0
	var mapped_run = 0
	
	for dir_name in dir_vectors.keys():
		var vec = dir_vectors[dir_name]
		
		# === Walk 動畫 (magnitude 0.5) ===
		var walk_found = false
		
		# 1. 簡化格式: Walk_Forward, Walk_Left, etc.
		for a in anims:
			if a == "Walk_" + dir_name or a == "Walk" + dir_name:
				_add_blend_point(bs, lib_prefix + a, vec * 0.5)
				mapped_walk += 1
				walk_found = true
				break
		
		# 2. 原始 FBX 格式: HumanM@Walk01_Forward
		if not walk_found:
			for a in anims:
				if ("@Walk" in a or "Walk01" in a) and a.ends_with("_" + dir_name):
					_add_blend_point(bs, a, vec * 0.5)
					mapped_walk += 1
					walk_found = true
					break
		
		# 3. Stride8 格式: pc_mx_stride8_f_walk
		if not walk_found:
			var stride_key = stride8_mapping[dir_name]
			var walk_target = "pc_mx_stride8_" + stride_key + "_walk"
			for a in anims:
				if a.ends_with(walk_target):
					_add_blend_point(bs, a, vec * 0.5)
					mapped_walk += 1
					break
		
		# === Run 動畫 (magnitude 1.0) ===
		var run_found = false
		
		# 1. 簡化格式: Run_Forward, Run_Left, etc.
		for a in anims:
			if a == "Run_" + dir_name or a == "Run" + dir_name:
				_add_blend_point(bs, lib_prefix + a, vec * 1.0)
				mapped_run += 1
				run_found = true
				break
		
		# 2. 原始 FBX 格式: HumanM@Run01_Forward
		if not run_found:
			for a in anims:
				if ("@Run" in a or "Run01" in a) and a.ends_with("_" + dir_name):
					_add_blend_point(bs, a, vec * 1.0)
					mapped_run += 1
					run_found = true
					break
		
		# 3. Stride8 格式: pc_mx_stride8_f_run
		if not run_found:
			var stride_key = stride8_mapping[dir_name]
			var run_target = "pc_mx_stride8_" + stride_key + "_run"
			for a in anims:
				if a.ends_with(run_target):
					_add_blend_point(bs, a, vec * 1.0)
					mapped_run += 1
					break
		
		# === Sprint 動畫 (magnitude 1.5) ===
		var sprint_found = false
		
		# 1. 簡化格式: Sprint_Forward, Sprint_Left, etc.
		for a in anims:
			if a == "Sprint_" + dir_name or a == "Sprint" + dir_name:
				_add_blend_point(bs, lib_prefix + a, vec * 1.5)
				sprint_found = true
				break
		
		# 2. 原始 FBX 格式: HumanM@Sprint01_Forward
		if not sprint_found:
			for a in anims:
				if ("@Sprint" in a or "Sprint01" in a) and a.ends_with("_" + dir_name):
					_add_blend_point(bs, a, vec * 1.5)
					sprint_found = true
					break
	
	# 兜底：通用 walking/running 動畫
	if mapped_walk < 4:
		var walk_name = _find_animation_name(anims, "walking")
		if walk_name != "":
			_add_blend_point(bs, walk_name, Vector2(0, 0.5))
			print("[AnimationSystem] Fallback walk: ", walk_name)
	
	if mapped_run < 4:
		var run_name = _find_animation_name(anims, "running")
		if run_name != "":
			_add_blend_point(bs, run_name, Vector2(0, 1.0))
			print("[AnimationSystem] Fallback run: ", run_name)
	
	print("[AnimationSystem] Mapped %d walk + %d run = %d total blend points (Sprint also added)" % [mapped_walk, mapped_run, bs.get_blend_point_count()])

func update(delta: float) -> void:
	if not _initialized: _init_system()
	if not ecs_world or not _anim_tree or not _initialized: return
	
	var entities = ecs_world.get_entities_with(["MovementState", "AnimationComponent", "PhysicsComponent"])
	for entity_id in entities:
		var movement = ecs_world.get_component(entity_id, "MovementState")
		var anim_comp = ecs_world.get_component(entity_id, "AnimationComponent")
		var physics = ecs_world.get_component(entity_id, "PhysicsComponent")
		if not movement or not anim_comp or not physics: continue
		
		# 調試：每30幀輸出一次地面狀態
		if Engine.get_process_frames() % 30 == 0:
			print("[AnimationSystem] Grounded state: was=", anim_comp.was_grounded, " current=", physics.is_grounded)
		
		var horizontal_speed = Vector2(physics.velocity.x, physics.velocity.z).length()
		
		# 使用遲滯判定避免抖動：開始移動需要 > 0.15，停止需要 < 0.1
		if _is_moving_state:
			_is_moving_state = horizontal_speed > 0.1 # 較低閾值停止
		else:
			_is_moving_state = horizontal_speed > 0.15 # 啟動閾值（原 0.3 太高導致短按沒反應）
		var is_moving = _is_moving_state
		var intent_dir = Vector2.ZERO
		var mv = movement.move_vector
		# BlendSpace2D: X=左右, Y=前後 (Forward=+Y, Backward=-Y)
		# InputSystem 設置 move_vector: Y+ = forward, X+ = right，與 BlendSpace2D 一致
		if mv is Vector3: intent_dir = Vector2(mv.x, -mv.z) # 3D: -Z是前進，需反轉為 +Y
		elif mv is Vector2: intent_dir = mv # 2D: 已經是 Y+=forward，直接使用
		
		# 根據速度和模式決定 magnitude：Walk (0.5), Run (1.0), Sprint (1.5)
		var walk_speed = 5.0 # 走路最大速度
		var run_speed = 8.0 # 跑步最大速度
		var sprint_speed = 12.0 # 衝刺最大速度
		
		var target_magnitude = 0.5 # 預設為 Walk
		
		# 檢查是否在 sprint 模式
		var is_sprinting = movement.mode == "sprint"
		
		if is_sprinting:
			# Sprint 模式：使用 1.5 magnitude
			if horizontal_speed > run_speed:
				var t = clamp((horizontal_speed - run_speed) / (sprint_speed - run_speed), 0.0, 1.0)
				target_magnitude = lerp(1.0, 1.5, t)
			elif horizontal_speed > walk_speed:
				target_magnitude = 1.0
			elif horizontal_speed > 0.1:
				target_magnitude = 0.5
		elif horizontal_speed > walk_speed:
			# 普通跑步：速度在 walk_speed 到 run_speed 之間
			var t = clamp((horizontal_speed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
			target_magnitude = lerp(0.5, 1.0, t)
		elif horizontal_speed > 0.1:
			# 走路
			target_magnitude = 0.5
		
		# 動畫步幅速度 (walking 動畫設計時假設的移動速度)
		# 增加這個值會讓動畫播放更慢，減少跳躍感
		var anim_stride_speed = 4.0 # 調高以減少跳躍感
		
		var target_pos = Vector2.ZERO
		if is_moving and intent_dir.length() > 0.1:
			# 方向映射：直接使用 intent_dir（BlendSpace2D 已調整位置）
			target_pos = intent_dir.normalized() * target_magnitude
		elif is_moving:
			var basis = ecs_world.global_transform.basis.orthonormalized()
			var local_vel = basis.inverse() * physics.velocity
			# 方向映射：直接使用 local_vel
			target_pos = Vector2(local_vel.x, local_vel.z).normalized() * target_magnitude
		
		
		# 只在移動時更新 blend_position，停止時凍結以避免抖動
		if is_moving:
			# 方向切換響應速度
			var blend_speed = 15.0 # 基础过渡速度
			
			# 计算方向变化角度
			var angle_diff = abs(_current_blend_pos.angle_to(target_pos))
			
			# 180° 反向需要較慢速度，讓 blend 經過中心 Idle 動畫避免 quaternion twist
			if angle_diff > PI * 0.75: # 135度以上（前↔後切换）
				blend_speed = 6.0 # 較慢，讓過渡經過中心 Idle
			elif angle_diff > PI / 2: # 90-135度
				blend_speed = 10.0
			elif angle_diff > PI / 4: # 45-90度
				blend_speed = 12.0
			# else: 使用默认的 15.0（小角度最快响应）
			
			# 使用指数衰减插值代替线性 move_toward，提供更自然的减速
			var lerp_weight = clamp(delta * blend_speed, 0.0, 1.0)
			_current_blend_pos = _current_blend_pos.lerp(target_pos, lerp_weight)
			
			# 更新 BlendSpace2D 參數（支援多種結構）
			# 新簡化結構：movement 直接是 BlendSpace2D
			if _anim_tree.get("parameters/movement/blend_position") != null:
				# 計算基於速度的 Y 軸位置
				# Y: 0=Idle, ±0.5=Walk, ±1=Run
				var speed_y = 0.0
				if horizontal_speed > 0.1:
					if horizontal_speed >= run_speed:
						speed_y = 1.0
					elif horizontal_speed >= walk_speed:
						speed_y = remap(horizontal_speed, walk_speed, run_speed, 0.5, 1.0)
					else:
						speed_y = remap(horizontal_speed, 0.0, walk_speed, 0.0, 0.5)
				
				# 根據移動方向設定
				var final_pos = _current_blend_pos * speed_y
				_anim_tree.set("parameters/movement/blend_position", final_pos)
			# 舊複雜結構：Grounded/Locomotion/Walk 和 Grounded/Locomotion/Run
			elif _anim_tree.get("parameters/Grounded/Locomotion/Walk/blend_position") != null:
				_anim_tree.set("parameters/Grounded/Locomotion/Walk/blend_position", _current_blend_pos)
				_anim_tree.set("parameters/Grounded/Locomotion/Run/blend_position", _current_blend_pos)
				
				# 計算 IdleLocoBlend (0=Idle, 1=Locomotion) 和 WalkRunBlend (0=Walk, 1=Run)
				var idle_loco_blend = clamp(horizontal_speed / (walk_speed * 0.5), 0.0, 1.0)
				var walk_run_blend = clamp((horizontal_speed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
				_anim_tree.set("parameters/Grounded/IdleLocoBlend/blend_amount", idle_loco_blend)
				_anim_tree.set("parameters/Grounded/Locomotion/WalkRunBlend/blend_amount", walk_run_blend)
			# 舊結構：Locomotion/WalkSpace 和 Locomotion/RunSpace
			elif _anim_tree.get("parameters/Locomotion/WalkSpace/blend_position") != null:
				_anim_tree.set("parameters/Locomotion/WalkSpace/blend_position", _current_blend_pos)
				_anim_tree.set("parameters/Locomotion/RunSpace/blend_position", _current_blend_pos)
				
				# 計算 IdleWalkBlend (0=Idle, 1=Walk) 和 WalkRunBlend (0=Walk, 1=Run)
				var idle_walk_blend = clamp(horizontal_speed / walk_speed, 0.0, 1.0)
				var walk_run_blend = clamp((horizontal_speed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
				_anim_tree.set("parameters/Locomotion/IdleWalkBlend/blend_amount", idle_walk_blend)
				_anim_tree.set("parameters/Locomotion/WalkRunBlend/blend_amount", walk_run_blend)
			else:
				# 備用：Locomotion 直接是 BlendSpace2D
				_anim_tree.set("parameters/Locomotion/blend_position", _current_blend_pos)
		else:
			# 停止時：緩慢回到 Idle (0,0)
			_current_blend_pos = _current_blend_pos.lerp(Vector2.ZERO, delta * 5.0)
			# 確保更新主要路徑
			if _anim_tree.get("parameters/movement/blend_position") != null:
				_anim_tree.set("parameters/movement/blend_position", _current_blend_pos)
		
		_anim_tree.set("parameters/conditions/is_moving", is_moving)

		
		# Debug 輸出 - 每 60 幀顯示一次
		if Engine.get_process_frames() % 60 == 0:
			print("[AnimDebug] speed=%.2f magnitude=%.2f blend=(%.2f,%.2f) moving=%s mode=%s" % [
				horizontal_speed, target_magnitude, _current_blend_pos.x, _current_blend_pos.y,
				is_moving, movement.mode if movement else "?"
			])
		_anim_tree.set("parameters/conditions/not_moving", not is_moving)
		_anim_tree.set("parameters/conditions/is_airborne", not physics.is_grounded)
		_anim_tree.set("parameters/conditions/is_combat", anim_comp.is_combat)
		
		# 跳躍參數：檢測從地面到空中（起跳）和從空中到地面（落地）
		var was_grounded = anim_comp.was_grounded
		var is_grounded = physics.is_grounded
		
		# 新 StateMachine 結構使用 conditions：
		# - is_jumping: Grounded → Airborne
		# - is_grounded: Airborne → Grounded
		_anim_tree.set("parameters/conditions/is_grounded", is_grounded)
		
		# 獲取 playback 一次用於多個檢查
		var playback = _anim_tree.get("parameters/playback")
		
		# 觸發起跳：從地面進入空中 + 必須有向上速度（區分跳躍和走下平台）
		var is_leaving_ground = was_grounded and not is_grounded
		var has_upward_velocity = physics.velocity.y > 0.5 # 向上速度 > 0.5 才算跳躍
		var is_jumping = is_leaving_ground and has_upward_velocity
		
		if is_leaving_ground and not has_upward_velocity:
			print("[AnimationSystem] 🚶 Walking off ledge (not jumping) - skipping jump")
		
		if is_jumping:
			print("[AnimationSystem] 🦘 JUMP DETECTED! upward_velocity=", physics.velocity.y)
			_anim_tree.set("parameters/conditions/is_jumping", true)
		elif is_grounded:
			# 落地時重置 is_jumping
			_anim_tree.set("parameters/conditions/is_jumping", false)
		
		# 觸發落地：檢測從空中到地面
		var is_actually_landed = not was_grounded and is_grounded

		
		# 方案2：預測著地 - 在空中但接近地面
		var is_approaching_ground = false
		if not is_grounded and physics.velocity.y < 0: # 在空中且向下移動
			# 嘗試獲取 ground_ray 來檢測地面距離
			var ground_ray = ecs_world.get("ground_ray")
			if ground_ray is RayCast3D and ground_ray.is_colliding():
				var distance_to_ground = ecs_world.global_position.distance_to(ground_ray.get_collision_point())
				# 當距離地面 < 0.5m 時開始播放落地動畫
				if distance_to_ground < 0.5:
					is_approaching_ground = true
					if Engine.get_process_frames() % 10 == 0: # 防止日誌刷屏
						print("[AnimationSystem] 🔽 APPROACHING GROUND! distance=", distance_to_ground)
		
		# 觸發 is_landing：要麼即將著地，要麼已著地
		var is_landing = is_actually_landed or is_approaching_ground
		if is_landing:
			if is_actually_landed:
				print("[AnimationSystem] 🛬 LANDING DETECTED! was_grounded=", was_grounded, " is_grounded=", is_grounded)
			
			# 直接使用 travel() 触发落地动画，条件转换不可靠
			# 只有在 JumpStart 状态时才播放落地动画（走下平台不需要）
			if playback:
				var current = playback.get_current_node()
				if current == "JumpStart":
					print("[AnimationSystem] ✈️ Transitioning JumpStart → JumpLand")
					playback.travel("JumpLand")
				elif is_actually_landed:
					# 走下平台落地，跳过落地动画，直接回到 Idle/Locomotion
					print("[AnimationSystem] 🚶 Ledge landing (not from jump) - skipping JumpLand")

		
		# 更新上一幀的地面狀態
		anim_comp.was_grounded = is_grounded
		
		# 使用 playback 處理狀態機轉換
		# 新結構只有 'movement' 狀態（BlendSpace2D 已處理 Idle/Walk/Run）
		if playback:
			var current_node = playback.get_current_node()
			var is_in_jump_state = current_node in ["JumpStart", "JumpLand"]
			
			# DEBUG: 跳跃帧调试
			if is_jumping or is_landing:
				print("[AnimationSystem] 🐛 Jump frame - current_node: ", current_node, " is_in_jump_state: ", is_in_jump_state)
				print("[AnimationSystem] 🐛 Condition check: not_in_jump=", not is_in_jump_state, " not_jumping=", not is_jumping, " not_landing=", not is_landing)
			
		# 只在以下情況使用 travel()：
			# 1. 不在跳躍狀態
			# 2. 沒有觸發跳躍或落地
			if not is_in_jump_state and not is_jumping and not is_landing:
				# 如果卡在 Start，使用 start() 跳到 movement
				if current_node == "Start" or current_node == "":
					print("[AnimationSystem] Unstuck: start(\"movement\") from Start")
					playback.start("movement")
				# 新結構不需要 Idle/Locomotion 切換，blend_position 已處理
		
		# 動畫速度縮放：根據移動方向調整
		# 後退動畫較慢，需要較低的基準速度
		var dir_stride_speed = anim_stride_speed
		if _current_blend_pos.y < -0.3: # 後退方向
			dir_stride_speed = 2.5 # 後退動畫較慢
		var speed_scale = clamp(horizontal_speed / dir_stride_speed, 0.8, 2.0)
		_anim_tree.set("parameters/movement/speed_scale", speed_scale)

func _debug_print_animation_info():
	print("\n=== ANIMATION DIAGNOSTIC INFO ===")
	
	# Find skeleton dynamically
	var root_node: Node = null
	if _anim_tree.root_node != NodePath("") and _anim_tree.has_node(_anim_tree.root_node):
		root_node = _anim_tree.get_node(_anim_tree.root_node)
	if not root_node:
		root_node = ecs_world
	var skeleton = _find_skeleton(root_node)
	
	# 1. Print skeleton bones (first 15)
	print("--- Skeleton Bones (first 15) ---")
	if skeleton:
		for i in range(min(skeleton.get_bone_count(), 15)):
			print("  [%d] %s" % [i, skeleton.get_bone_name(i)])
		print("  ... total bones: ", skeleton.get_bone_count())
	else:
		print("  ERROR: No skeleton reference!")
	
	# 2. Print animation track paths from Idle animation
	print("--- Animation Tracks 'movement/Idle' (first 10) ---")
	var anim_player = _anim_tree.get_node(_anim_tree.anim_player) if _anim_tree.anim_player else null
	if anim_player:
		# Try with library prefix first
		var anim_name = "movement/Idle"
		if not anim_player.has_animation(anim_name):
			anim_name = "Idle" # Try without prefix
		
		if anim_player.has_animation(anim_name):
			var anim = anim_player.get_animation(anim_name)
			print("  Animation found: ", anim_name, " (", anim.get_track_count(), " tracks)")
			for i in range(min(anim.get_track_count(), 10)):
				var path = anim.track_get_path(i)
				var track_type = anim.track_get_type(i)
				var type_name = ["Value", "Position3D", "Rotation3D", "Scale3D", "BlendShape", "Method", "Bezier", "Audio", "Animation"][track_type] if track_type < 9 else str(track_type)
				print("  [%d] %s (%s)" % [i, path, type_name])
		else:
			print("  ERROR: Animation 'Idle' not found!")
			print("  Available animations:")
			for lib_name in anim_player.get_animation_library_list():
				var lib = anim_player.get_animation_library(lib_name)
				print("    Library '%s': %s" % [lib_name, lib.get_animation_list()])
	else:
		print("  ERROR: AnimationPlayer not found!")
	
	# 3. Print root_node resolution
	print("--- Root Node Info ---")
	print("  AnimationTree.root_node = ", _anim_tree.root_node)
	if _anim_tree.has_node(_anim_tree.root_node):
		var root = _anim_tree.get_node(_anim_tree.root_node)
		print("  Resolved to: ", root.name, " (", root.get_class(), ")")
		print("  Root children:")
		for child in root.get_children():
			print("    - ", child.name, " (", child.get_class(), ")")
	else:
		print("  ERROR: root_node path does not resolve!")
	
	# 4. Check anim_player path
	print("--- AnimationPlayer Path ---")
	print("  AnimationTree.anim_player = ", _anim_tree.anim_player)
	if anim_player:
		print("  AnimationPlayer.root_node = ", anim_player.root_node)
	
	print("=================================\n")
