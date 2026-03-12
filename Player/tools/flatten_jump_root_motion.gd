@tool
extends EditorScript

## 修正版：將所有跳躍動畫的 Hips Y 值設為統一基準
## 使用統一的 Y 值（正常站立高度），讓所有動畫與膠囊體對齊
## 
## 使用方式：在 Script Editor 中按 Ctrl+Shift+X 執行

# 統一的基準 Y 值（正常站立時 Hips 的高度）
const BASE_Y_VALUE: float = 0.92

# 要處理的動畫列表
const ANIMATIONS_TO_FIX: Array[String] = [
	"Jump_Running",
	"Jump_Standing",
	"Jump_Standing_Alt",
	"Jump_ToStage",
	"Jump_ToStage1",
	"Jump_Up_Platform",
	"Jump_Up_Platform_Alt",
	"Jump_Up_Running",
	"Jump_Down_Platform",
	"Jump_Down_Platform_Alt",
	"Jump_Down_Platform_Alt2",
	"ual_Jump_Land",
	"ual_Jump_Start",
]

func _run() -> void:
	var anim_lib_path = "res://Player/animations/movement.res"
	var anim_lib = load(anim_lib_path) as AnimationLibrary
	
	if not anim_lib:
		print("❌ 無法載入動畫庫: ", anim_lib_path)
		return
	
	print("=".repeat(70))
	print("🔧 統一 Hips Y 軸位置工具 (修正版)")
	print("=".repeat(70))
	print("基準 Y 值: %.3f" % BASE_Y_VALUE)
	print("將處理 %d 個動畫\n" % ANIMATIONS_TO_FIX.size())
	
	var fixed_count = 0
	
	for anim_name in ANIMATIONS_TO_FIX:
		var anim = anim_lib.get_animation(anim_name)
		if not anim:
			print("⚠️ 動畫不存在: ", anim_name)
			continue
		
		var result = _fix_hips_y(anim, anim_name)
		if result:
			fixed_count += 1
	
	# 保存動畫庫
	var save_result = ResourceSaver.save(anim_lib, anim_lib_path)
	if save_result == OK:
		print("\n✅ 動畫庫已保存: ", anim_lib_path)
	else:
		print("\n❌ 保存失敗! 錯誤碼: ", save_result)
	
	print("\n" + "=".repeat(70))
	print("📊 處理結果: 成功修復 %d 個動畫" % fixed_count)
	print("=".repeat(70))

func _fix_hips_y(anim: Animation, anim_name: String) -> bool:
	print("-".repeat(50))
	print("🔧 處理: ", anim_name)
	
	# 尋找 Hips 位置軌道
	var hips_track_idx = -1
	
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		var track_type = anim.track_get_type(i)
		
		if ("Hips" in path_str or "hips" in path_str) and track_type == Animation.TYPE_POSITION_3D:
			hips_track_idx = i
			break
	
	if hips_track_idx < 0:
		print("   ⚠️ 找不到 Hips 位置軌道，跳過")
		return false
	
	var key_count = anim.track_get_key_count(hips_track_idx)
	if key_count == 0:
		print("   ⚠️ 軌道沒有關鍵幀，跳過")
		return false
	
	# 獲取當前的 Y 值範圍
	var first_pos = anim.position_track_interpolate(hips_track_idx, 0.0)
	print("   原始第一幀 Y: %.3f → 新 Y: %.3f" % [first_pos.y, BASE_Y_VALUE])
	
	# 修改每個關鍵幀的 Y 值
	var modified_count = 0
	for i in key_count:
		var key_value = anim.track_get_key_value(hips_track_idx, i)
		if key_value is Vector3:
			var new_value = Vector3(key_value.x, BASE_Y_VALUE, key_value.z)
			anim.track_set_key_value(hips_track_idx, i, new_value)
			modified_count += 1
	
	print("   ✅ 修改了 %d 個關鍵幀" % modified_count)
	return true
