@tool
extends EditorScript

## 檢查 Shimmy 動畫軌道路徑是否與骨架匹配

const LIB_PATH = "res://Player/animations/movement.res"
const SCENE_PATH = "res://Player/test/PlayerCapsuleTest.tscn"

func _run() -> void:
	print("\n=== 檢查動畫軌道路徑 ===\n")
	
	var lib = load(LIB_PATH) as AnimationLibrary
	var scene = load(SCENE_PATH) as PackedScene
	
	if not lib or not scene:
		print("ERROR: Cannot load resources")
		return
	
	var instance = scene.instantiate()
	var skeleton: Skeleton3D = _find_skeleton(instance)
	
	if not skeleton:
		print("ERROR: Cannot find skeleton")
		instance.queue_free()
		return
	
	# 獲取骨架中的所有骨骼名稱
	var bone_names = []
	for i in skeleton.get_bone_count():
		bone_names.append(skeleton.get_bone_name(i))
	
	print("骨架中有 %d 個骨骼" % bone_names.size())
	print("前 5 個骨骼: %s" % str(bone_names.slice(0, 5)))
	
	# 檢查 Shimmy_Left 動畫
	var anim = lib.get_animation("Shimmy_Left")
	if not anim:
		print("ERROR: Shimmy_Left not found")
		instance.queue_free()
		return
	
	print("\n=== Shimmy_Left 動畫軌道 ===")
	var matched = 0
	var unmatched = 0
	var unmatched_list = []
	
	for i in anim.get_track_count():
		var path = str(anim.track_get_path(i))
		# 提取骨骼名稱（從 "%GeneralSkeleton:Hips" 提取 "Hips"）
		var bone_name = ""
		if ":" in path:
			bone_name = path.split(":")[-1]
		
		if bone_name in bone_names:
			matched += 1
		else:
			unmatched += 1
			if unmatched <= 10:
				unmatched_list.append(bone_name)
	
	print("匹配: %d, 不匹配: %d" % [matched, unmatched])
	if unmatched > 0:
		print("不匹配的骨骼: %s" % str(unmatched_list))
	
	# 檢查動畫路徑格式
	print("\n=== 動畫軌道路徑範例 ===")
	for i in min(5, anim.get_track_count()):
		print("  路徑: %s" % str(anim.track_get_path(i)))
	
	instance.queue_free()
	print("\n✅ 檢查完成")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null
