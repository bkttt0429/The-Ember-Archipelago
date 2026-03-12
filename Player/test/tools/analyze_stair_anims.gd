@tool
extends EditorScript
## 分析樓梯動畫的 Hips 骨骼位置和時間軸
## 用於判定每一步的 Y 位移量和時間點

const MOVEMENT_LIB_PATH = "res://Player/animations/movement.res"
const ANIMS_TO_ANALYZE = ["Ascending_Stairs", "Descending_Stairs"]

func _run() -> void:
	print("\n=== 樓梯動畫分析 ===")
	
	var lib = ResourceLoader.load(MOVEMENT_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + MOVEMENT_LIB_PATH)
		return
	
	for anim_name in ANIMS_TO_ANALYZE:
		if not lib.has_animation(anim_name):
			print("[%s] ❌ 動畫不存在" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		print("\n========================================")
		print("動畫: %s" % anim_name)
		print("長度: %.4fs | FPS: %.1f | Loop: %d" % [anim.length, 30.0, anim.loop_mode])
		print("軌道數: %d" % anim.get_track_count())
		print("========================================")
		
		# 找 Hips 骨骼的 position 和 rotation 軌道
		for i in range(anim.get_track_count()):
			var path = str(anim.track_get_path(i))
			var track_type = anim.track_get_type(i)
			
			# 只關注 Hips
			if path.find("Hips") < 0:
				continue
			
			var type_name = _track_type_name(track_type)
			var key_count = anim.track_get_key_count(i)
			print("\n--- 軌道[%d]: %s (type: %s, keys: %d) ---" % [i, path, type_name, key_count])
			
			# Position 軌道 (type 0 = VALUE, type 2 = POSITION_3D)
			if track_type == Animation.TYPE_POSITION_3D:
				print("  [Position 3D 軌道]")
				var min_y = 99999.0
				var max_y = -99999.0
				var first_y = 0.0
				var last_y = 0.0
				
				for k in range(key_count):
					var time = anim.track_get_key_time(i, k)
					var value = anim.position_track_interpolate(i, time)
					if k == 0:
						first_y = value.y
					if k == key_count - 1:
						last_y = value.y
					min_y = min(min_y, value.y)
					max_y = max(max_y, value.y)
					
					# 印出每個 keyframe
					print("  t=%.4f  pos=(%.4f, %.4f, %.4f)" % [time, value.x, value.y, value.z])
				
				print("\n  === Y 軸摘要 ===")
				print("  首幀 Y: %.4f" % first_y)
				print("  末幀 Y: %.4f" % last_y)
				print("  Y 變化量: %.4f (%.2f cm)" % [last_y - first_y, (last_y - first_y) * 100])
				print("  Y 範圍: %.4f ~ %.4f (跨度 %.4f)" % [min_y, max_y, max_y - min_y])
			
			# Rotation 軌道
			elif track_type == Animation.TYPE_ROTATION_3D:
				print("  [Rotation 3D 軌道] (略)")
			
			# Scale 軌道
			elif track_type == Animation.TYPE_SCALE_3D:
				print("  [Scale 3D 軌道] (略)")
		
		# 也找 Z 方向位移（前進距離）
		print("\n--- Hips 位移總結 ---")
		for i in range(anim.get_track_count()):
			var path = str(anim.track_get_path(i))
			if path.find("Hips") >= 0 and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
				var t0_pos = anim.position_track_interpolate(i, 0.0)
				var t_end_pos = anim.position_track_interpolate(i, anim.length)
				var delta = t_end_pos - t0_pos
				print("  起始位置: (%.4f, %.4f, %.4f)" % [t0_pos.x, t0_pos.y, t0_pos.z])
				print("  結束位置: (%.4f, %.4f, %.4f)" % [t_end_pos.x, t_end_pos.y, t_end_pos.z])
				print("  總位移 ΔX=%.4f, ΔY=%.4f (%.1f cm), ΔZ=%.4f" % [delta.x, delta.y, delta.y * 100, delta.z])
				
				# 每 0.1 秒採樣
				print("\n  --- 每 0.05s 採樣 ---")
				var t = 0.0
				while t <= anim.length + 0.001:
					var pos = anim.position_track_interpolate(i, t)
					var dy = pos.y - t0_pos.y
					var dz = pos.z - t0_pos.z
					print("  t=%.3f  Y=%.4f (ΔY=%.4f)  Z=%.4f (ΔZ=%.4f)" % [t, pos.y, dy, pos.z, dz])
					t += 0.05
				break
	
	print("\n=== 分析完成 ===")


func _track_type_name(t: int) -> String:
	match t:
		0: return "VALUE"
		1: return "POSITION_3D"
		2: return "ROTATION_3D"
		3: return "SCALE_3D"
		4: return "BLEND_SHAPE"
		5: return "METHOD"
		6: return "BEZIER"
		7: return "AUDIO"
		8: return "ANIMATION"
		_: return "UNKNOWN(%d)" % t
