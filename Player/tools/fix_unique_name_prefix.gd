@tool
extends EditorScript

## 修復動畫軌道路徑 - 添加 % 前綴 (Unique Name Binding)
## 將 "GeneralSkeleton:Bone" 轉換為 "%GeneralSkeleton:Bone"
## 使用方法：在 Godot 中開啟此腳本，按 Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

# 需要修復的動畫列表 (之前被破壞的動畫)
const ANIMS_TO_FIX = [
	"Breathing_Idle",
	"Shimmy_Left",
	"Shimmy_Right",
]

func _run() -> void:
	print("\n=== 修復動畫軌道路徑 (添加 % 前綴) ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	var total_fixed = 0
	
	for anim_name in ANIMS_TO_FIX:
		if not lib.has_animation(anim_name):
			print("SKIP: '%s' not found" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		var fixed_count = _fix_unique_name_prefix(anim)
		total_fixed += fixed_count
		print("Fixed %d tracks in '%s'" % [fixed_count, anim_name])
	
	if total_fixed > 0:
		var err = ResourceSaver.save(lib, LIB_PATH)
		if err == OK:
			print("\nSUCCESS: Saved to %s (total %d tracks fixed)" % [LIB_PATH, total_fixed])
		else:
			print("\nERROR saving: ", err)
	else:
		print("\nNo tracks needed fixing")
	
	print("\n=== Done ===")

func _fix_unique_name_prefix(anim: Animation) -> int:
	var fixed = 0
	
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# 檢查是否以 "GeneralSkeleton:" 開頭 (缺少 % 前綴)
		if path_str.begins_with("GeneralSkeleton:"):
			var new_path = "%" + path_str
			anim.track_set_path(i, NodePath(new_path))
			fixed += 1
	
	return fixed
