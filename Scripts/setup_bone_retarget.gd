@tool
extends EditorScript

# 批量更新 Human Animations FBX 的骨骼重定向設置
# 運行方式：在 Godot 編輯器中 File > Run

const HUMAN_ANIM_BASE = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/"
const SUBFOLDERS = ["Movement/Walk", "Movement/Run", "Movement/Jump", "Movement/Sprint", "Idles"]

# Human Animations FBX 骨骼名稱 -> Godot Mannequin 骨骼名稱
const BONE_MAP = {
	"Hips": "Hips",
	"Spine": "Spine",
	"Spine1": "Spine1",
	"Spine2": "Spine2",
	"Neck": "Neck",
	"Head": "Head",
	"LeftShoulder": "LeftShoulder",
	"LeftArm": "LeftArm",
	"LeftForeArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder",
	"RightArm": "RightArm",
	"RightForeArm": "RightForeArm",
	"RightHand": "RightHand",
	"LeftUpLeg": "LeftUpLeg",
	"LeftLeg": "LeftLeg",
	"LeftFoot": "LeftFoot",
	"LeftToeBase": "LeftToeBase",
	"RightUpLeg": "RightUpLeg",
	"RightLeg": "RightLeg",
	"RightFoot": "RightFoot",
	"RightToeBase": "RightToeBase",
	# 指骨（可選，如果模型有的話）
	"LeftHandThumb1": "LeftHandThumb1",
	"LeftHandThumb2": "LeftHandThumb2",
	"LeftHandThumb3": "LeftHandThumb3",
	"LeftHandIndex1": "LeftHandIndex1",
	"LeftHandIndex2": "LeftHandIndex2",
	"LeftHandIndex3": "LeftHandIndex3",
	"LeftHandMiddle1": "LeftHandMiddle1",
	"LeftHandMiddle2": "LeftHandMiddle2",
	"LeftHandMiddle3": "LeftHandMiddle3",
	"LeftHandRing1": "LeftHandRing1",
	"LeftHandRing2": "LeftHandRing2",
	"LeftHandRing3": "LeftHandRing3",
	"LeftHandPinky1": "LeftHandPinky1",
	"LeftHandPinky2": "LeftHandPinky2",
	"LeftHandPinky3": "LeftHandPinky3",
	"RightHandThumb1": "RightHandThumb1",
	"RightHandThumb2": "RightHandThumb2",
	"RightHandThumb3": "RightHandThumb3",
	"RightHandIndex1": "RightHandIndex1",
	"RightHandIndex2": "RightHandIndex2",
	"RightHandIndex3": "RightHandIndex3",
	"RightHandMiddle1": "RightHandMiddle1",
	"RightHandMiddle2": "RightHandMiddle2",
	"RightHandMiddle3": "RightHandMiddle3",
	"RightHandRing1": "RightHandRing1",
	"RightHandRing2": "RightHandRing2",
	"RightHandRing3": "RightHandRing3",
	"RightHandPinky1": "RightHandPinky1",
	"RightHandPinky2": "RightHandPinky2",
	"RightHandPinky3": "RightHandPinky3",
}

func _run():
	print("=== 開始批量設置 FBX 骨骼重定向 ===")
	
	var total_files = 0
	var processed_files = 0
	
	for subfolder in SUBFOLDERS:
		var folder_path = HUMAN_ANIM_BASE + subfolder + "/"
		var global_path = ProjectSettings.globalize_path(folder_path)
		
		if not DirAccess.dir_exists_absolute(global_path):
			print("  跳過不存在的資料夾: ", folder_path)
			continue
		
		print("\n處理資料夾: ", subfolder)
		var dir = DirAccess.open(folder_path)
		if not dir:
			continue
		
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".fbx") and not "[RM]" in file_name:
				total_files += 1
				var result = _process_fbx_file(folder_path + file_name)
				if result:
					processed_files += 1
			file_name = dir.get_next()
	
	print("\n=== 完成！ ===")
	print("處理了 %d / %d 個 FBX 檔案" % [processed_files, total_files])
	print("請執行 Project > Reload Current Project 以重新導入資源")

func _process_fbx_file(fbx_path: String) -> bool:
	var import_path = fbx_path + ".import"
	var global_import = ProjectSettings.globalize_path(import_path)
	
	if not FileAccess.file_exists(import_path):
		print("  警告：找不到 .import 檔案: ", fbx_path.get_file())
		return false
	
	# 讀取現有 import 設置
	var file = FileAccess.open(import_path, FileAccess.READ)
	if not file:
		return false
	
	var content = file.get_as_text()
	file.close()
	
	# 解析並更新 _subresources 區塊
	var new_content = _update_import_content(content, fbx_path.get_file())
	
	# 寫回檔案
	file = FileAccess.open(import_path, FileAccess.WRITE)
	if not file:
		return false
	
	file.store_string(new_content)
	file.close()
	
	print("  ✓ ", fbx_path.get_file())
	return true

func _update_import_content(content: String, file_name: String) -> String:
	# 檢查是否已經有骨骼重定向設置
	if "retargeting" in content:
		return content # 已經設置過了
	
	# 找到 _subresources={} 並替換
	var subres_pattern = "_subresources={}"
	if subres_pattern in content:
		var bone_map_str = _generate_bone_map_string()
		var new_subres = """_subresources={
"animations": {
"*": {
"settings/retarget": true
}
},
"nodes": {
"PATH:AnimationPlayer": {
"retarget/bone_map": %s
}
}
}""" % bone_map_str
		content = content.replace(subres_pattern, new_subres)
	
	return content

func _generate_bone_map_string() -> String:
	# Godot 的 BoneMap 格式
	var entries = []
	for src in BONE_MAP:
		entries.append('"%s": "%s"' % [src, BONE_MAP[src]])
	return "{" + ", ".join(entries) + "}"
