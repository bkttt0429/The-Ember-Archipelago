@tool
extends EditorScript

# 您的資料夾路徑 (請依實際情況微調)
const SEARCH_PATHS = [
	"res://Player/assets/characters/player/motion/Universal Animation Library[Standard]/Unreal-Godot/",
	"res://Player/assets/characters/player/motion/Universal Animation Library 2[Standard]/Unreal-Godot/"
]

# 輸出的動畫庫路徑
const OUTPUT_PATH = "res://Player/universal_anim_lib.tres"

func _run():
	print("--- 開始打包 Universal Animation Library ---")
	
	# 1. 獲取有效骨架列表 (從 Mannequin.fbx)
	var valid_bones = _get_valid_bones()
	if valid_bones.is_empty():
		printerr("警告：無法讀取 Mannequin 骨架，將跳過骨架驗證步驟！(這可能導致無效軌道殘留)")
	else:
		print("成功讀取 Mannequin 骨架，共 ", valid_bones.size(), " 根骨頭。")

	var lib = AnimationLibrary.new()
	var count = 0
	
	for path in SEARCH_PATHS:
		print("正在掃描: ", path)
		var dir = DirAccess.open(path)
		if not dir:
			printerr("無法打開路徑: ", path)
			continue
			
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			var anim_name = file_name.get_basename()
			# 過濾掉 Zombie 相關動畫
			if "Zombie" in anim_name or "zombie" in anim_name:
				file_name = dir.get_next()
				continue
			
			if not dir.current_is_dir() and file_name.ends_with(".res"):
				var full_path = path.path_join(file_name)
				# 載入動畫資源
				var anim = load(full_path)
				if anim is Animation:
					_process_and_add_animation(lib, anim, anim_name, count, valid_bones)
					count += 1
			
			file_name = dir.get_next()

	# 額外載入 MX Stride8 的 FBX 動畫 (Walk & Run)
	var mx_paths = [
		"res://Player/assets/characters/player/motion/mx/", # Added for Breathing Idle
		"res://Player/assets/characters/player/motion/mx/stride8/walk/",
		"res://Player/assets/characters/player/motion/mx/stride8/run/"
	]
	
	for path in mx_paths:
		print("正在掃描 FBX: ", path)
		var dir = DirAccess.open(path)
		if not dir: continue
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".fbx") and not file_name.ends_with(".import"):
				var full_path = path.path_join(file_name)
				var anim_name = file_name.get_basename()
				
				# 載入 FBX 場景並提取動畫
				var scene = load(full_path)
				if scene:
					var inst = scene.instantiate()
					var anim_player = _find_animation_player(inst)
					if anim_player:
						var anim_list = anim_player.get_animation_list()
						if anim_list.size() > 0:
							# 複製動畫以斷開與原始場景的連結
							var anim = anim_player.get_animation(anim_list[0]).duplicate()
							
							# 設定名稱 (移除 Mixamo 前綴等)
							_process_and_add_animation(lib, anim, anim_name, count, valid_bones)
							count += 1
					inst.free() # 立即釋放
			file_name = dir.get_next()

	if count > 0:
		var err = ResourceSaver.save(lib, OUTPUT_PATH)
		if err == OK:
			print("成功！已打包 ", count, " 個動畫至: ", OUTPUT_PATH)
			print("現在您可以在 AnimationPlayer 中載入此 .tres 檔案。")
			# EditorInterface.get_resource_filesystem().scan() # 暫時移除自動掃描，避免潛在的崩潰
		else:
			printerr("儲存失敗: ", err)
	else:
		printerr("未找到任何動畫檔！")

