@tool
extends EditorScript

## 為走路/跑步動畫添加腳步事件（Method Track）
## 假設標準走路循環：0% 左腳著地, 50% 右腳著地
## 用法：Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"
const NODE_PATH = "." # 根節點接收方法調用

# 需要處理的動畫前綴
const WALK_ANIMS = [
	"Walk_Forward", "Walk_Backward", "Walk_Left", "Walk_Right",
	"Walk_ForwardLeft", "Walk_ForwardRight", "Walk_BackwardLeft", "Walk_BackwardRight"
]
const RUN_ANIMS = [
	"Run_Forward", "Run_Backward", "Run_Left", "Run_Right",
	"Run_ForwardLeft", "Run_ForwardRight", "Run_BackwardLeft", "Run_BackwardRight"
]

func _run() -> void:
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: ", LIB_PATH)
		return
	
	print("\n=== Adding Footstep Events ===")
	
	var count = 0
	for anim_name in WALK_ANIMS + RUN_ANIMS:
		if lib.has_animation(anim_name):
			if _add_footstep_events(lib, anim_name):
				count += 1
	
	var err = ResourceSaver.save(lib, LIB_PATH)
	if err == OK:
		print("\n=== SUCCESS: Added events to ", count, " animations ===")
	else:
		print("ERROR saving: ", err)

func _add_footstep_events(lib: AnimationLibrary, anim_name: String) -> bool:
	var anim = lib.get_animation(anim_name)
	if not anim:
		return false
	
	# 檢查是否已有腳步軌道
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		if path == NODE_PATH and anim.track_get_type(i) == Animation.TYPE_METHOD:
			print("  SKIP: ", anim_name, " (already has method track)")
			return false
	
	# 添加 Method Track
	var track_idx = anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(track_idx, NODE_PATH)
	
	var length = anim.length
	
	# 在 0% 添加左腳事件
	anim.track_insert_key(track_idx, 0.0, {
		"method": "on_foot_left",
		"args": []
	})
	
	# 在 50% 添加右腳事件
	anim.track_insert_key(track_idx, length * 0.5, {
		"method": "on_foot_right",
		"args": []
	})
	
	print("  ADDED: ", anim_name, " (L@0.0s, R@", "%.2f" % (length * 0.5), "s)")
	return true
