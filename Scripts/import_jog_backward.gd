@tool
extends EditorScript

# 導入新的後退斜向動畫到 AnimationLibrary

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"

# 要導入的 FBX 檔案
var fbx_files = {
	"jog_bl": "res://Player/assets/characters/player/motion/mx/stride8/walk/Jog Backward left.fbx",
	"jog_br": "res://Player/assets/characters/player/motion/mx/stride8/walk/Jog Backward right.fbx"
}

func _run():
	print("=== 導入後退斜向動畫 ===")
	
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入動畫庫: " + ANIM_LIB_PATH)
		return
	
	for anim_name in fbx_files:
		var fbx_path = fbx_files[anim_name]
		print("\n處理: %s (%s)" % [anim_name, fbx_path])
		
		# 載入 FBX 資源
		var fbx_res = load(fbx_path)
		if not fbx_res:
			print("  無法載入 FBX: %s" % fbx_path)
			continue
		
		# FBX 導入後會生成動畫
		# 在 Godot 中，導入的 FBX 動畫通常在 .import 資料夾中
		# 需要手動在 Godot 中設定動畫導入
		
		print("  FBX 資源類型: %s" % fbx_res.get_class())
		
		# 如果是 PackedScene，實例化並查找動畫
		if fbx_res is PackedScene:
			var instance = fbx_res.instantiate()
			
			# 查找 AnimationPlayer
			var anim_player = _find_animation_player(instance)
			if anim_player:
				print("  找到 AnimationPlayer，動畫列表:")
				for name in anim_player.get_animation_list():
					print("    - %s" % name)
					
					# 複製動畫到 library
					var anim = anim_player.get_animation(name)
					if anim:
						var new_name = anim_name # 使用我們定義的名稱
						if lib.has_animation(new_name):
							lib.remove_animation(new_name)
						lib.add_animation(new_name, anim.duplicate())
						print("    已添加: %s" % new_name)
			else:
				print("  找不到 AnimationPlayer")
			
			instance.queue_free()
	
	# 儲存
	var error = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if error == OK:
		print("\n已儲存動畫庫！")
	else:
		push_error("儲存失敗: %d" % error)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null
