@tool
extends EditorScript

## 從 Stop_Walking 動畫生成 4 方向版本
## 透過旋轉 Hips 骨骼的 rotation track 來模擬不同方向的停止

const LIB_PATH = "res://Player/animations/movement.res"
const SOURCE_ANIM = "Stop_Walking"

# 輸出動畫名稱和對應的 Hips Y 旋轉角度（弧度）
const DIRECTIONS = {
	"Stop_Walking_Forward": 0.0, # 原始方向
	"Stop_Walking_Left": PI / 2, # 左轉 90°
	"Stop_Walking_Right": - PI / 2, # 右轉 90°
	"Stop_Walking_Backward": PI, # 後轉 180°
}

func _run() -> void:
	print("\n=== Generating 4-Directional Stop_Walking Animations ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	if not lib.has_animation(SOURCE_ANIM):
		print("ERROR: Source animation '%s' not found" % SOURCE_ANIM)
		return
	
	var source = lib.get_animation(SOURCE_ANIM)
	print("Source: %s (%.2fs, %d tracks)" % [SOURCE_ANIM, source.length, source.get_track_count()])
	
	var created = 0
	
	for anim_name in DIRECTIONS.keys():
		var rotation_offset = DIRECTIONS[anim_name]
		
		# Forward 版本（複製原始動畫）
		if anim_name == "Stop_Walking_Forward":
			if not lib.has_animation(anim_name):
				var copy = source.duplicate()
				lib.add_animation(anim_name, copy)
				print("CREATED: %s (copy of original)" % anim_name)
				created += 1
			else:
				print("SKIP: %s (already exists)" % anim_name)
			continue
		
		# 刪除舊版本（如果存在）
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
			print("REMOVED: old %s" % anim_name)
		
		# 複製並修改
		var new_anim = source.duplicate() as Animation
		var modified = _rotate_hips_tracks(new_anim, rotation_offset)
		
		lib.add_animation(anim_name, new_anim)
		print("CREATED: %s (rotated %.0f°, modified %d tracks)" % [anim_name, rad_to_deg(rotation_offset), modified])
		created += 1
	
	# 保存
	if created > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\nSUCCESS: Created %d directional Stop_Walking animations" % created)
		else:
			print("\nERROR saving: ", err)
	
	print("\n=== Done ===")

## 旋轉動畫中 Hips 骨骼的 rotation 軌道
func _rotate_hips_tracks(anim: Animation, y_rotation: float) -> int:
	var modified = 0
	
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# 只處理 Hips 的旋轉軌道
		if not ("Hips" in path_str):
			continue
		
		var track_type = anim.track_get_type(i)
		
		# 處理 Rotation3D 軌道
		if track_type == Animation.TYPE_ROTATION_3D:
			var key_count = anim.track_get_key_count(i)
			for k in key_count:
				var quat = anim.track_get_key_value(i, k) as Quaternion
				# 建立 Y 軸旋轉的四元數
				var y_rot_quat = Quaternion(Vector3.UP, y_rotation)
				# 應用旋轉
				var new_quat = y_rot_quat * quat
				anim.track_set_key_value(i, k, new_quat)
			modified += 1
			print("  Rotated: %s (%d keys)" % [path_str, key_count])
	
	return modified
