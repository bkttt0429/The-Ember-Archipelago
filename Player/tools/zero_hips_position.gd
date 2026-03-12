@tool
extends EditorScript

## 將動畫的 Hips 位置完全歸零 (X=0, Y=0, Z=0)
## 這會讓動畫變成完全 in-place，不會有任何位移
## 用法：Ctrl+Shift+X 執行

const ANIM_NAMES = ["Run_To_Stop", "Stop_Walking"]
const LIB_PATH = "res://Player/animations/movement.res"

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	for anim_name in ANIM_NAMES:
		_zero_hips_position(lib, anim_name)
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== SUCCESS: Library saved! ===")
	else:
		print("ERROR saving: ", err)

func _zero_hips_position(lib: AnimationLibrary, anim_name: String) -> void:
	if not lib.has_animation(anim_name):
		print("SKIP: Animation not found: ", anim_name)
		return
	
	var anim = lib.get_animation(anim_name)
	print("\n--- Processing: ", anim_name, " ---")
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		
		# 只處理 Hips 的位置軌道
		if path.contains("Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			print("  Found Hips position: ", key_count, " keys")
			
			# 把所有 key 都設為 (0, 0, 0)
			for key_idx in key_count:
				anim.track_set_key_value(i, key_idx, Vector3.ZERO)
			
			print("  All positions set to (0, 0, 0)!")
			return
	
	print("  WARNING: No Hips position track found")
