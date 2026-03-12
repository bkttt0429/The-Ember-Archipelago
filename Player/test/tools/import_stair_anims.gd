@tool
extends EditorScript
## 將樓梯動畫從 FBX 提取並匯入 movement.res
## 使用方式：在 Godot 編輯器中 File > Run Script 執行此腳本

const MOVEMENT_LIB_PATH = "res://Player/animations/movement.res"
const STAIR_FBX_DIR = "res://Player/assets/characters/player/motion/mx/stairs/"
const SKELETON_PATH = "%GeneralSkeleton" # ★ 使用 Godot unique name 語法（與 movement.res 現有動畫一致）

# FBX 檔案 → 動畫名稱映射（與 SimpleCapsuleMove.gd 中的常數一致）
const STAIR_ANIMS = {
	"Ascending Stairs.fbx": "Ascending_Stairs",
	"Descending Stairs.fbx": "Descending_Stairs",
}

func _run() -> void:
	print("\n=== 匯入樓梯動畫到 movement.res ===")
	
	# 1. 載入 movement.res
	var lib = ResourceLoader.load(MOVEMENT_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("[StairImport] 無法載入: " + MOVEMENT_LIB_PATH)
		return
	
	# 2. 先查看現有動畫的軌道格式作為參考
	var existing_anims = lib.get_animation_list()
	print("[StairImport] movement.res 現有 %d 個動畫" % existing_anims.size())
	if existing_anims.size() > 0:
		var ref_anim = lib.get_animation(existing_anims[0])
		print("[StairImport] 參考軌道格式 (from '%s'):" % existing_anims[0])
		for i in range(min(ref_anim.get_track_count(), 5)):
			print("  [%d] %s" % [i, ref_anim.track_get_path(i)])
	
	# 3. 逐一處理 FBX
	var success_count = 0
	for fbx_file in STAIR_ANIMS:
		var anim_name = STAIR_ANIMS[fbx_file]
		var fbx_path = STAIR_FBX_DIR + fbx_file
		
		print("\n[StairImport] 處理: %s → '%s'" % [fbx_file, anim_name])
		
		# 載入 FBX 為 PackedScene
		var scene = ResourceLoader.load(fbx_path) as PackedScene
		if not scene:
			push_error("[StairImport] 無法載入 FBX: " + fbx_path)
			continue
		
		# 實例化並找 AnimationPlayer
		var instance = scene.instantiate()
		var fbx_anim_player: AnimationPlayer = _find_anim_player(instance)
		if not fbx_anim_player:
			push_error("[StairImport] FBX 中找不到 AnimationPlayer")
			instance.free()
			continue
		
		# 提取動畫
		var anim = _extract_first_animation(fbx_anim_player)
		if not anim:
			push_error("[StairImport] 找不到動畫資料")
			instance.free()
			continue
		
		# 重新映射軌道路徑
		var remapped = _remap_tracks(anim)
		print("[StairImport] 處理了 %d 個軌道" % remapped)
		
		# 設定迴圈模式
		anim.loop_mode = Animation.LOOP_LINEAR
		
		# 移除舊的同名動畫（如果存在）
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
			print("[StairImport] 已移除舊動畫: %s" % anim_name)
		
		# 加入 library
		lib.add_animation(anim_name, anim)
		print("[StairImport] ✅ 已加入: %s (%.2fs, %d tracks, loop)" % [
			anim_name, anim.length, anim.get_track_count()
		])
		
		instance.free()
		success_count += 1
	
	# 4. 儲存
	if success_count > 0:
		var err = ResourceSaver.save(lib, MOVEMENT_LIB_PATH)
		if err == OK:
			print("\n[StairImport] ✅ 已儲存 movement.res (%d 個新動畫)" % success_count)
		else:
			push_error("[StairImport] 儲存失敗: %d" % err)
	else:
		push_error("[StairImport] 沒有成功匯入任何動畫")
	
	print("\n=== 匯入完成 ===")


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_anim_player(child)
		if found:
			return found
	return null


func _extract_first_animation(ap: AnimationPlayer) -> Animation:
	for lib_name in ap.get_animation_library_list():
		var alib = ap.get_animation_library(lib_name)
		for anim_name in alib.get_animation_list():
			var anim = alib.get_animation(anim_name)
			if anim:
				print("[StairImport] 找到動畫: '%s/%s' (%.2fs)" % [lib_name, anim_name, anim.length])
				return anim.duplicate()
	return null


func _remap_tracks(anim: Animation) -> int:
	var count = 0
	for i in range(anim.get_track_count()):
		var orig_path = str(anim.track_get_path(i))
		var colon_pos = orig_path.find(":")
		if colon_pos >= 0:
			var node_part = orig_path.substr(0, colon_pos)
			var bone_part = orig_path.substr(colon_pos + 1)
			# ★ 如果已經是正確的 %GeneralSkeleton 路徑，跳過重映射
			if node_part == SKELETON_PATH:
				if count < 3:
					print("  [%d] '%s' (已正確)" % [i, orig_path])
				count += 1
				continue
			# 需要重映射（例如原始的 Skeleton3D 路徑）
			var new_path = NodePath(SKELETON_PATH +":"+ bone_part)
			anim.track_set_path(i, new_path)
			count += 1
			if count <= 5:
				print("  [%d] '%s' -> '%s'" % [i, orig_path, new_path])
		else:
			print("  [%d] '%s' (non-bone, skipped)" % [i, orig_path])
	return count
