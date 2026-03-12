@tool
extends EditorScript

# 比較 Mannequin 和 Human Animations FBX 的骨骼名稱
# 運行方式：Godot 編輯器中 File > Run

const MANNEQUIN_PATH = "res://Player/assets/characters/player/Characters_Mannequin.fbx"
const HUMAN_ANIM_PATH = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/Movement/Walk/HumanM@Walk01_Forward.fbx"

func _run():
	print("=== 骨骼名稱對比 ===\n")
	
	# 載入 Mannequin
	print("【Mannequin 骨骼】")
	var mannequin_bones = _get_skeleton_bones(MANNEQUIN_PATH)
	for bone in mannequin_bones:
		print("  ", bone)
	
	print("\n【Human Animation FBX 骨骼】")
	var anim_bones = _get_skeleton_bones(HUMAN_ANIM_PATH)
	for bone in anim_bones:
		print("  ", bone)
	
	# 比較差異
	print("\n【差異分析】")
	print("Mannequin 骨骼數量: ", mannequin_bones.size())
	print("Animation 骨骼數量: ", anim_bones.size())
	
	print("\n只在 Mannequin 中:")
	for bone in mannequin_bones:
		if not bone in anim_bones:
			print("  - ", bone)
	
	print("\n只在 Animation 中:")
	for bone in anim_bones:
		if not bone in mannequin_bones:
			print("  + ", bone)

func _get_skeleton_bones(path: String) -> Array:
	var bones = []
	var scene = load(path) as PackedScene
	if not scene:
		push_error("無法載入: " + path)
		return bones
	
	var inst = scene.instantiate()
	_find_skeleton_bones(inst, bones)
	inst.queue_free()
	return bones

func _find_skeleton_bones(node: Node, bones: Array):
	if node is Skeleton3D:
		for i in range(node.get_bone_count()):
			bones.append(node.get_bone_name(i))
	for child in node.get_children():
		_find_skeleton_bones(child, bones)
