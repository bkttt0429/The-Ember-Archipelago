@tool
extends EditorScript

## 將動畫轉為 In-Place（移除根骨水平位移）
## 業界標準參考：
## - Run to Stop: 0.4s ~ 0.8s (典型 0.5-0.6s)
## - Walk to Stop: 0.6s ~ 1.0s
## - Jog to Stop: 0.5s ~ 0.8s

const LIB_PATH = "res://Player/animations/movement.res"

# 要處理的動畫（可依需要調整）
const ANIMS_TO_FIX = ["Run_To_Stop", "Run_To_Stop_Alt", "Stop_Walking"]

# 業界標準長度參考（秒）
const INDUSTRY_STANDARDS = {
	"Run_To_Stop": {"min": 0.4, "max": 0.8, "ideal": 0.5},
	"Run_To_Stop_Alt": {"min": 0.4, "max": 0.8, "ideal": 0.6},
	"Stop_Walking": {"min": 0.6, "max": 1.2, "ideal": 0.8},
}

func _run() -> void:
	print("\n=== In-Place Animation Converter ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	print("--- 動畫長度分析 ---")
	for anim_name in ANIMS_TO_FIX:
		if not lib.has_animation(anim_name):
			print("SKIP: '%s' not found" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var length = anim.length
		var standard = INDUSTRY_STANDARDS.get(anim_name, {"min": 0.5, "max": 1.0, "ideal": 0.6})
		
		var status = "✓ OK"
		if length < standard["min"]:
			status = "⚠ 太短"
		elif length > standard["max"]:
			status = "⚠ 太長 (建議: %.1fs)" % standard["ideal"]
		
		print("  %s: %.2fs [業界 %.1f-%.1fs] %s" % [anim_name, length, standard["min"], standard["max"], status])
	
	print("\n--- 移除根骨水平位移 ---")
	var total_fixed = 0
	
	for anim_name in ANIMS_TO_FIX:
		if not lib.has_animation(anim_name):
			continue
		
		var anim = lib.get_animation(anim_name)
		var fixed = _remove_root_motion(anim, anim_name)
		total_fixed += fixed
	
	if total_fixed > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\nSUCCESS: Saved library with %d tracks modified" % total_fixed)
		else:
			print("\nERROR saving: ", err)
	else:
		print("\nNo root motion tracks found to fix")
	
	print("\n=== Done ===")

func _remove_root_motion(anim: Animation, anim_name: String) -> int:
	var fixed = 0
	
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# 只處理 Hips 的 position 軌道
		if "Hips:position" in path_str or (":Hips" in path_str and anim.track_get_type(i) == Animation.TYPE_POSITION_3D):
			var key_count = anim.track_get_key_count(i)
			if key_count == 0:
				continue
			
			# 取得第一個關鍵幀的 Y 值作為基準
			var first_pos = anim.track_get_key_value(i, 0) as Vector3
			var base_y = first_pos.y
			
			print("  %s: Found Hips position track (%d keys)" % [anim_name, key_count])
			
			# 將所有關鍵幀的 X/Z 歸零，保留 Y
			for k in key_count:
				var pos = anim.track_get_key_value(i, k) as Vector3
				var new_pos = Vector3(0.0, pos.y, 0.0) # X=0, Z=0, 保留 Y
				anim.track_set_key_value(i, k, new_pos)
			
			print("    -> Removed X/Z displacement, kept Y")
			fixed += 1
	
	return fixed
