@tool
extends EditorScript

## 分析上樓梯動畫的步數結構 — 檢查 Hips Y 曲線找出幾個 step cycle

func _run() -> void:
	var fbx_path = "res://Player/assets/characters/player/motion/mx/stairs/Walking Up The Stairs.fbx"
	var fbx_scene = load(fbx_path) as PackedScene
	if not fbx_scene:
		print("ERROR: Cannot load FBX: %s" % fbx_path)
		return

	var inst = fbx_scene.instantiate()
	var ap: AnimationPlayer = null
	for child in inst.get_children():
		if child is AnimationPlayer:
			ap = child
			break
		for gc in child.get_children():
			if gc is AnimationPlayer:
				ap = gc
				break
		if ap:
			break

	if not ap:
		print("ERROR: No AnimationPlayer found")
		inst.queue_free()
		return

	var anim: Animation = null
	for lib_name in ap.get_animation_library_list():
		var lib = ap.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			anim = lib.get_animation(an)
			break
		if anim:
			break

	if not anim:
		print("ERROR: No animation found")
		inst.queue_free()
		return

	print("=".repeat(60))
	print("Animation: Walking Up The Stairs")
	print("Duration: %.4fs" % anim.length)
	print("Track count: %d" % anim.get_track_count())
	print("=".repeat(60))

	# 分析每條軌道
	for i in range(anim.get_track_count()):
		var path = str(anim.track_get_path(i))
		var type_id = anim.track_get_type(i)
		var key_count = anim.track_get_key_count(i)
		
		var colon = path.rfind(":")
		var bone_name = path.substr(colon + 1) if colon >= 0 else path
		
		# 只顯示 Hips 位置軌（分析步數）
		if bone_name == "Hips" and type_id == Animation.TYPE_POSITION_3D:
			print("\n--- HIPS Position Track (%d keys) ---" % key_count)
			var prev_y: float = 0.0
			var step_count: int = 0
			var going_up: bool = true
			
			for k in range(key_count):
				var t: float = anim.track_get_key_time(i, k)
				var v: Vector3 = anim.track_get_key_value(i, k)
				
				# 偵測方向變化（上→下 = 一個 step peak）
				if k > 0:
					if going_up and v.y < prev_y - 0.005:
						going_up = false
						step_count += 1
						print("  *** STEP PEAK #%d at t=%.4f Y=%.4f ***" % [step_count, t, prev_y])
					elif not going_up and v.y > prev_y + 0.005:
						going_up = true
				
				# 印出每個 keyframe
				print("  [%3d] t=%.4f  Y=%.4f  Z=%.4f  (dY=%.4f)" % [k, t, v.y, v.z, v.y - prev_y if k > 0 else 0.0])
				prev_y = v.y
			
			print("\nTotal detected step peaks: %d" % step_count)
			print("Total Y displacement: %.4f" % (anim.track_get_key_value(i, key_count - 1).y - anim.track_get_key_value(i, 0).y))
			print("Total Z displacement: %.4f" % (anim.track_get_key_value(i, key_count - 1).z - anim.track_get_key_value(i, 0).z))

		# 也顯示腿的旋轉軌（分析左右腳交替）
		if bone_name in ["LeftUpLeg", "RightUpLeg"] and type_id == Animation.TYPE_ROTATION_3D:
			print("\n--- %s Rotation Track (%d keys, duration=%.4fs) ---" % [bone_name, key_count, anim.length])
			# 只顯示 X rotation（knee lift）的幾個關鍵點
			var samples = [0, key_count / 6, key_count / 3, key_count / 2, key_count * 2 / 3, key_count * 5 / 6, key_count - 1]
			for sk in samples:
				var ki = mini(int(sk), key_count - 1)
				var t: float = anim.track_get_key_time(i, ki)
				var q: Quaternion = anim.track_get_key_value(i, ki) as Quaternion
				# Quaternion → Euler to see X rotation (knee lift)
				var euler = q.get_euler()
				print("  [%3d] t=%.4f  euler_x=%.1f° euler_y=%.1f° euler_z=%.1f°" % [ki, t, rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)])

	inst.queue_free()
	print("\n=== Analysis complete ===")
