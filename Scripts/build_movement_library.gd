@tool
extends EditorScript

# 從 Human Animations 建立移動動畫庫
# 運行方式：Godot 編輯器中 File > Run
# 輸出：res://Player/assets/characters/player/motion/movement_animations.res

const HUMAN_ANIM_BASE = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/"
const OUTPUT_PATH = "res://Player/assets/characters/player/motion/movement_animations.res"
const SKELETON_PATH = "res://Player/assets/characters/player/Characters_Mannequin.fbx"

# 要載入的動畫資料夾
const ANIM_FOLDERS = {
	"Movement/Walk": true,
	"Movement/Run": true,
	"Movement/Jump": true,
	"Movement/Sprint": true,
	"Idles": true
}

# B- 骨骼 -> Mannequin 骨骼映射
const BONE_MAP = {
	"B-root": "Hips",
	"B-hips": "Hips",
	"B-spine": "Spine",
	"B-chest": "Chest",
	"B-upperChest": "UpperChest",
	"B-spineProxy": "",
	"B-neck": "Neck",
	"B-head": "Head",
	"B-jaw": "",
	"B-shoulder.L": "LeftShoulder",
	"B-upperArm.L": "LeftUpperArm",
	"B-forearm.L": "LeftLowerArm",
	"B-hand.L": "LeftHand",
	"B-handProp.L": "",
	"B-shoulder.R": "RightShoulder",
	"B-upperArm.R": "RightUpperArm",
	"B-forearm.R": "RightLowerArm",
	"B-hand.R": "RightHand",
	"B-handProp.R": "",
	"B-thigh.L": "LeftUpperLeg",
	"B-shin.L": "LeftLowerLeg",
	"B-foot.L": "LeftFoot",
	"B-toe.L": "LeftToes",
	"B-thigh.R": "RightUpperLeg",
	"B-shin.R": "RightLowerLeg",
	"B-foot.R": "RightFoot",
	"B-toe.R": "RightToes",
	"B-thumb01.L": "LeftThumbMetacarpal", "B-thumb02.L": "LeftThumbProximal", "B-thumb03.L": "LeftThumbDistal",
	"B-indexFinger01.L": "LeftIndexProximal", "B-indexFinger02.L": "LeftIndexIntermediate", "B-indexFinger03.L": "LeftIndexDistal",
	"B-middleFinger01.L": "LeftMiddleProximal", "B-middleFinger02.L": "LeftMiddleIntermediate", "B-middleFinger03.L": "LeftMiddleDistal",
	"B-ringFinger01.L": "LeftRingProximal", "B-ringFinger02.L": "LeftRingIntermediate", "B-ringFinger03.L": "LeftRingDistal",
	"B-pinky01.L": "LeftLittleProximal", "B-pinky02.L": "LeftLittleIntermediate", "B-pinky03.L": "LeftLittleDistal",
	"B-thumb01.R": "RightThumbMetacarpal", "B-thumb02.R": "RightThumbProximal", "B-thumb03.R": "RightThumbDistal",
	"B-indexFinger01.R": "RightIndexProximal", "B-indexFinger02.R": "RightIndexIntermediate", "B-indexFinger03.R": "RightIndexDistal",
	"B-middleFinger01.R": "RightMiddleProximal", "B-middleFinger02.R": "RightMiddleIntermediate", "B-middleFinger03.R": "RightMiddleDistal",
	"B-ringFinger01.R": "RightRingProximal", "B-ringFinger02.R": "RightRingIntermediate", "B-ringFinger03.R": "RightRingDistal",
	"B-pinky01.R": "RightLittleProximal", "B-pinky02.R": "RightLittleIntermediate", "B-pinky03.R": "RightLittleDistal",
}

var _skeleton: Skeleton3D
var _bone_names: Array = []

func _run():
	print("=== 開始建立移動動畫庫 ===\n")
	
	# 載入目標骨架
	if not _load_skeleton():
		push_error("無法載入目標骨架")
		return
	
	print("目標骨架骨骼數量: ", _bone_names.size())
	
	# 建立動畫庫
	var lib = AnimationLibrary.new()
	var total_anims = 0
	
	for folder in ANIM_FOLDERS.keys():
		var folder_path = HUMAN_ANIM_BASE + folder + "/"
		var global_path = ProjectSettings.globalize_path(folder_path)
		
		if not DirAccess.dir_exists_absolute(global_path):
			print("跳過不存在的資料夾: ", folder)
			continue
		
		print("\n處理: ", folder)
		var count = _process_folder(folder_path, lib)
		total_anims += count
		print("  載入了 %d 個動畫" % count)
	
	# 儲存動畫庫
	var err = ResourceSaver.save(lib, OUTPUT_PATH)
	if err == OK:
		print("\n=== 完成！ ===")
		print("共 %d 個動畫已儲存到: %s" % [total_anims, OUTPUT_PATH])
		print("\n動畫列表:")
		for anim_name in lib.get_animation_list():
			print("  - ", anim_name)
	else:
		push_error("儲存失敗，錯誤碼: " + str(err))

