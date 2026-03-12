@tool
extends EditorScript

## 修復 Breathing_Idle 動畫的骨骼名稱
## 將 mixamorig1_* 轉換為標準骨骼名稱

const LIB_PATH = "res://Player/animations/movement.res"

const BONE_REMAP: Dictionary = {
	"mixamorig1_Hips": "Hips",
	"mixamorig1_Spine": "Spine",
	"mixamorig1_Spine1": "Spine1",
	"mixamorig1_Spine2": "Spine2",
	"mixamorig1_Neck": "Neck",
	"mixamorig1_Head": "Head",
	"mixamorig1_LeftShoulder": "LeftShoulder",
	"mixamorig1_LeftArm": "LeftArm",
	"mixamorig1_LeftForeArm": "LeftForeArm",
	"mixamorig1_LeftHand": "LeftHand",
	"mixamorig1_RightShoulder": "RightShoulder",
	"mixamorig1_RightArm": "RightArm",
	"mixamorig1_RightForeArm": "RightForeArm",
	"mixamorig1_RightHand": "RightHand",
	"mixamorig1_LeftUpLeg": "LeftUpLeg",
	"mixamorig1_LeftLeg": "LeftLeg",
	"mixamorig1_LeftFoot": "LeftFoot",
	"mixamorig1_LeftToeBase": "LeftToeBase",
	"mixamorig1_RightUpLeg": "RightUpLeg",
	"mixamorig1_RightLeg": "RightLeg",
	"mixamorig1_RightFoot": "RightFoot",
	"mixamorig1_RightToeBase": "RightToeBase",
	# 手指
	"mixamorig1_LeftHandThumb1": "LeftHandThumb1",
	"mixamorig1_LeftHandThumb2": "LeftHandThumb2",
	"mixamorig1_LeftHandThumb3": "LeftHandThumb3",
	"mixamorig1_LeftHandIndex1": "LeftHandIndex1",
	"mixamorig1_LeftHandIndex2": "LeftHandIndex2",
	"mixamorig1_LeftHandIndex3": "LeftHandIndex3",
	"mixamorig1_LeftHandMiddle1": "LeftHandMiddle1",
	"mixamorig1_LeftHandMiddle2": "LeftHandMiddle2",
	"mixamorig1_LeftHandMiddle3": "LeftHandMiddle3",
	"mixamorig1_LeftHandRing1": "LeftHandRing1",
	"mixamorig1_LeftHandRing2": "LeftHandRing2",
	"mixamorig1_LeftHandRing3": "LeftHandRing3",
	"mixamorig1_LeftHandPinky1": "LeftHandPinky1",
	"mixamorig1_LeftHandPinky2": "LeftHandPinky2",
	"mixamorig1_LeftHandPinky3": "LeftHandPinky3",
	"mixamorig1_RightHandThumb1": "RightHandThumb1",
	"mixamorig1_RightHandThumb2": "RightHandThumb2",
	"mixamorig1_RightHandThumb3": "RightHandThumb3",
	"mixamorig1_RightHandIndex1": "RightHandIndex1",
	"mixamorig1_RightHandIndex2": "RightHandIndex2",
	"mixamorig1_RightHandIndex3": "RightHandIndex3",
	"mixamorig1_RightHandMiddle1": "RightHandMiddle1",
	"mixamorig1_RightHandMiddle2": "RightHandMiddle2",
	"mixamorig1_RightHandMiddle3": "RightHandMiddle3",
	"mixamorig1_RightHandRing1": "RightHandRing1",
	"mixamorig1_RightHandRing2": "RightHandRing2",
	"mixamorig1_RightHandRing3": "RightHandRing3",
	"mixamorig1_RightHandPinky1": "RightHandPinky1",
	"mixamorig1_RightHandPinky2": "RightHandPinky2",
	"mixamorig1_RightHandPinky3": "RightHandPinky3",
}

func _run() -> void:
	print("\n=== Fixing Breathing_Idle Bone Names ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library")
		return
	
	if not lib.has_animation("Breathing_Idle"):
		print("ERROR: Breathing_Idle not found")
		return
	
	var anim = lib.get_animation("Breathing_Idle")
	print("Animation: Breathing_Idle (%d tracks)" % anim.get_track_count())
	
	var fixed = 0
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		for old_bone in BONE_REMAP.keys():
			if old_bone in path_str:
				var new_path = path_str.replace(old_bone, BONE_REMAP[old_bone])
				anim.track_set_path(i, NodePath(new_path))
				fixed += 1
				break
	
	print("Fixed %d tracks" % fixed)
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\nSUCCESS: Breathing_Idle bone names fixed!")
	else:
		print("\nERROR saving: ", err)