func _process_and_add_animation(lib: AnimationLibrary, anim: Animation, anim_name: String, _idx: int, valid_bones: Array = []) -> void:
	# 處理重名
	var final_name = anim_name
	if lib.has_animation(final_name):
		final_name += "_2"
		print("重名處理: ", anim_name, " -> ", final_name)
	
	# 設置循環
	if "Walk" in final_name or "Run" in final_name or "Idle" in final_name or "walk" in final_name or "run" in final_name:
		anim.loop_mode = Animation.LOOP_LINEAR

	# 執行骨架修復
	# 用反向迴圈，方便刪除無效軌道
	for i in range(anim.get_track_count() - 1, -1, -1):
		var track_path = anim.track_get_path(i)
		var path_str = str(track_path)
		
		# === 強力名稱映射邏輯 ===
		var parts = path_str.split(":")
		if parts.size() > 1:
			var node_part = parts[0]
			var bone_part = parts[1]
			
			# 1. 修正節點名稱 (Node Name Fix)
			if "%GeneralSkeleton" in node_part: node_part = "GeneralSkeleton"
			elif "Skeleton3D" in node_part: node_part = "GeneralSkeleton"
			
			# 2. 骨頭名稱標準化 (Bone Name Normalization)
			var refined_bone = bone_part
			
			# 移除常見前綴
			refined_bone = refined_bone.replace("mixamorig_", "").replace("mixamorig1_", "").replace("mixamorig:", "")
			
			# 定義手動映射表 (涵蓋 B- 骨架 與 常見命名差異)
			var manual_map = {
				"B-hips": "Hips", "B-spine": "Spine", "B-chest": "Spine1", "B-upperChest": "Spine2",
				"B-neck": "Neck", "B-head": "Head",
				"B-shoulder.L": "LeftShoulder", "B-upper_arm.L": "LeftArm", "B-forearm.L": "LeftForeArm", "B-hand.L": "LeftHand",
				"B-shoulder.R": "RightShoulder", "B-upper_arm.R": "RightArm", "B-forearm.R": "RightForeArm", "B-hand.R": "RightHand",
				"B-thigh.L": "LeftUpLeg", "B-shin.L": "LeftLeg", "B-foot.L": "LeftFoot", "B-toe.L": "LeftToeBase",
				"B-thigh.R": "RightUpLeg", "B-shin.R": "RightLeg", "B-foot.R": "RightFoot", "B-toe.R": "RightToeBase",
				"B-thumb01.L": "LeftHandThumb1", "B-thumb02.L": "LeftHandThumb2", "B-thumb03.L": "LeftHandThumb3",
				"B-indexFinger01.L": "LeftHandIndex1", "B-indexFinger02.L": "LeftHandIndex2", "B-indexFinger03.L": "LeftHandIndex3",
				"B-middleFinger01.L": "LeftHandMiddle1", "B-middleFinger02.L": "LeftHandMiddle2", "B-middleFinger03.L": "LeftHandMiddle3",
				"B-ringFinger01.L": "LeftHandRing1", "B-ringFinger02.L": "LeftHandRing2", "B-ringFinger03.L": "LeftHandRing3",
				"B-pinky01.L": "LeftHandPinky1", "B-pinky02.L": "LeftHandPinky2", "B-pinky03.L": "LeftHandPinky3",
				"B-thumb01.R": "RightHandThumb1", "B-thumb02.R": "RightHandThumb2", "B-thumb03.R": "RightHandThumb3",
				"B-indexFinger01.R": "RightHandIndex1", "B-indexFinger02.R": "RightHandIndex2", "B-indexFinger03.R": "RightHandIndex3",
				"B-middleFinger01.R": "RightHandMiddle1", "B-middleFinger02.R": "RightHandMiddle2", "B-middleFinger03.R": "RightHandMiddle3",
				"B-ringFinger01.R": "RightHandRing1", "B-ringFinger02.R": "RightHandRing2", "B-ringFinger03.R": "RightHandRing3",
				"B-pinky01.R": "RightHandPinky1", "B-pinky02.R": "RightHandPinky2", "B-pinky03.R": "RightHandPinky3",
				"RightToes": "RightToeBase", "LeftToes": "LeftToeBase",
				"RightShoe": "RightFoot", "LeftShoe": "LeftFoot",
				"RightHandThumb4": "RightHandThumb3", "LeftHandThumb4": "LeftHandThumb3",
				
				# Mappings for Unreal/Humanoid naming
				"Chest": "Spine1", "UpperChest": "Spine2",
				
				"LeftUpperLeg": "LeftUpLeg", "RightUpperLeg": "RightUpLeg",
				"LeftLowerLeg": "LeftLeg", "RightLowerLeg": "RightLeg",
				
				# Fingers - Left
				"LeftIndexProximal": "LeftHandIndex1", "LeftIndexIntermediate": "LeftHandIndex2", "LeftIndexDistal": "LeftHandIndex3", "index_04_leaf_l": "LeftHandIndex4",
				"LeftMiddleProximal": "LeftHandMiddle1", "LeftMiddleIntermediate": "LeftHandMiddle2", "LeftMiddleDistal": "LeftHandMiddle3", "middle_04_leaf_l": "LeftHandMiddle4",
				"LeftRingProximal": "LeftHandRing1", "LeftRingIntermediate": "LeftHandRing2", "LeftRingDistal": "LeftHandRing3", "ring_04_leaf_l": "LeftHandRing4",
				"LeftLittleProximal": "LeftHandPinky1", "LeftLittleIntermediate": "LeftHandPinky2", "LeftLittleDistal": "LeftHandPinky3", "pinky_04_leaf_l": "LeftHandPinky4",
				"LeftThumbMetacarpal": "LeftHandThumb1", "LeftThumbProximal": "LeftHandThumb2", "LeftThumbDistal": "LeftHandThumb3", "thumb_04_leaf_l": "LeftHandThumb4",

				# Fingers - Right
				"RightIndexProximal": "RightHandIndex1", "RightIndexIntermediate": "RightHandIndex2", "RightIndexDistal": "RightHandIndex3", "index_04_leaf_r": "RightHandIndex4",
				"RightMiddleProximal": "RightHandMiddle1", "RightMiddleIntermediate": "RightHandMiddle2", "RightMiddleDistal": "RightHandMiddle3", "middle_04_leaf_r": "RightHandMiddle4",
				"RightRingProximal": "RightHandRing1", "RightRingIntermediate": "RightHandRing2", "RightRingDistal": "RightHandRing3", "ring_04_leaf_r": "RightHandRing4",
				"RightLittleProximal": "RightHandPinky1", "RightLittleIntermediate": "RightHandPinky2", "RightLittleDistal": "RightHandPinky3", "pinky_04_leaf_r": "RightHandPinky4",
				"RightThumbMetacarpal": "RightHandThumb1", "RightThumbProximal": "RightHandThumb2", "RightThumbDistal": "RightHandThumb3", "thumb_04_leaf_r": "RightHandThumb4",
				
				# Leafs
				"ball_leaf_l": "LeftToe_End", "ball_leaf_r": "RightToe_End"
			}
			
			# 查表替換
			if manual_map.has(refined_bone):
				refined_bone = manual_map[refined_bone]
			
			# 組合新路徑
			path_str = node_part + ":" + refined_bone
		
		# === 應用新路徑 ===
		if str(track_path) != path_str:
			anim.track_set_path(i, NodePath(path_str))
		
		# === 驗證與刪除無效軌道 ===
		if not valid_bones.is_empty() and "GeneralSkeleton:" in path_str:
			var parts_check = path_str.split(":")
			if parts_check.size() > 1:
				var target_bone = parts_check[1]
				# 排除 Root 因為有些動畫需要 Root Motion 但骨架不一定有 Root 骨
				if target_bone.to_lower() == "root":
					pass
				# 如果該動畫軌道的骨頭，在我們的模型骨架中不存在 -> 刪除該軌道
				elif not valid_bones.has(target_bone):
					# 嘗試加 mixamorig: 或 mixamorig1_ 前綴再找一次
					var prefixes = ["mixamorig:", "mixamorig1_"]
					var found_prefixed = false
					
					for prefix in prefixes:
						var p_bone = prefix + target_bone
						if valid_bones.has(p_bone):
							path_str = parts_check[0] + ":" + p_bone
							anim.track_set_path(i, NodePath(path_str))
							found_prefixed = true
							break
					
					if not found_prefixed:
						# 真的找不到 -> 刪除
						# print("移除無效骨頭軌道: ", target_bone, " (Raw: ", track_path, ")")
						anim.remove_track(i)
		

	lib.add_animation(final_name, anim)

func _get_valid_bones() -> Array:
	var model_path = "res://Assets/Models/character/mannequin.fbx"
	if not FileAccess.file_exists(model_path):
		printerr("錯誤：找不到模型檔: ", model_path)
		return []
		
	var scene = load(model_path)
	if not scene: return []
	var inst = scene.instantiate()
	
	var skeleton: Skeleton3D = null
	if inst is Skeleton3D:
		skeleton = inst
	else:
		skeleton = _find_skeleton(inst)
		
	var bones = []
	if skeleton:
		for i in range(skeleton.get_bone_count()):
			bones.append(skeleton.get_bone_name(i))
	
	inst.free()
	return bones

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found: return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found: return found
	return null
