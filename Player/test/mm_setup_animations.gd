@tool
extends EditorScript
## Motion Matching 動畫設置腳本
## 用法: 在 Godot 編輯器中 File > Run Script > 選擇此腳本
##
## 注意: FBX 檔案必須先配置 BoneMap retarget（B-* → Humanoid Profile）
##       .import 檔案已經通過 Python 腳本批量修改完成

# FBX 裡的骨架節點路徑 → 我們場景中的骨架節點路徑
# 重導入後 FBX 的 track 路徑可能是 Rig/GeneralSkeleton 或 Rig/Skeleton3D
const SKELETON_PATH_REMAP := {
	"%GeneralSkeleton": "Armature/GeneralSkeleton",
	"Rig/Skeleton3D": "Armature/GeneralSkeleton",
	"Rig/GeneralSkeleton": "Armature/GeneralSkeleton",
	"Armature/Skeleton3D": "Armature/GeneralSkeleton",
}

# 沒有對應 target 骨骼的 track，直接移除
const SKIP_BONES: PackedStringArray = ["B-spineProxy", "B-jaw", "B-handProp.L", "B-handProp.R"]

func _run() -> void:
	print("\n=== Motion Matching 動畫設置開始 ===\n")
	
	# 1. 打開場景
	EditorInterface.open_scene_from_path("res://Player/test/MotionMatchTest.tscn")
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		printerr("ERROR: 無法取得場景根節點")
		return
	
	# 2. 取得 AnimationPlayer
	var anim_player: AnimationPlayer = root.get_node_or_null("Player/AnimationPlayer")
	if not anim_player:
		printerr("ERROR: 找不到 Player/AnimationPlayer")
		return
	
	# 3. 檢查骨骼名稱
	var skeleton: Skeleton3D = root.get_node_or_null("Player/Visuals/Human/Armature/GeneralSkeleton")
	if skeleton:
		print("目標骨架: ", skeleton.name, " | 骨骼數: ", skeleton.get_bone_count())
		var sample_count := mini(10, skeleton.get_bone_count())
		print("  前 ", sample_count, " 個骨骼:")
		for i in range(sample_count):
			print("    [", i, "] ", skeleton.get_bone_name(i))
	else:
		print("WARNING: 找不到骨架")
	
	# 4. 先載入一個測試動畫，印出原始 track 路徑（供診斷）
	_debug_print_first_anim_tracks()
	
	# 5. 定義動畫清單
	var anims := _get_animation_list()
	
	# 6. 逐一載入動畫
	var lib := AnimationLibrary.new()
	var success_count := 0
	var fail_count := 0
	
	for anim_name in anims:
		var path: String = anims[anim_name]
		var anim := _extract_animation_from_fbx(path)
		if anim:
			_remap_skeleton_path(anim)
			lib.add_animation(anim_name, anim)
			print("  ✓ ", anim_name)
			success_count += 1
		else:
			printerr("  ✗ ", anim_name, " — 載入失敗: ", path)
			fail_count += 1
	
	print("\n載入完成: ", success_count, " 成功, ", fail_count, " 失敗")
	
	# 7. 清除舊動畫，加入新的
	for existing_lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(existing_lib_name)
	anim_player.add_animation_library("", lib)
	print("AnimationLibrary 已加入 AnimationPlayer")
	
	# 8. 設置 AnimationTree
	var anim_tree: AnimationTree = root.get_node_or_null("Player/AnimationTree")
	if anim_tree:
		_setup_animation_tree(anim_tree)
	else:
		printerr("ERROR: 找不到 AnimationTree")
	
	# 9. 保存場景
	EditorInterface.save_scene()
	
	print("\n=== 設置完成！===")
	print("下一步：")
	print("  1. 檢查 AnimationPlayer 是否有所有動畫")
	print("  2. 選中 MMAnimationLibrary → 底部面板點擊 Bake")
	print("  3. Ctrl+S 保存場景")
	print("  4. F5 運行測試")


func _debug_print_first_anim_tracks() -> void:
	# 載入 idle 動畫來看看 retarget 後的 track 路徑
	var test_path := "res://Player/assets/characters/player/motion/Human Animations/Animations/Female/Idles/HumanF@Idle01.fbx"
	var scene_res = load(test_path)
	if not scene_res or not scene_res is PackedScene:
		print("  [診斷] 無法載入測試 FBX")
		return
	
	var instance: Node = scene_res.instantiate()
	var src_player: AnimationPlayer = _find_animation_player(instance)
	if src_player:
		for lib_name in src_player.get_animation_library_list():
			var src_lib := src_player.get_animation_library(lib_name)
			for anim_name in src_lib.get_animation_list():
				if anim_name == "RESET":
					continue
				var anim := src_lib.get_animation(anim_name)
				print("\n  [診斷] FBX 動畫 '", anim_name, "' 的前 5 個 track:")
				for i in range(mini(5, anim.get_track_count())):
					print("    Track[", i, "]: ", anim.track_get_path(i))
				break
			break
	
	# 也檢查 skeleton 節點
	var skel := _find_skeleton(instance)
	if skel:
		print("  [診斷] FBX Skeleton 路徑: ", instance.get_path_to(skel))
		print("  [診斷] FBX Skeleton 名稱: ", skel.name)
		print("  [診斷] 前 5 個骨骼:")
		for i in range(mini(5, skel.get_bone_count())):
			print("    [", i, "] ", skel.get_bone_name(i))
	
	instance.free()
	print()


