@tool
extends EditorScript

# 修復 Walk 動畫的骨骼映射問題
# 重新從 FBX 提取並正確映射

const HUMAN_ANIM_BASE = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/"
const OUTPUT_PATH = "res://Player/assets/characters/player/motion/movement_animations.res"

# 完整的骨骼映射表（包含所有可能的變體）
const BONE_MAP = {
	"B-root": "Hips",
	"B-hips": "Hips",
	"B-spine": "Spine",
	"B-chest": "Spine1",
	"B-upperChest": "Spine2",
	"B-spineProxy": "",
	"B-neck": "Neck",
	"B-head": "Head",
	"B-jaw": "",
	
	# 左臂
	"B-shoulder.L": "LeftShoulder",
	"B-upperArm.L": "LeftArm",
	"B-forearm.L": "LeftForeArm",
	"B-hand.L": "LeftHand",
	"B-handProp.L": "",
	
	# 右臂
	"B-shoulder.R": "RightShoulder",
	"B-upperArm.R": "RightArm",
	"B-forearm.R": "RightForeArm",
	"B-hand.R": "RightHand",
	"B-handProp.R": "",
	
	# 左腿
	"B-thigh.L": "LeftUpLeg",
	"B-shin.L": "LeftLeg",
	"B-foot.L": "LeftFoot",
	"B-toe.L": "LeftToeBase",
	
	# 右腿
	"B-thigh.R": "RightUpLeg",
	"B-shin.R": "RightLeg",
	"B-foot.R": "RightFoot",
	"B-toe.R": "RightToeBase",
	
	# 左手手指
	"B-thumb01.L": "LeftHandThumb1", "B-thumb02.L": "LeftHandThumb2", "B-thumb03.L": "LeftHandThumb3",
	"B-indexFinger01.L": "LeftHandIndex1", "B-indexFinger02.L": "LeftHandIndex2", "B-indexFinger03.L": "LeftHandIndex3",
	"B-middleFinger01.L": "LeftHandMiddle1", "B-middleFinger02.L": "LeftHandMiddle2", "B-middleFinger03.L": "LeftHandMiddle3",
	"B-ringFinger01.L": "LeftHandRing1", "B-ringFinger02.L": "LeftHandRing2", "B-ringFinger03.L": "LeftHandRing3",
	"B-pinky01.L": "LeftHandPinky1", "B-pinky02.L": "LeftHandPinky2", "B-pinky03.L": "LeftHandPinky3",
	
	# 右手手指
	"B-thumb01.R": "RightHandThumb1", "B-thumb02.R": "RightHandThumb2", "B-thumb03.R": "RightHandThumb3",
	"B-indexFinger01.R": "RightHandIndex1", "B-indexFinger02.R": "RightHandIndex2", "B-indexFinger03.R": "RightHandIndex3",
	"B-middleFinger01.R": "RightHandMiddle1", "B-middleFinger02.R": "RightHandMiddle2", "B-middleFinger03.R": "RightHandMiddle3",
	"B-ringFinger01.R": "RightHandRing1", "B-ringFinger02.R": "RightHandRing2", "B-ringFinger03.R": "RightHandRing3",
	"B-pinky01.R": "RightHandPinky1", "B-pinky02.R": "RightHandPinky2", "B-pinky03.R": "RightHandPinky3",
}

var _skeleton: Skeleton3D
var _bone_names: Array = []

