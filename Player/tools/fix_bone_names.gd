@tool
extends EditorScript

## 修復 Mixamo 動畫骨骼名稱映射
## 將 mixamorig1_* 轉換為 Hips, Spine 等標準名稱

const LIB_PATH = "res://Player/animations/movement.res"

# 骨架節點名稱重映射：動畫中的名稱 -> 場景中的實際名稱
# Mixamo/通用導出使用 "Skeleton3D"，但 Human.fbx 使用 "GeneralSkeleton"
const SKELETON_PATH_REMAP: Dictionary = {
	"Skeleton3D": "GeneralSkeleton",
}

# 要修復的動畫列表 (所有攀爬動畫)
const ANIMS_TO_FIX = [
	"Breathing_Idle",
	"Run_To_Stop_Alt",
	"Shimmy_Left",
	"Shimmy_Right",
	"Hanging_Idle",
	"Hang_To_Crouch",
	"Hang_Drop",
	"Braced_Hang_Left",
	"Braced_Hang_Right",
	"Free_Hang_Hop_Left",
	"Free_Hang_Hop_Right"
]

# 骨骼名稱映射：Mixamo 名稱 -> 骨架實際名稱 (Unity Humanoid)
const BONE_REMAP: Dictionary = {
	# ===== 主要骨骼 =====
	# Spine 系列
	"Spine1": "Chest",
	"Spine2": "UpperChest",
	
	# 腿部
	"LeftUpLeg": "LeftUpperLeg",
	"RightUpLeg": "RightUpperLeg",
	"LeftLeg": "LeftLowerLeg",
	"RightLeg": "RightLowerLeg",
	"LeftToeBase": "LeftToes",
	"RightToeBase": "RightToes",
	
	# 手臂
	"LeftArm": "LeftUpperArm",
	"RightArm": "RightUpperArm",
	"LeftForeArm": "LeftLowerArm",
	"RightForeArm": "RightLowerArm",
	
	# ===== 左手手指 =====
	"LeftHandThumb1": "LeftThumbProximal",
	"LeftHandThumb2": "LeftThumbDistal",
	"LeftHandThumb3": "LeftThumbMetacarpal",
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
	
	# ===== 右手手指 =====
	"RightHandThumb1": "RightThumbProximal",
	"RightHandThumb2": "RightThumbDistal",
	"RightHandThumb3": "RightThumbMetacarpal",
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
	print("\n=== Fixing Bone Names in Animations ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	var total_fixed = 0
	
	for anim_name in ANIMS_TO_FIX:
		if not lib.has_animation(anim_name):
			print("SKIP: '%s' not found" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var fixed_count = _remap_animation_tracks(anim, anim_name)
		total_fixed += fixed_count
		print("Fixed %d tracks in '%s'" % [fixed_count, anim_name])
	
	if total_fixed > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\nSUCCESS: Saved to %s (total %d tracks fixed)" % [LIB_PATH, total_fixed])
		else:
			print("\nERROR saving: ", err)
	else:
		print("\nNo tracks needed fixing")
	
	print("\n=== Done ===")

func _remap_animation_tracks(anim: Animation, _anim_name: String) -> int:
	var fixed = 0
	
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		var modified = false
		
		# 第一步：重映射骨架節點路徑 (Skeleton3D -> GeneralSkeleton)
		for old_skel in SKELETON_PATH_REMAP.keys():
			if old_skel in path_str:
				path_str = path_str.replace(old_skel, SKELETON_PATH_REMAP[old_skel])
				modified = true
				break
		
		# 第二步：重映射骨骼名稱
		for old_bone in BONE_REMAP.keys():
			if old_bone in path_str:
				path_str = path_str.replace(old_bone, BONE_REMAP[old_bone])
				modified = true
				break
		
		# 若有修改則應用
		if modified:
			anim.track_set_path(i, NodePath(path_str))
			fixed += 1
	
	return fixed
