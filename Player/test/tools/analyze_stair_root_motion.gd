extends MainLoop

## 分析樓梯 FBX 動畫的 Root Motion 數據（CLI 版本）
## 用法: godot --headless --script res://Player/test/tools/analyze_stair_root_motion.gd

const STAIR_ANIM_DIR = "res://Player/assets/characters/player/motion/mx/stairs/"

var _done := false

func _initialize() -> void:
	print("\n" + "=" * 70)
	print("  樓梯動畫 Root Motion 分析")
	print("=" * 70)
	
	var files = [
		"Ascending Stairs.fbx",
		"Ascending Stairs inplace.fbx",
		"Descending Stairs.fbx",
		"Running Up Stairs.fbx",
	]
	
	for file_name in files:
		var path = STAIR_ANIM_DIR + file_name
		print("\n" + "-" * 60)
		print("  %s" % file_name)
		print("-" * 60)
		_analyze_fbx(path)
	
	print("\n" + "=" * 70)
	print("  分析完成")
	print("=" * 70)
	_done = true

func _process(_delta: float) -> bool:
	return _done

func _analyze_fbx(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("  X 找不到: %s" % path)
		return
	
	var scene: PackedScene = load(path)
	if not scene:
		print("  X 無法載入: %s" % path)
		return
	
	var instance = scene.instantiate()
	
	# 找 Skeleton3D
	var skeleton: Skeleton3D = _find_node_of_type(instance, "Skeleton3D")
	if skeleton:
		print("  Skeleton: %s (%d bones)" % [skeleton.name, skeleton.get_bone_count()])
		
		# 列出關鍵骨骼
		var key_bones = ["Hips", "Root", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]
		for bone_name in key_bones:
			var idx = skeleton.find_bone(bone_name)
			if idx >= 0:
				var rest = skeleton.get_bone_rest(idx)
				print("    OK %s (idx=%d) rest=(%+.3f, %+.3f, %+.3f)" % [
					bone_name, idx, rest.origin.x, rest.origin.y, rest.origin.z
				])
			else:
				# 嘗試 mixamo 前綴
				for prefix in ["mixamorig1_", "mixamorig_"]:
					var mx_name = prefix + bone_name
					idx = skeleton.find_bone(mx_name)
					if idx >= 0:
						var rest = skeleton.get_bone_rest(idx)
						print("    OK %s -> %s (idx=%d) rest=(%+.3f, %+.3f, %+.3f)" % [
							bone_name, mx_name, idx, rest.origin.x, rest.origin.y, rest.origin.z
						])
						break
				if idx < 0:
					print("    -- %s not found" % bone_name)
	
	# 找 AnimationPlayer
	var anim_player: AnimationPlayer = _find_node_of_type(instance, "AnimationPlayer")
	if not anim_player:
		print("  X 找不到 AnimationPlayer")
		instance.free()
		return
	
	var anim_list = anim_player.get_animation_list()
	print("  AnimationPlayer: %d animations" % anim_list.size())
	
	for anim_name in anim_list:
		if anim_name == "RESET":
			continue
		
		var anim: Animation = anim_player.get_animation(anim_name)
		if not anim:
			continue
		
		print("\n  Animation: \"%s\"" % anim_name)
		print("    Length: %.3fs  Loop: %s  Tracks: %d" % [
			anim.length,
			"Yes" if anim.loop_mode != Animation.LOOP_NONE else "No",
			anim.get_track_count()
		])
		
		# 找所有位置軌道
		print("    Position tracks:")
		var hips_track := -1
		var root_track := -1
		
		for t in range(anim.get_track_count()):
			if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			
			var track_path = str(anim.track_get_path(t))
			var key_count = anim.track_get_key_count(t)
			
			if key_count < 1:
				continue
			
			var first_val: Vector3 = anim.track_get_key_value(t, 0)
			var last_val: Vector3 = anim.track_get_key_value(t, key_count - 1)
			var delta_v = last_val - first_val
			
			var tag = ""
			if "Hips" in track_path or "Hip" in track_path:
				tag = " <-- HIPS"
				hips_track = t
			elif "Root" in track_path:
				tag = " <-- ROOT"
				root_track = t
			elif "Foot" in track_path:
				tag = " <-- FOOT"
			elif "Toe" in track_path:
				tag = " <-- TOE"
			
			# 只印有意義位移的軌道
			if delta_v.length() > 0.001 or tag != "":
				print("      [%d] %s (%d keys) delta=(%+.4f, %+.4f, %+.4f)%s" % [
					t, track_path, key_count, delta_v.x, delta_v.y, delta_v.z, tag
				])
		
		# 分析 Root Motion
		var analyze_track = hips_track if hips_track >= 0 else root_track
		if analyze_track >= 0:
			var track_path = str(anim.track_get_path(analyze_track))
			var key_count = anim.track_get_key_count(analyze_track)
			
			print("\n    === Root Motion Analysis (track: %s) ===" % track_path)
			
			if key_count > 0:
				var first_pos: Vector3 = anim.track_get_key_value(analyze_track, 0)
				var last_pos: Vector3 = anim.track_get_key_value(analyze_track, key_count - 1)
				var total_delta = last_pos - first_pos
				
				print("    Start: (%+.4f, %+.4f, %+.4f)" % [first_pos.x, first_pos.y, first_pos.z])
				print("    End:   (%+.4f, %+.4f, %+.4f)" % [last_pos.x, last_pos.y, last_pos.z])
				print("    Delta: (%+.4f, %+.4f, %+.4f)" % [total_delta.x, total_delta.y, total_delta.z])
				
				# Y range
				var min_y = first_pos.y
				var max_y = first_pos.y
				for k in range(key_count):
					var pos: Vector3 = anim.track_get_key_value(analyze_track, k)
					min_y = minf(min_y, pos.y)
					max_y = maxf(max_y, pos.y)
				
				print("    Y range: [%.4f, %.4f] (span=%.4f)" % [min_y, max_y, max_y - min_y])
				
				# 推算階高
				if abs(total_delta.y) > 0.01:
					var total_y = abs(total_delta.y)
					var dir_str = "UP" if total_delta.y > 0 else "DOWN"
					print("    Direction: %s" % dir_str)
					for steps in range(1, 7):
						var step_h = total_y / steps
						if step_h >= 0.08 and step_h <= 0.40:
							print("    >> Estimate: %d steps x %.1f cm = %.1f cm total" % [steps, step_h * 100, total_y * 100])
				else:
					print("    Y delta ~0: This is an IN-PLACE animation (no root motion Y)")
				
				# 水平位移
				var h_dist = Vector2(total_delta.x, total_delta.z).length()
				print("    Horizontal: %.4f m (speed: %.3f m/s)" % [h_dist, h_dist / anim.length if anim.length > 0 else 0])
				
				# Y 曲線取樣
				print("    Y curve (sampled every 0.05s):")
				var curve_str = "      "
				var count = 0
				var t_cur = 0.0
				while t_cur <= anim.length + 0.001:
					var pos = _sample_position_track(anim, analyze_track, t_cur)
					curve_str += "%+.3f " % pos.y
					count += 1
					if count % 12 == 0:
						print(curve_str)
						curve_str = "      "
					t_cur += 0.05
				if curve_str.strip_edges() != "":
					print(curve_str)
		
		# 分析腳部
		_analyze_foot_tracks(anim)
	
	instance.free()

func _analyze_foot_tracks(anim: Animation) -> void:
	for foot_name in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		for t in range(anim.get_track_count()):
			var p = str(anim.track_get_path(t))
			if foot_name in p and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				var key_count = anim.track_get_key_count(t)
				if key_count < 2:
					continue
				
				var min_y = INF
				var max_y = - INF
				var min_y_time = 0.0
				var max_y_time = 0.0
				for k in range(key_count):
					var pos: Vector3 = anim.track_get_key_value(t, k)
					var time = anim.track_get_key_time(t, k)
					if pos.y < min_y:
						min_y = pos.y
						min_y_time = time
					if pos.y > max_y:
						max_y = pos.y
						max_y_time = time
				
				print("    Foot %s: Y=[%.3f, %.3f] ground@%.2fs lift@%.2fs lift_height=%.3f" % [
					foot_name, min_y, max_y, min_y_time, max_y_time, max_y - min_y
				])
				break

func _sample_position_track(anim: Animation, track_idx: int, time: float) -> Vector3:
	var key_count = anim.track_get_key_count(track_idx)
	if key_count == 0:
		return Vector3.ZERO
	if key_count == 1:
		return anim.track_get_key_value(track_idx, 0)
	
	if time <= anim.track_get_key_time(track_idx, 0):
		return anim.track_get_key_value(track_idx, 0)
	if time >= anim.track_get_key_time(track_idx, key_count - 1):
		return anim.track_get_key_value(track_idx, key_count - 1)
	
	for k in range(key_count - 1):
		var t0 = anim.track_get_key_time(track_idx, k)
		var t1 = anim.track_get_key_time(track_idx, k + 1)
		if time >= t0 and time < t1:
			var factor = (time - t0) / (t1 - t0) if (t1 - t0) > 0 else 0.0
			var v0: Vector3 = anim.track_get_key_value(track_idx, k)
			var v1: Vector3 = anim.track_get_key_value(track_idx, k + 1)
			return v0.lerp(v1, factor)
	
	return anim.track_get_key_value(track_idx, key_count - 1)

func _find_node_of_type(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name:
		return root
	for child in root.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null
