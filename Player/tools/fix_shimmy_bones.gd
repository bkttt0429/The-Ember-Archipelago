@tool
extends EditorScript

## 修復 Shimmy 動畫骨骼名稱
## 將 mixamorig1_* 轉換為 Unity Humanoid 格式
## 使用方法：在 Godot 中開啟此腳本，按 Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

const ANIMS_TO_FIX = ["Shimmy_Left", "Shimmy_Right"]

# 骨骼名稱映射：Mixamo -> Unity Humanoid
const BONE_MAP = {
	# 前綴會被去除，然後應用這些映射
	"Hips": "Hips",
	"Spine": "Spine",
	"Spine1": "Chest",
	"Spine2": "UpperChest",
	"Neck": "Neck",
	"Head": "Head",
	
	# 腿
	"LeftUpLeg": "LeftUpperLeg",
	"RightUpLeg": "RightUpperLeg",
	"LeftLeg": "LeftLowerLeg",
	"RightLeg": "RightLowerLeg",
	"LeftFoot": "LeftFoot",
	"RightFoot": "RightFoot",
	"LeftToeBase": "LeftToes",
	"RightToeBase": "RightToes",
	
	# 肩膀和手臂
	"LeftShoulder": "LeftShoulder",
	"RightShoulder": "RightShoulder",
	"LeftArm": "LeftUpperArm",
	"RightArm": "RightUpperArm",
	"LeftForeArm": "LeftLowerArm",
	"RightForeArm": "RightLowerArm",
	"LeftHand": "LeftHand",
	"RightHand": "RightHand",
	
	# 手指（如果有）
	"LeftHandThumb1": "LeftThumbProximal",
	"LeftHandThumb2": "LeftThumbIntermediate",
	"LeftHandThumb3": "LeftThumbDistal",
	"LeftHandIndex1": "LeftIndexProximal",
	"LeftHandIndex2": "LeftIndexIntermediate",
	"LeftHandIndex3": "LeftIndexDistal",
	"LeftHandMiddle1": "LeftMiddleProximal",
	"LeftHandMiddle2": "LeftMiddleIntermediate",
	"LeftHandMiddle3": "LeftMiddleDistal",
	"LeftHandRing1": "LeftRingProximal",
	"LeftHandRing2": "LeftRingIntermediate",
	"LeftHandRing3": "LeftRingDistal",
	"LeftHandPinky1": "LeftLittleProximal",
	"LeftHandPinky2": "LeftLittleIntermediate",
	"LeftHandPinky3": "LeftLittleDistal",
	
	"RightHandThumb1": "RightThumbProximal",
	"RightHandThumb2": "RightThumbIntermediate",
	"RightHandThumb3": "RightThumbDistal",
	"RightHandIndex1": "RightIndexProximal",
	"RightHandIndex2": "RightIndexIntermediate",
	"RightHandIndex3": "RightIndexDistal",
	"RightHandMiddle1": "RightMiddleProximal",
	"RightHandMiddle2": "RightMiddleIntermediate",
	"RightHandMiddle3": "RightMiddleDistal",
	"RightHandRing1": "RightRingProximal",
	"RightHandRing2": "RightRingIntermediate",
	"RightHandRing3": "RightRingDistal",
	"RightHandPinky1": "RightLittleProximal",
	"RightHandPinky2": "RightLittleIntermediate",
	"RightHandPinky3": "RightLittleDistal",
}

func _run() -> void:
	print("\n=== 修復 Shimmy 骨骼名稱 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + LIB_PATH)
		return
	
	var total_fixed = 0
	
	for anim_name in ANIMS_TO_FIX:
		if not lib.has_animation(anim_name):
			print("⚠️ '%s' 不存在" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var fixed = _fix_bone_names(anim)
		total_fixed += fixed
		print("✓ %s: 修正了 %d 軌道" % [anim_name, fixed])
	
	if total_fixed > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\n✅ 已儲存!")
		else:
			push_error("儲存失敗")
	
	print("\n=== 完成 ===")

func _fix_bone_names(anim: Animation) -> int:
	var fixed = 0
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		
		# 解析路徑
		if not ":" in path:
			continue
		
		var parts = path.split(":")
		var node_part = parts[0] # %GeneralSkeleton
		var bone_part = parts[1] # mixamorig1_Hips
		
		# 去除 mixamorig1_ 前綴
		var clean_bone = bone_part
		if bone_part.begins_with("mixamorig1_"):
			clean_bone = bone_part.substr(len("mixamorig1_"))
		elif bone_part.begins_with("mixamorig_"):
			clean_bone = bone_part.substr(len("mixamorig_"))
		
		# 應用映射
		var new_bone = clean_bone
		if BONE_MAP.has(clean_bone):
			new_bone = BONE_MAP[clean_bone]
		
		# 構建新路徑
		var new_path = node_part + ":" + new_bone
		
		if new_path != path:
			anim.track_set_path(i, NodePath(new_path))
			fixed += 1
	
	return fixed
