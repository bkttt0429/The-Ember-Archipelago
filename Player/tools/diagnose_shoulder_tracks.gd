@tool
extends EditorScript

## 診斷 Shimmy 動畫的肩膀骨骼軌道
## 使用方法：在 Godot 中開啟此腳本，按 Ctrl+Shift+X 執行

const LIB_PATH = "res://Player/animations/movement.res"
const ANIMS_TO_CHECK = ["Shimmy_Left", "Idle", "Hanging_Idle"]

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("🔍 肩膀骨骼軌道診斷")
	print("=".repeat(60))
	
	var lib = load(LIB_PATH) as AnimationLibrary
	if not lib:
		print("ERROR: Cannot load library: " + LIB_PATH)
		return
	
	for anim_name in ANIMS_TO_CHECK:
		if not lib.has_animation(anim_name):
			print("\n❌ '%s' 不存在" % anim_name)
			continue
		
		var anim = lib.get_animation(anim_name)
		print("\n" + "=".repeat(60))
		print("📊 動畫: %s" % anim_name)
		print("=".repeat(60))
		
		# 搜尋 shoulder 相關軌道
		var shoulder_tracks: Array[String] = []
		var arm_tracks: Array[String] = []
		
		for i in anim.get_track_count():
			var path = str(anim.track_get_path(i))
			var bone_name = path.get_slice(":", 1) if ":" in path else path.split("/")[-1]
			
			if "Shoulder" in bone_name or "Clavicle" in bone_name:
				shoulder_tracks.append("  [%02d] %s" % [i, path])
			elif "Arm" in bone_name or "arm" in bone_name:
				arm_tracks.append("  [%02d] %s" % [i, path])
		
		print("\n🦴 肩膀軌道 (%d):" % shoulder_tracks.size())
		for t in shoulder_tracks:
			print(t)
		if shoulder_tracks.is_empty():
			print("  ⚠️ 無肩膀軌道！")
		
		print("\n💪 手臂軌道 (%d):" % arm_tracks.size())
		for t in arm_tracks:
			print(t)
	
	print("\n✅ 診斷完成")
