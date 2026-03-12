@tool
extends EditorScript

# 清理動畫庫中無法解析的軌道 (手指骨骼等)
# 這會永久修改 animations_mx.res

const ANIM_LIB_PATH = "res://Player/assets/characters/player/motion/animations_mx.res"
const SKELETON_PATH = "res://Assets/Models/character/mannequin.fbx"

# 要移除的骨骼名稱模式 (子字串匹配)
const REMOVE_PATTERNS = [
	"Thumb", "Index", "Middle", "Ring", "Pinky", # 手指
	"HandThumb", "HandIndex", "HandMiddle", "HandRing", "HandPinky"
]

func _run():
	print("開始清理動畫庫...")
	
	# 載入動畫庫
	var lib = load(ANIM_LIB_PATH) as AnimationLibrary
	if not lib:
		push_error("無法載入動畫庫: " + ANIM_LIB_PATH)
		return
	
	# 取得模型骨架
	var valid_bones = _get_skeleton_bones()
	print("模型骨骼數量: %d" % valid_bones.size())
	
	var total_removed = 0
	var anim_names = lib.get_animation_list()
	
	for anim_name in anim_names:
		var anim = lib.get_animation(anim_name)
		if not anim:
			continue
		
		var removed_count = _clean_animation(anim, valid_bones)
		if removed_count > 0:
			print("  %s: 移除 %d 個軌道" % [anim_name, removed_count])
			total_removed += removed_count
	
	# 儲存修改後的動畫庫
	var error = ResourceSaver.save(lib, ANIM_LIB_PATH)
	if error == OK:
		print("成功儲存！共移除 %d 個無效軌道" % total_removed)
	else:
		push_error("儲存失敗: %d" % error)

func _get_skeleton_bones() -> Array:
	var bones = []
	var scene = load(SKELETON_PATH)
	if not scene:
		print("警告: 無法載入骨架場景，將使用模式匹配")
		return []
	
	var inst = scene.instantiate()
	var skeleton = _find_skeleton(inst)
	if skeleton:
		for i in range(skeleton.get_bone_count()):
			bones.append(skeleton.get_bone_name(i))
	inst.queue_free()
	return bones

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found = _find_skeleton(child)
		if found:
			return found
	return null

func _clean_animation(anim: Animation, valid_bones: Array) -> int:
	var tracks_to_remove = []
	
	for i in range(anim.get_track_count()):
		var path = str(anim.track_get_path(i))
		
		# 只處理骨骼軌道
		if ":" not in path:
			continue
		
		var parts = path.split(":")
		if parts.size() < 2:
			continue
		
		var bone_name = parts[1]
		var should_remove = false
		
		# 方法 1: 如果有有效骨骼列表，檢查骨骼是否存在
		if valid_bones.size() > 0:
			if bone_name not in valid_bones:
				should_remove = true
		
		# 方法 2: 使用模式匹配移除手指骨骼
		for pattern in REMOVE_PATTERNS:
			if pattern in bone_name:
				should_remove = true
				break
		
		if should_remove:
			tracks_to_remove.append(i)
	
	# 從後往前移除 (避免索引錯位)
	tracks_to_remove.reverse()
	for idx in tracks_to_remove:
		anim.remove_track(idx)
	
	return tracks_to_remove.size()
