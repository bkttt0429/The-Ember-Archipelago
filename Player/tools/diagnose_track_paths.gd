@tool
extends EditorScript

## 診斷動畫軌道路徑 - 找出正確的路徑格式
## 使用方法：在 Godot 中開啟此腳本，按 Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"

# 分析這些動畫的軌道路徑
const ANIMS_TO_CHECK = ["Idle", "Walk_Forward", "Breathing_Idle", "Shimmy_Left"]

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("🔍 動畫軌道路徑診斷")
	print("=".repeat(60))
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	print("可用動畫: ", lib.get_animation_list())
	
	for anim_name in ANIMS_TO_CHECK:
		if not lib.has_animation(anim_name):
			print("\n❌ '%s' 不存在" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		print("\n" + "=".repeat(60))
		print("📊 動畫: %s (軌道數: %d)" % [anim_name, anim.get_track_count()])
		print("=".repeat(60))
		
		# 顯示前 10 個軌道
		var count = min(10, anim.get_track_count())
		for i in count:
			var path = anim.track_get_path(i)
			print("  [%02d] %s" % [i, str(path)])
		
		if anim.get_track_count() > 10:
			print("  ... 還有 %d 個軌道" % (anim.get_track_count() - 10))
	
	print("\n✅ 診斷完成")
