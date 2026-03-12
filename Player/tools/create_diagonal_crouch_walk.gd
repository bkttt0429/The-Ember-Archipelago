@tool
extends EditorScript

## 在 Godot 中直接創建斜向蹲行動畫
## 方法：複製原始動畫，然後旋轉 Hips 骨骼的旋轉曲線
## 使用方式：File > Run

const LIBRARY_PATH = "res://Player/animations/movement.res"
const SOURCE_ANIM_NAME = "Crouch_Walk_Forward" # 原始前進動畫
const NEW_ANIM_NAME = "Crouch_Walk_ForwardRight" # 新的斜向動畫
const ROTATION_ANGLE = -45.0 # 旋轉角度（度）

func _run():
	print("\n" + "=".repeat(60))
	print("🔧 創建斜向蹲行動畫")
	print("=".repeat(60))
	
	# 載入動畫庫
	var lib = load(LIBRARY_PATH) as AnimationLibrary
	if lib == null:
		push_error("無法載入動畫庫: " + LIBRARY_PATH)
		return
	
	print("✅ 動畫庫載入成功")
	
	# 檢查原始動畫是否存在
	if not lib.has_animation(SOURCE_ANIM_NAME):
		push_error("找不到原始動畫: " + SOURCE_ANIM_NAME)
		print("可用動畫列表:")
		for anim_name in lib.get_animation_list():
			if "crouch" in anim_name.to_lower() or "Crouch" in anim_name:
				print("  - ", anim_name)
		return
	
	# 取得原始動畫
	var source_anim = lib.get_animation(SOURCE_ANIM_NAME)
	print("✅ 原始動畫: ", SOURCE_ANIM_NAME)
	print("   軌道數: ", source_anim.get_track_count())
	print("   長度: ", source_anim.length, " 秒")
	
	# 複製動畫
	var new_anim = source_anim.duplicate(true) as Animation
	new_anim.resource_name = NEW_ANIM_NAME
	
	# 找到 Hips 的旋轉軌道
	var hips_rotation_track = -1
	for i in range(new_anim.get_track_count()):
		var path = str(new_anim.track_get_path(i))
		var track_type = new_anim.track_get_type(i)
		
		# 尋找 Hips 的 Rotation3D 軌道
		if "Hips" in path and track_type == Animation.TYPE_ROTATION_3D:
			hips_rotation_track = i
			print("✅ 找到 Hips 旋轉軌道: ", path)
			break
	
	if hips_rotation_track == -1:
		push_error("找不到 Hips 旋轉軌道！")
		return
	
	# 修改 Hips 旋轉曲線 - 在每個關鍵幀加上 Y 軸旋轉
	var rotation_offset = Quaternion(Vector3.UP, deg_to_rad(ROTATION_ANGLE))
	var key_count = new_anim.track_get_key_count(hips_rotation_track)
	
	print("📝 正在修改 ", key_count, " 個關鍵幀...")
	
	# 先收集所有關鍵幀數據
	var keyframes = []
	for key_idx in range(key_count):
		var time = new_anim.track_get_key_time(hips_rotation_track, key_idx)
		var original_quat = new_anim.track_get_key_value(hips_rotation_track, key_idx) as Quaternion
		var new_quat = rotation_offset * original_quat
		keyframes.append({"time": time, "value": new_quat})
	
	# 清除舊軌道的所有關鍵幀
	while new_anim.track_get_key_count(hips_rotation_track) > 0:
		new_anim.track_remove_key(hips_rotation_track, 0)
	
	# 插入新的關鍵幀
	for kf in keyframes:
		new_anim.rotation_track_insert_key(hips_rotation_track, kf.time, kf.value)
	
	print("✅ 已應用 ", ROTATION_ANGLE, "° Y軸旋轉到 Hips")
	
	# 如果已存在同名動畫，先移除
	if lib.has_animation(NEW_ANIM_NAME):
		lib.remove_animation(NEW_ANIM_NAME)
		print("⚠️ 已移除舊的 ", NEW_ANIM_NAME)
	
	# 加入新動畫
	var err = lib.add_animation(NEW_ANIM_NAME, new_anim)
	if err != OK:
		push_error("無法加入動畫: " + str(err))
		return
	
	# 儲存
	err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err != OK:
		push_error("無法儲存動畫庫: " + str(err))
		return
	
	print("\n" + "=".repeat(60))
	print("✅ 成功!")
	print("=".repeat(60))
	print("   新動畫名稱: ", NEW_ANIM_NAME)
	print("   已儲存到: ", LIBRARY_PATH)
	print("\n現在可以在 BlendSpace2D 中使用 movement/", NEW_ANIM_NAME)
