@tool
extends EditorScript

## 診斷動畫軌道結構
## 運行方式: Godot Editor → Script → Run (Ctrl+Shift+X)

func _run() -> void:
	print("=== 診斷動畫軌道 ===")
	
	var lib_path = "res://Player/animations/movement.res"
	var lib = load(lib_path) as AnimationLibrary
	if not lib:
		push_error("找不到 AnimationLibrary: " + lib_path)
		return
	
	var anim_name = "Hang_To_Crouch"
	if not lib.has_animation(anim_name):
		push_error("找不到動畫: " + anim_name)
		return
	
	var anim = lib.get_animation(anim_name)
	print("動畫: ", anim_name)
	print("長度: ", anim.length, " 秒")
	print("軌道數: ", anim.get_track_count())
	print("")
	
	for i in range(anim.get_track_count()):
		var path = anim.track_get_path(i)
		var track_type = anim.track_get_type(i)
		var key_count = anim.track_get_key_count(i)
		
		var type_name = ""
		match track_type:
			Animation.TYPE_VALUE: type_name = "VALUE"
			Animation.TYPE_POSITION_3D: type_name = "POSITION_3D"
			Animation.TYPE_ROTATION_3D: type_name = "ROTATION_3D"
			Animation.TYPE_SCALE_3D: type_name = "SCALE_3D"
			Animation.TYPE_BLEND_SHAPE: type_name = "BLEND_SHAPE"
			Animation.TYPE_METHOD: type_name = "METHOD"
			Animation.TYPE_BEZIER: type_name = "BEZIER"
			Animation.TYPE_AUDIO: type_name = "AUDIO"
			Animation.TYPE_ANIMATION: type_name = "ANIMATION"
			_: type_name = "UNKNOWN(" + str(track_type) + ")"
		
		# 只顯示含有位置資訊的軌道或根骨骼相關
		if track_type == Animation.TYPE_POSITION_3D:
			print("[", i, "] ", type_name, " | ", path, " | keys: ", key_count)
			
			# 顯示第一個和最後一個關鍵幀的值
			if key_count > 0:
				var first_val = anim.track_get_key_value(i, 0)
				var last_val = anim.track_get_key_value(i, key_count - 1)
				print("      第一幀: ", first_val)
				print("      最後幀: ", last_val)
				var delta = last_val - first_val
				print("      位移差: ", delta, " (長度: %.2f)" % delta.length())
	
	print("")
	print("=== 完成 ===")
