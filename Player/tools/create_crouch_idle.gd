@tool
extends EditorScript
## 從 Stand_To_Crouch 動畫的最後幾幀創建 Crouch_Idle 循環動畫
## 使用方式：Script > Run

const LIBRARY_PATH = "res://Player/animations/movement.res"
const SOURCE_ANIM = "Stand_To_Crouch"
const TARGET_ANIM = "Crouch_Idle"
const IDLE_DURATION = 0.1 # 短循環（接近靜止姿勢）

func _run() -> void:
	print("=== 創建 Crouch_Idle 動畫 ===")
	
	var lib = ResourceLoader.load(LIBRARY_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入 %s" % LIBRARY_PATH)
		return
	
	if not lib.has_animation(SOURCE_ANIM):
		push_error("找不到來源動畫: %s" % SOURCE_ANIM)
		return
	
	var source = lib.get_animation(SOURCE_ANIM)
	var src_length = source.length
	print("來源動畫: %s (%.2fs, %d 軌道)" % [SOURCE_ANIM, src_length, source.get_track_count()])
	
	# 創建新動畫：只取最後一幀的姿勢
	var idle_anim = Animation.new()
	idle_anim.length = IDLE_DURATION
	idle_anim.loop_mode = Animation.LOOP_LINEAR
	
	for i in range(source.get_track_count()):
		var path = source.track_get_path(i)
		var type = source.track_get_type(i)
		var key_count = source.track_get_key_count(i)
		
		if key_count == 0:
			continue
		
		# 在新動畫中創建對應軌道
		var new_track = idle_anim.add_track(type)
		idle_anim.track_set_path(new_track, path)
		
		# 取最後一幀的值作為靜止姿勢
		var last_value = source.track_get_key_value(i, key_count - 1)
		
		# 插入兩個相同的 key（開頭和結尾），確保循環平滑
		idle_anim.track_insert_key(new_track, 0.0, last_value)
		idle_anim.track_insert_key(new_track, IDLE_DURATION, last_value)
	
	# 加入到 library
	if lib.has_animation(TARGET_ANIM):
		lib.remove_animation(TARGET_ANIM)
		print("移除舊版 %s" % TARGET_ANIM)
	
	var err = lib.add_animation(TARGET_ANIM, idle_anim)
	if err == OK:
		print("✅ 已創建: %s (%d 軌道, %.2fs loop)" % [TARGET_ANIM, idle_anim.get_track_count(), IDLE_DURATION])
	else:
		push_error("無法加入動畫: %s" % error_string(err))
		return
	
	# 儲存
	err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err == OK:
		print("=== 完成！Crouch_Idle 已加入 %s ===" % LIBRARY_PATH)
	else:
		push_error("儲存失敗: %s" % error_string(err))
