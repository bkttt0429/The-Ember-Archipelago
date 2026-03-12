@tool
extends EditorScript

## 分析跳躍動畫的根骨骼位移
## 在 Script Editor 中執行，會輸出每個跳躍動畫的位移數據

func _run() -> void:
	var anim_lib_path = "res://Player/animations/movement.res"
	var anim_lib = load(anim_lib_path) as AnimationLibrary
	
	if not anim_lib:
		print("❌ 無法載入動畫庫: ", anim_lib_path)
		return
	
	print("=".repeat(70))
	print("🔍 跳躍動畫根骨骼位移分析")
	print("=".repeat(70))
	
	# 找出所有跳躍相關的動畫
	var jump_anims: Array[String] = []
	for anim_name in anim_lib.get_animation_list():
		if "Jump" in anim_name or "jump" in anim_name or "ual_Jump" in anim_name:
			jump_anims.append(anim_name)
	
	print("找到 %d 個跳躍動畫\n" % jump_anims.size())
	
	# 分析結果
	var safe_anims: Array[String] = [] # 沒有位移，可以直接用
	var needs_fix: Array[String] = [] # 有位移，需要處理
	
	for anim_name in jump_anims:
		var anim = anim_lib.get_animation(anim_name)
		if not anim:
			continue
		
		var result = _analyze_animation(anim_name, anim)
		
		if result["has_y_displacement"]:
			needs_fix.append(anim_name)
		else:
			safe_anims.append(anim_name)
	
	# 總結
	print("\n" + "=".repeat(70))
	print("📊 分析結果摘要")
	print("=".repeat(70))
	
	print("\n✅ 可以直接使用的動畫 (%d 個):" % safe_anims.size())
	for anim in safe_anims:
		print("   • ", anim)
	
	print("\n⚠️ 需要處理的動畫 (%d 個):" % needs_fix.size())
	for anim in needs_fix:
		print("   • ", anim)
	
	if needs_fix.size() > 0:
		print("\n💡 建議：")
		print("   1. 在 Blender 中刪除 Hips 的 Y 位置軌道")
		print("   2. 或在 Mixamo 重新下載，勾選 'In Place' 選項")
		print("   3. 或在 Godot 中用腳本運行時忽略 Y 位移")

func _analyze_animation(anim_name: String, anim: Animation) -> Dictionary:
	print("-".repeat(50))
	print("📦 動畫: ", anim_name)
	print("   長度: %.2f 秒" % anim.length)
	
	var result = {
		"has_y_displacement": false,
		"y_start": 0.0,
		"y_end": 0.0,
		"y_delta": 0.0,
		"y_max": 0.0,
		"y_min": 0.0,
	}
	
	# 尋找 Hips 骨骼的位置軌道
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		var track_type = anim.track_get_type(i)
		
		# 只看 Hips 骨骼的位置軌道
		if not ("Hips" in path_str or "hips" in path_str):
			continue
		
		# 檢查是否是位置軌道
		if track_type == Animation.TYPE_POSITION_3D:
			_analyze_position_track(anim, i, result)
		elif track_type == Animation.TYPE_VALUE and ":position" in path_str:
			_analyze_value_position_track(anim, i, result)
	
	# 輸出結果
	if result["y_delta"] != 0 or result["y_max"] != result["y_min"]:
		var y_range = result["y_max"] - result["y_min"]
		print("   🔴 Y軸位移: %.3f (起始: %.3f, 結束: %.3f)" % [result["y_delta"], result["y_start"], result["y_end"]])
		print("   🔴 Y軸範圍: %.3f (最低: %.3f, 最高: %.3f)" % [y_range, result["y_min"], result["y_max"]])
		
		if abs(result["y_delta"]) > 0.01 or y_range > 0.5:
			print("   ⚠️ 有明顯根骨骼位移！")
			result["has_y_displacement"] = true
		else:
			print("   ✅ 位移在可接受範圍內")
	else:
		print("   ✅ 沒有 Y 軸位移")
	
	return result

func _analyze_position_track(anim: Animation, track_idx: int, result: Dictionary) -> void:
	var key_count = anim.track_get_key_count(track_idx)
	if key_count == 0:
		return
	
	# 獲取第一幀和最後一幀的位置
	var first_pos = anim.position_track_interpolate(track_idx, 0.0)
	var last_pos = anim.position_track_interpolate(track_idx, anim.length)
	
	result["y_start"] = first_pos.y
	result["y_end"] = last_pos.y
	result["y_delta"] = last_pos.y - first_pos.y
	
	# 找出最大和最小值
	result["y_max"] = first_pos.y
	result["y_min"] = first_pos.y
	
	for i in key_count:
		var time = anim.track_get_key_time(track_idx, i)
		var pos = anim.position_track_interpolate(track_idx, time)
		result["y_max"] = maxf(result["y_max"], pos.y)
		result["y_min"] = minf(result["y_min"], pos.y)

func _analyze_value_position_track(anim: Animation, track_idx: int, result: Dictionary) -> void:
	var key_count = anim.track_get_key_count(track_idx)
	if key_count == 0:
		return
	
	# 獲取第一幀和最後一幀的值
	var first_val = anim.track_get_key_value(track_idx, 0)
	var last_val = anim.track_get_key_value(track_idx, key_count - 1)
	
	if first_val is Vector3 and last_val is Vector3:
		result["y_start"] = first_val.y
		result["y_end"] = last_val.y
		result["y_delta"] = last_val.y - first_val.y
		
		result["y_max"] = first_val.y
		result["y_min"] = first_val.y
		
		for i in key_count:
			var val = anim.track_get_key_value(track_idx, i)
			if val is Vector3:
				result["y_max"] = maxf(result["y_max"], val.y)
				result["y_min"] = minf(result["y_min"], val.y)
