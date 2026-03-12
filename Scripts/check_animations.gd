@tool
extends EditorScript

# 檢查並修復動畫庫中的動畫問題

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"

func _run():
	print("=== 檢查動畫庫 ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + ANIM_LIB_PATH)
		return
	
	var anims_to_check = [
		"left strafe walking", "right strafe walking",
		"mx_f_walk", "mx_b_walk", "mx_l_walk", "mx_r_walk"
	]
	
	for anim_name in anims_to_check:
		if lib.has_animation(anim_name):
			var anim = lib.get_animation(anim_name)
			print("\n動畫: %s" % anim_name)
			print("  長度: %.2f 秒" % anim.length)
			print("  軌道數: %d" % anim.get_track_count())
			print("  循環: %s" % _loop_mode_str(anim.loop_mode))
			
			# 檢查第一個軌道的路徑
			if anim.get_track_count() > 0:
				print("  第一個軌道: %s" % anim.track_get_path(0))
			
			# 確保設定為循環
			if anim.loop_mode != Animation.LOOP_LINEAR:
				print("  -> 自動設定為循環")
				anim.loop_mode = Animation.LOOP_LINEAR
		else:
			print("\n動畫: %s - 找不到!" % anim_name)
	
	# 儲存修改
	var error = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if error == OK:
		print("\n已儲存動畫庫 (已設定為循環)")
	else:
		push_error("儲存失敗")

func _loop_mode_str(mode: int) -> String:
	match mode:
		Animation.LOOP_NONE: return "無循環"
		Animation.LOOP_LINEAR: return "線性循環"
		Animation.LOOP_PINGPONG: return "乒乓循環"
	return "未知"