func _get_animation_list() -> Dictionary:
	var anims := {}
	var base := "res://Player/assets/characters/player/motion/Human Animations/Animations/Female/"
	
	# Idles
	anims["idle_01"] = base + "Idles/HumanF@Idle01.fbx"
	anims["idle_02"] = base + "Idles/HumanF@Idle02.fbx"
	
	# Walk [RM] - 8 方向
	var walk_dirs: PackedStringArray = ["Forward", "Backward", "Left", "Right", "ForwardLeft", "ForwardRight", "BackwardLeft", "BackwardRight"]
	for dir in walk_dirs:
		var key := "walk_" + dir.to_snake_case()
		anims[key] = base + "Movement/Walk/RootMotion/HumanF@Walk01_" + dir + " [RM].fbx"
	
	# Run [RM] - 8 方向
	var run_dirs: PackedStringArray = ["Forward", "Backward", "Left", "Right", "ForwardLeft", "ForwardRight", "BackwardLeft", "BackwardRight"]
	for dir in run_dirs:
		var key := "run_" + dir.to_snake_case()
		anims[key] = base + "Movement/Run/RootMotion/HumanF@Run01_" + dir + " [RM].fbx"
	
	# Sprint [RM] - 5 方向
	var sprint_dirs: PackedStringArray = ["Forward", "Left", "Right", "ForwardLeft", "ForwardRight"]
	for dir in sprint_dirs:
		var key := "sprint_" + dir.to_snake_case()
		anims[key] = base + "Movement/Sprint/RootMotion/HumanF@Sprint01_" + dir + " [RM].fbx"
	
	# 轉彎
	anims["turn_left"] = base + "Movement/Turn/HumanF@Turn01_Left [RM].fbx"
	anims["turn_right"] = base + "Movement/Turn/HumanF@Turn01_Right [RM].fbx"
	
	# 跳躍
	anims["jump_full"] = base + "Movement/Jump/HumanF@Jump01 [RM].fbx"
	anims["jump_begin"] = base + "Movement/Jump/HumanF@Jump01 [RM] - Begin.fbx"
	anims["jump_land"] = base + "Movement/Jump/HumanF@Jump01 [RM] - Land.fbx"
	
	return anims


func _extract_animation_from_fbx(path: String) -> Animation:
	var scene_res = load(path)
	if not scene_res or not scene_res is PackedScene:
		return null
	
	var instance: Node = scene_res.instantiate()
	var src_player: AnimationPlayer = _find_animation_player(instance)
	
	if not src_player:
		instance.free()
		return null
	
	# 取得第一個動畫（跳過 RESET）
	var result: Animation = null
	for lib_name in src_player.get_animation_library_list():
		var src_lib := src_player.get_animation_library(lib_name)
		for anim_name in src_lib.get_animation_list():
			if anim_name == "RESET":
				continue
			var anim := src_lib.get_animation(anim_name)
			result = anim.duplicate()
			break
		if result:
			break
	
	instance.free()
	return result


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


## 重映射骨架節點路徑 + 移除無效 tracks
func _remap_skeleton_path(anim: Animation) -> void:
	var tracks_to_remove: PackedInt32Array = []
	
	for i in range(anim.get_track_count()):
		var path_str := str(anim.track_get_path(i))
		
		# 檢查是否含有無效骨骼名稱
		var colon_idx := path_str.find(":")
		if colon_idx >= 0:
			var bone_name := path_str.substr(colon_idx + 1)
			if bone_name in SKIP_BONES:
				tracks_to_remove.append(i)
				continue
		
		# 重映射骨架節點路徑
		for src_path in SKELETON_PATH_REMAP:
			if path_str.begins_with(src_path):
				path_str = SKELETON_PATH_REMAP[src_path] + path_str.substr(src_path.length())
				anim.track_set_path(i, NodePath(path_str))
				break
	
	# 從後往前移除無效 tracks
	for j in range(tracks_to_remove.size() - 1, -1, -1):
		anim.remove_track(tracks_to_remove[j])


func _setup_animation_tree(anim_tree: AnimationTree) -> void:
	# 嘗試建立 MMAnimationNode
	if not ClassDB.class_exists("MMAnimationNode"):
		printerr("ERROR: MMAnimationNode 類型不存在 — GDExtension 未載入？")
		printerr("  請確認 addons/godot-motion-matching/addons/motion_matching/bin/ 有 DLL")
		return
	
	var mm_anim_node = ClassDB.instantiate("MMAnimationNode")
	if not mm_anim_node:
		printerr("ERROR: 無法建立 MMAnimationNode")
		return
	
	anim_tree.tree_root = mm_anim_node
	print("AnimationTree.tree_root → MMAnimationNode ✓")
	
	# 建立 MMAnimationLibrary
	if ClassDB.class_exists("MMAnimationLibrary"):
		var mm_lib = ClassDB.instantiate("MMAnimationLibrary")
		if mm_lib:
			var features := []
			
			if ClassDB.class_exists("MMTrajectoryFeature"):
				var traj = ClassDB.instantiate("MMTrajectoryFeature")
				if traj:
					features.append(traj)
					print("  + MMTrajectoryFeature ✓")
			
			if ClassDB.class_exists("MMBoneDataFeature"):
				var bone_feat = ClassDB.instantiate("MMBoneDataFeature")
				if bone_feat:
					features.append(bone_feat)
					print("  + MMBoneDataFeature ✓")
			
			if features.size() > 0:
				mm_lib.set("features", features)
			
			mm_anim_node.set("animation_library", mm_lib)
			print("MMAnimationNode.animation_library → MMAnimationLibrary ✓")
	else:
		printerr("WARNING: MMAnimationLibrary 類型不存在")
