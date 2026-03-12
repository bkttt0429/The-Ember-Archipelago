@tool
extends EditorScript

## 分析 Stop_Walking 動畫的完整軌道結構

const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	print("\n=== Stop_Walking Complete Track Analysis ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load " + LIB_PATH)
		return
	
	var anim = lib.get_animation("Stop_Walking") as Animation
	if not anim:
		print("ERROR: Stop_Walking not found")
		return
	
	print("Duration: %.3f seconds (%.0f frames @ 30fps)" % [anim.length, anim.length * 30])
	print("Total Tracks: %d\n" % anim.get_track_count())
	
	# 統計各類型軌道
	var pos_count = 0
	var rot_count = 0
	var scale_count = 0
	
	# 顯示所有軌道
	print("=== All Tracks ===")
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		var track_type = anim.track_get_type(i)
		var key_count = anim.track_get_key_count(i)
		
		var type_name = "Unknown"
		match track_type:
			Animation.TYPE_POSITION_3D:
				type_name = "Pos"
				pos_count += 1
			Animation.TYPE_ROTATION_3D:
				type_name = "Rot"
				rot_count += 1
			Animation.TYPE_SCALE_3D:
				type_name = "Scale"
				scale_count += 1
		
		# 簡化路徑顯示
		var short_path = path.replace("Skeleton3D:", "")
		print("%02d: [%s] %s (%d keys)" % [i, type_name, short_path, key_count])
	
	print("\n=== Summary ===")
	print("Position tracks: %d" % pos_count)
	print("Rotation tracks: %d" % rot_count)
	print("Scale tracks: %d" % scale_count)
	
	# 分析腳部旋轉軌道（如果沒有位置軌道，旋轉可能包含步伐資訊）
	print("\n=== Foot Rotation Analysis ===")
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		var is_foot = "LeftFoot" in path or "RightFoot" in path
		
		if is_foot and anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			var key_count = anim.track_get_key_count(i)
			print("--- %s (%d keys) ---" % [path.replace("Skeleton3D:", ""), key_count])
			
			for k in key_count:
				var time = anim.track_get_key_time(i, k)
				var q = anim.track_get_key_value(i, k) as Quaternion
				var euler = q.get_euler()
				# 腳部抬起時 X 旋轉角度會變化
				print("  %.3fs: X=%.1f° Y=%.1f° Z=%.1f°" % [time, rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)])
	
	print("\n=== Done ===")
