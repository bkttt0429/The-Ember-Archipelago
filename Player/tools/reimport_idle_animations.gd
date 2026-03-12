@tool
extends EditorScript

## 重新匯入 Idle 資料夾的動畫（排除 Breathing Idle）
## 同時自動修復骨骼名稱映射

const FBX_DIR = "res://Player/assets/characters/player/motion/mx/Idle/"
const LIB_PATH = "res://Player/animations/movement.res"

# FBX 檔案名 -> 動畫庫中的名稱（排除 Breathing Idle）
const ANIM_MAPPING = {
	"Run To Stop.fbx": "Run_To_Stop",
	"Run To Stop (1).fbx": "Run_To_Stop_Alt",
	"Stop Walking.fbx": "Stop_Walking",
}

# 骨骼名稱映射：mixamorig1_ 前綴 -> 標準名稱
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
	print("\n=== Re-importing Idle Animations (excluding Breathing Idle) ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	var replaced_count = 0
	var added_count = 0
	
	for fbx_file in ANIM_MAPPING.keys():
		var fbx_path = FBX_DIR + fbx_file
		var target_name = ANIM_MAPPING[fbx_file]
		
		# 刪除舊動畫（如果存在）
		if lib.has_animation(target_name):
			lib.remove_animation(target_name)
			print("REMOVED: '%s'" % target_name)
			replaced_count += 1
		
		# 加載 FBX 場景
		var fbx_scene = load(fbx_path)
		if not fbx_scene:
			print("ERROR: Cannot load FBX: " + fbx_path)
			continue
		
		var instance = fbx_scene.instantiate()
		var anim_player: AnimationPlayer = null
		
		for child in instance.get_children():
			if child is AnimationPlayer:
				anim_player = child
				break
		
		if not anim_player:
			print("ERROR: No AnimationPlayer in FBX: " + fbx_file)
			instance.queue_free()
			continue
		
		# 獲取動畫
		var anim_list = anim_player.get_animation_list()
		if anim_list.size() > 0:
			var anim = anim_player.get_animation(anim_list[0]).duplicate()
			
			# 修復骨骼名稱
			var fixed_tracks = _remap_animation_tracks(anim)
			
			lib.add_animation(target_name, anim)
			print("ADDED: '%s' (from %s, length: %.2fs, fixed %d tracks)" % [target_name, fbx_file, anim.length, fixed_tracks])
			added_count += 1
		else:
			print("ERROR: No animations found in: " + fbx_file)
		
		instance.queue_free()
	
	# 保存
	if added_count > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\nSUCCESS: Saved %d animations to %s (replaced: %d)" % [added_count, LIB_PATH, replaced_count])
		else:
			print("\nERROR saving: ", err)
	else:
		print("\nNo animations added")
	
	print("\n=== Done ===")

func _remap_animation_tracks(anim: Animation) -> int:
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
	
	return fixed
