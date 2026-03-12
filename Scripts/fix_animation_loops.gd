@tool
extends EditorScript

# 修復動畫循環問題 - 裁剪開頭和結尾的問題幀

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"

# 要修復的動畫
var anims_to_fix = [
	"jog_bl", "jog_br"
]

# 裁剪的時間
const TRIM_FROM_START = 0.1 # 裁剪開頭 0.1 秒
const TRIM_FROM_END = 0.1 # 裁剪結尾 0.1 秒

func _run():
	print("=== 裁剪動畫開頭和結尾 ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + ANIM_LIB_PATH)
		return
	
	for anim_name in anims_to_fix:
		if not lib.has_animation(anim_name):
			print("找不到: %s" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var old_length = anim.length
		
		# 計算新長度
		var new_length = old_length - TRIM_FROM_START - TRIM_FROM_END
		
		if new_length < 0.3:
			print("%s: 裁剪後太短 (%.2f秒)，跳過" % [anim_name, new_length])
			continue
		
		# 移動所有關鍵幀：向前移動 TRIM_FROM_START 秒
		_shift_keyframes(anim, -TRIM_FROM_START)
		
		# 移除時間小於 0 或大於 new_length 的關鍵幀
		_remove_keys_outside_range(anim, 0, new_length)
		
		# 設定新長度
		anim.length = new_length
		
		print("%s: %.3f -> %.3f 秒（裁剪了開頭 %.1f 秒 + 結尾 %.1f 秒）" % [
			anim_name, old_length, new_length, TRIM_FROM_START, TRIM_FROM_END
		])
	
	# 儲存
	var error = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if error == OK:
		print("\n已儲存！動畫已裁剪。")
	else:
		push_error("儲存失敗: %d" % error)

func _shift_keyframes(anim: Animation, shift: float):
	# 移動所有關鍵幀的時間
	for track_idx in range(anim.get_track_count()):
		var key_count = anim.track_get_key_count(track_idx)
		
		# 需要重新插入所有關鍵幀
		var keys_data = []
		for key_idx in range(key_count):
			var time = anim.track_get_key_time(track_idx, key_idx) + shift
			var value = anim.track_get_key_value(track_idx, key_idx)
			keys_data.append({"time": time, "value": value})
		
		# 清除所有關鍵幀
		anim.track_clear_keys(track_idx)
		
		# 重新插入移動後的關鍵幀
		for key_data in keys_data:
			if key_data.time >= 0: # 只插入時間 >= 0 的關鍵幀
				anim.track_insert_key(track_idx, key_data.time, key_data.value)

func _remove_keys_outside_range(anim: Animation, min_time: float, max_time: float):
	for track_idx in range(anim.get_track_count()):
		var keys_to_remove = []
		
		for key_idx in range(anim.track_get_key_count(track_idx)):
			var time = anim.track_get_key_time(track_idx, key_idx)
			if time < min_time or time > max_time:
				keys_to_remove.append(key_idx)
		
		# 從後往前移除
		keys_to_remove.reverse()
		for key_idx in keys_to_remove:
			anim.track_remove_key(track_idx, key_idx)
