@tool
extends EditorScript

## 從動畫庫中移除 Head 骨骼軌道
## 這樣 AnimationTree 就不會覆蓋程式化的頭部旋轉

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"
const BONES_TO_REMOVE = ["Head", "Neck"] # 要移除的骨骼軌道

func _run():
	print("=== 移除頭部骨骼軌道 ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("找不到動畫庫: " + ANIM_LIB_PATH)
		return
	
	var anim_names = lib.get_animation_list()
	var total_removed = 0
	
	for anim_name in anim_names:
		var anim = lib.get_animation(anim_name)
		var removed = _remove_bone_tracks(anim, anim_name)
		total_removed += removed
	
	# 儲存修改
	var err = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if err == OK:
		print("✅ 已儲存動畫庫，共移除 %d 個軌道" % total_removed)
	else:
		push_error("儲存失敗: " + str(err))
	
	print("=== 完成 ===")

func _remove_bone_tracks(anim: Animation, anim_name: String) -> int:
	var removed_count = 0
	
	# 從後往前遍歷避免索引問題
	for i in range(anim.get_track_count() - 1, -1, -1):
		var track_path = anim.track_get_path(i)
		var path_str = str(track_path)
		
		# 檢查是否包含要移除的骨骼
		for bone_name in BONES_TO_REMOVE:
			if ":" + bone_name in path_str or "/" + bone_name in path_str:
				anim.remove_track(i)
				print("  移除: %s - %s" % [anim_name, path_str])
				removed_count += 1
				break
	
	return removed_count
