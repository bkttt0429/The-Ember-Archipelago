@tool
extends EditorScript

## 批量創建所有斜向蹲行動畫
## 使用方式：File > Run

const LIBRARY_PATH = "res://Player/animations/movement.res"

# 定義要創建的斜向動畫
# [源動畫, 新動畫名稱, Y軸旋轉角度]
const DIAGONAL_ANIMS = [
	["Crouch_Walk_Forward", "Crouch_Walk_ForwardLeft", 45.0], # 左前 +45°
	["Crouch_Walk_Backward", "Crouch_Walk_BackwardRight", 45.0], # 右後 +45° (往後走時向右看)
	["Crouch_Walk_Backward", "Crouch_Walk_BackwardLeft", -45.0], # 左後 -45° (往後走時向左看)
]

func _run():
	print("\n" + "=".repeat(60))
	print("🔧 批量創建斜向蹲行動畫")
	print("=".repeat(60))
	
	var lib = load(LIBRARY_PATH) as AnimationLibrary
	if lib == null:
		push_error("無法載入動畫庫: " + LIBRARY_PATH)
		return
	
	print("✅ 動畫庫載入成功")
	print("現有動畫數量: ", lib.get_animation_list().size())
	
	var success_count = 0
	
	for config in DIAGONAL_ANIMS:
		var source_name = config[0]
		var new_name = config[1]
		var angle = config[2]
		
		print("\n" + "-".repeat(40))
		print("📦 處理: ", new_name)
		
		if create_diagonal_animation(lib, source_name, new_name, angle):
			success_count += 1
	
	# 儲存
	var err = ResourceSaver.save(lib, LIBRARY_PATH)
	if err != OK:
		push_error("無法儲存動畫庫!")
		return
	
	print("\n" + "=".repeat(60))
	print("✅ 完成! 成功創建 ", success_count, "/", DIAGONAL_ANIMS.size(), " 個動畫")
	print("=".repeat(60))
	print("已儲存到: ", LIBRARY_PATH)

func create_diagonal_animation(lib: AnimationLibrary, source_name: String, new_name: String, angle: float) -> bool:
	# 檢查源動畫
	if not lib.has_animation(source_name):
		push_error("  找不到源動畫: " + source_name)
		return false
	
	var source_anim = lib.get_animation(source_name)
	print("  源動畫: ", source_name, " (", source_anim.get_track_count(), " 軌道)")
	
	# 複製動畫
	var new_anim = source_anim.duplicate(true) as Animation
	new_anim.resource_name = new_name
	
	# 找 Hips 旋轉軌道
	var hips_track = -1
	for i in range(new_anim.get_track_count()):
		var path = str(new_anim.track_get_path(i))
		if "Hips" in path and new_anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
			hips_track = i
			break
	
	if hips_track == -1:
		push_error("  找不到 Hips 旋轉軌道!")
		return false
	
	# 修改旋轉
	var rotation_offset = Quaternion(Vector3.UP, deg_to_rad(angle))
	var key_count = new_anim.track_get_key_count(hips_track)
	
	var keyframes = []
	for key_idx in range(key_count):
		var time = new_anim.track_get_key_time(hips_track, key_idx)
		var original_quat = new_anim.track_get_key_value(hips_track, key_idx) as Quaternion
		var new_quat = rotation_offset * original_quat
		keyframes.append({"time": time, "value": new_quat})
	
	# 清除並重建軌道
	while new_anim.track_get_key_count(hips_track) > 0:
		new_anim.track_remove_key(hips_track, 0)
	
	for kf in keyframes:
		new_anim.rotation_track_insert_key(hips_track, kf.time, kf.value)
	
	# 移除舊動畫（如果存在）
	if lib.has_animation(new_name):
		lib.remove_animation(new_name)
	
	# 加入新動畫
	var err = lib.add_animation(new_name, new_anim)
	if err != OK:
		push_error("  無法加入動畫: " + str(err))
		return false
	
	print("  ✅ 創建完成: ", new_name, " (旋轉 ", angle, "°)")
	return true
