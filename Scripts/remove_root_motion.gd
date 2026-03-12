@tool
extends EditorScript

# 移除動畫中的 Root Motion (Hips 位移軌道)

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"

func _run():
	print("=== 移除 Root Motion ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入: " + ANIM_LIB_PATH)
		return
	
	# 要處理的動畫列表 - 所有走路/跑步動畫
	var anims_to_fix = [
		"walking", "running",
		"left strafe walking", "right strafe walking",
		"left strafe", "right strafe",
		"jog_bl", "jog_br",
		"mx_f_walk", "mx_b_walk", "mx_l_walk", "mx_r_walk",
		"mx_fl_walk", "mx_fr_walk", "mx_bl_walk", "mx_br_walk",
		"mx_f_run", "mx_b_run", "mx_l_run", "mx_r_run",
		"mx_fl_run", "mx_fr_run", "mx_bl_run", "mx_br_run"
	]
	
	for anim_name in anims_to_fix:
		if not lib.has_animation(anim_name):
			print("找不到動畫: %s" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var removed = _remove_position_tracks(anim)
		print("%s: 移除了 %d 個位移軌道" % [anim_name, removed])
	
	# 儲存
	var error = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if error == OK:
		print("已儲存！Root Motion 已移除。")
	else:
		push_error("儲存失敗")

func _remove_position_tracks(anim: Animation) -> int:
	var removed = 0
	var tracks_to_remove = []
	
	for i in range(anim.get_track_count()):
		var track_type = anim.track_get_type(i)
		var path = str(anim.track_get_path(i))
		
		# 移除 Hips 的位移軌道 (這是 Root Motion 的來源)
		if track_type == Animation.TYPE_POSITION_3D:
			if "Hips" in path or "Root" in path:
				tracks_to_remove.append(i)
				print("  移除軌道: %s" % path)
	
	# 從後往前移除
	tracks_to_remove.reverse()
	for idx in tracks_to_remove:
		anim.remove_track(idx)
		removed += 1
	
	return removed