func _load_skeleton() -> bool:
	# 嘗試從場景中讀取骨架
	var tree = get_editor_interface().get_edited_scene_root()
	if tree:
		_skeleton = _find_skeleton(tree)
		if _skeleton:
			for i in range(_skeleton.get_bone_count()):
				_bone_names.append(_skeleton.get_bone_name(i))
			return true
	
	# 嘗試從 Mannequin FBX 載入
	var scene = load(SKELETON_PATH) as PackedScene
	if scene:
		var inst = scene.instantiate()
		_skeleton = _find_skeleton(inst)
		if _skeleton:
			for i in range(_skeleton.get_bone_count()):
				_bone_names.append(_skeleton.get_bone_name(i))
			inst.queue_free()
			return true
		inst.queue_free()
	
	return false

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null

func _process_folder(folder_path: String, lib: AnimationLibrary) -> int:
	var count = 0
	var dir = DirAccess.open(folder_path)
	if not dir:
		return 0
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		# 跳過 RootMotion 子資料夾
		if dir.current_is_dir() and file_name == "RootMotion":
			file_name = dir.get_next()
			continue
		
		# 跳過子資料夾、Root Motion 版本和非 FBX 檔案
		if not dir.current_is_dir() and file_name.ends_with(".fbx") and not "[RM]" in file_name:
			var anim = _extract_animation(folder_path + file_name)
			if anim:
				# 使用簡化的動畫名稱
				var anim_name = _simplify_name(file_name)
				lib.add_animation(anim_name, anim)
				count += 1
		file_name = dir.get_next()
	
	return count

func _simplify_name(file_name: String) -> String:
	# HumanM@Walk01_Forward.fbx -> Walk_Forward
	# HumanM@Idle01.fbx -> Idle
	var name = file_name.get_basename() # 移除 .fbx
	
	# 移除 HumanM@ 前綴
	if name.begins_with("HumanM@"):
		name = name.substr(7)
	
	# 簡化數字後綴
	# Walk01_Forward -> Walk_Forward
	# Idle01 -> Idle
	name = name.replace("01_", "_")
	name = name.replace("01-", "_")
	if name.ends_with("01"):
		name = name.substr(0, name.length() - 2)
	if name.ends_with("02"):
		name = name.substr(0, name.length() - 2)
	
	# 處理 Jump 動畫特殊格式
	# "Jump - Begin" -> "Jump_Begin"
	name = name.replace(" - ", "_")
	name = name.replace(" ", "_")
	
	return name

func _extract_animation(fbx_path: String) -> Animation:
	var scene = load(fbx_path) as PackedScene
	if not scene:
		return null
	
	var inst = scene.instantiate()
	var anim_player = _find_animation_player(inst)
	
	if not anim_player:
		inst.queue_free()
		return null
	
	var anim_list = anim_player.get_animation_list()
	if anim_list.size() == 0:
		inst.queue_free()
		return null
	
	# 取得第一個動畫並複製
	var anim = anim_player.get_animation(anim_list[0]).duplicate()
	
	# 修正骨骼軌道
	_fix_animation_tracks(anim)
	
	# 設定循環模式
	var name_lower = fbx_path.to_lower()
	if "idle" in name_lower or "walk" in name_lower or "run" in name_lower or "sprint" in name_lower or "loop" in name_lower:
		anim.loop_mode = Animation.LOOP_LINEAR
	else:
		anim.loop_mode = Animation.LOOP_NONE
	
	inst.queue_free()
	return anim

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _fix_animation_tracks(anim: Animation):
	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		if not ":" in path_str:
			continue
		
		var parts = path_str.split(":")
		var bone_name = parts[1]
		
		# 查找映射
		if BONE_MAP.has(bone_name):
			var mapped = BONE_MAP[bone_name]
			if mapped == "":
				# 忽略的骨骼
				anim.track_set_enabled(i, false)
				continue
			
			# 檢查目標骨架是否有此骨骼
			if mapped in _bone_names:
				var new_path = "GeneralSkeleton:" + mapped
				anim.track_set_path(i, NodePath(new_path))
			elif ("mixamorig:" + mapped) in _bone_names:
				var new_path = "GeneralSkeleton:mixamorig:" + mapped
				anim.track_set_path(i, NodePath(new_path))
			else:
				anim.track_set_enabled(i, false)
		elif bone_name in _bone_names:
			# 直接匹配
			var new_path = "GeneralSkeleton:" + bone_name
			anim.track_set_path(i, NodePath(new_path))
		else:
			# 無法映射，禁用軌道
			anim.track_set_enabled(i, false)