func _run():
	print("=== 修復 Walk 動畫骨骼映射 ===\n")
	
	# 載入骨架
	if not _load_skeleton():
		push_error("無法載入骨架")
		return
	
	print("目標骨架骨骼數: ", _bone_names.size())
	
	# 載入現有動畫庫
	var lib = load(OUTPUT_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入動畫庫")
		return
	
	# 重新處理所有 Walk 動畫
	var walk_anims = ["Walk_Forward", "Walk_Backward", "Walk_Left", "Walk_Right",
					  "Walk_ForwardLeft", "Walk_ForwardRight", "Walk_BackwardLeft", "Walk_BackwardRight"]
	
	var walk_files = {
		"Walk_Forward": "Movement/Walk/HumanM@Walk01_Forward.fbx",
		"Walk_Backward": "Movement/Walk/HumanM@Walk01_Backward.fbx",
		"Walk_Left": "Movement/Walk/HumanM@Walk01_Left.fbx",
		"Walk_Right": "Movement/Walk/HumanM@Walk01_Right.fbx",
		"Walk_ForwardLeft": "Movement/Walk/HumanM@Walk01_ForwardLeft.fbx",
		"Walk_ForwardRight": "Movement/Walk/HumanM@Walk01_ForwardRight.fbx",
		"Walk_BackwardLeft": "Movement/Walk/HumanM@Walk01_BackwardLeft.fbx",
		"Walk_BackwardRight": "Movement/Walk/HumanM@Walk01_BackwardRight.fbx",
	}
	
	var fixed_count = 0
	
	for anim_name in walk_anims:
		if not walk_files.has(anim_name):
			continue
		
		var fbx_path = HUMAN_ANIM_BASE + walk_files[anim_name]
		print("\n處理: ", anim_name)
		print("  從: ", fbx_path)
		
		var anim = _extract_and_fix_animation(fbx_path)
		if anim:
			# 替換庫中的動畫
			if lib.has_animation(anim_name):
				lib.remove_animation(anim_name)
			lib.add_animation(anim_name, anim)
			fixed_count += 1
			print("  ✓ 已修復並替換")
		else:
			print("  ✗ 無法載入")
	
	# 保存
	if fixed_count > 0:
		var err = ResourceSaver.save(lib, OUTPUT_PATH)
		if err == OK:
			print("\n=== 完成！ ===")
			print("已修復 %d 個 Walk 動畫" % fixed_count)
			print("動畫庫已更新: ", OUTPUT_PATH)
		else:
			push_error("保存失敗: " + str(err))
	else:
		print("\n沒有動畫需要修復")

func _load_skeleton() -> bool:
	var skel_path = "res://Player/assets/characters/player/Characters_Mannequin.fbx"
	var scene = load(skel_path) as PackedScene
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

func _extract_and_fix_animation(fbx_path: String) -> Animation:
	if not FileAccess.file_exists(fbx_path):
		return null
	
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
	
	# 複製動畫
	var anim = anim_player.get_animation(anim_list[0]).duplicate()
	
	print("  原始軌道數: ", anim.get_track_count())
	
	# 修正骨骼軌道 - 更嚴格的映射
	_fix_animation_tracks_strict(anim)
	
	# 設定循環
	anim.loop_mode = Animation.LOOP_LINEAR
	
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

func _fix_animation_tracks_strict(anim: Animation):
	var enabled_count = 0
	var disabled_count = 0
	var mapped_count = 0
	
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
			
			# 忽略的骨骼
			if mapped == "":
				anim.track_set_enabled(i, false)
				disabled_count += 1
				continue
			
			# 嘗試映射
			var found = false
			
			# 1. 直接匹配
			if mapped in _bone_names:
				anim.track_set_path(i, NodePath("GeneralSkeleton:"+ mapped))
				anim.track_set_enabled(i, true)
				enabled_count += 1
				mapped_count += 1
				found = true
			# 2. mixamorig 前綴
			elif ("mixamorig:" + mapped) in _bone_names:
				anim.track_set_path(i, NodePath("GeneralSkeleton:mixamorig:"+ mapped))
				anim.track_set_enabled(i, true)
				enabled_count += 1
				mapped_count += 1
				found = true
			
			if not found:
				# 無法映射，禁用但不刪除
				anim.track_set_enabled(i, false)
				disabled_count += 1
		else:
			# 沒有映射規則的骨骼，檢查是否直接存在
			if bone_name in _bone_names:
				anim.track_set_path(i, NodePath("GeneralSkeleton:"+ bone_name))
				anim.track_set_enabled(i, true)
				enabled_count += 1
			else:
				anim.track_set_enabled(i, false)
				disabled_count += 1
	
	print("  映射統計: 啟用=%d, 禁用=%d, 成功映射=%d" % [enabled_count, disabled_count, mapped_count])
