@tool
extends EditorScript
## Motion Matching Feature 配置腳本 v2
## 
## 重要發現：Bake 按鈕從 AnimationPlayer 的 animation library 讀取 features，
## 不是從 MMAnimationNode.animation_library。
## 所以 features 必須設在 AnimationPlayer 中名為 "mm" 的 MMAnimationLibrary 上。
##
## 用法: File > Run Script > 選擇此腳本

func _run() -> void:
	print("\n=== MM Feature 配置 v2 ===\n")
	
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		printerr("ERROR: 請先打開 MotionMatchTest.tscn")
		return
	
	# 1. 取得 AnimationPlayer (也是 AnimationMixer)
	var anim_player: AnimationPlayer = root.get_node_or_null("Player/AnimationPlayer")
	if not anim_player:
		printerr("ERROR: 找不到 Player/AnimationPlayer")
		return
	print("✓ AnimationPlayer 找到")
	
	# 2. 列出所有 animation libraries
	print("  現有 libraries:")
	for lib_name in anim_player.get_animation_library_list():
		var lib = anim_player.get_animation_library(lib_name)
		var anim_count = lib.get_animation_list().size() if lib else 0
		print("    '", lib_name, "' → ", lib.get_class() if lib else "null", " (", anim_count, " animations)")
	
	# 3. 取得 "mm" library — 如果不存在就創建
	var mm_lib_name := "mm"
	var mm_lib = anim_player.get_animation_library(mm_lib_name)
	
	if not mm_lib:
		# 檢查有沒有其他名字的 library（可能是 "" 或其他名稱）
		var lib_list = anim_player.get_animation_library_list()
		if lib_list.size() > 0:
			# 用第一個現有的 library
			mm_lib_name = lib_list[0]
			mm_lib = anim_player.get_animation_library(mm_lib_name)
			print("  使用現有 library: '", mm_lib_name, "'")
		
		if not mm_lib:
			printerr("ERROR: 找不到任何 animation library")
			return
	
	print("✓ Library '", mm_lib_name, "' 類型: ", mm_lib.get_class())
	
	# 4. 檢查是否為 MMAnimationLibrary
	if mm_lib.get_class() != "MMAnimationLibrary":
		print("  ⚠ Library 不是 MMAnimationLibrary，需要替換...")
		
		# 保存現有動畫
		var existing_anims := {}
		for anim_name in mm_lib.get_animation_list():
			existing_anims[anim_name] = mm_lib.get_animation(anim_name)
		print("  保存了 ", existing_anims.size(), " 個動畫")
		
		# 創建 MMAnimationLibrary 並複製動畫
		if ClassDB.class_exists("MMAnimationLibrary"):
			var new_lib = ClassDB.instantiate("MMAnimationLibrary")
			for anim_name in existing_anims:
				new_lib.add_animation(anim_name, existing_anims[anim_name])
			
			# 替換
			anim_player.remove_animation_library(mm_lib_name)
			anim_player.add_animation_library(mm_lib_name, new_lib)
			mm_lib = new_lib
			print("  ✓ 已替換為 MMAnimationLibrary (保留所有動畫)")
		else:
			printerr("  ERROR: MMAnimationLibrary 類型不存在")
			return
	
	# 5. 列印骨架資訊
	var skeleton: Skeleton3D = root.get_node_or_null("Player/Visuals/Human/Armature/GeneralSkeleton")
	if skeleton:
		print("\n骨架骨骼 (前 20 個):")
		for i in range(mini(20, skeleton.get_bone_count())):
			print("  [", i, "] ", skeleton.get_bone_name(i))
		print("  ... 共 ", skeleton.get_bone_count(), " 個\n")
	
	# 6. 檢查現有 features
	var existing_features = mm_lib.get("features")
	print("目前 features: ", existing_features.size() if existing_features else "null/empty")
	
	# 7. 建立 Features
	var features: Array = []
	
	# --- MMTrajectoryFeature ---
	if ClassDB.class_exists("MMTrajectoryFeature"):
		var traj = ClassDB.instantiate("MMTrajectoryFeature")
		if traj:
			traj.set("past_frames", 0)
			traj.set("future_delta_time", 0.5)
			traj.set("future_frames", 4)
			traj.set("include_facing", true)
			traj.set("facing_weight", 10.0)
			traj.set("include_height", false)
			features.append(traj)
			print("✓ MMTrajectoryFeature")
			print("  dim_count = ", traj.get_dimension_count())
	
	# --- MMBoneDataFeature ---
	if ClassDB.class_exists("MMBoneDataFeature"):
		var bone_feat = ClassDB.instantiate("MMBoneDataFeature")
		if bone_feat:
			var bone_names := PackedStringArray([
				"LeftUpperLeg",
				"LeftLowerLeg",
				"LeftFoot",
				"RightUpperLeg",
				"RightLowerLeg",
				"RightFoot"
			])
			bone_feat.set("bone_names", bone_names)
			features.append(bone_feat)
			print("✓ MMBoneDataFeature")
			print("  bones: ", bone_names)
			print("  dim_count = ", bone_feat.get_dimension_count())
	
	# 8. 設定 features
	if features.size() == 0:
		printerr("ERROR: 沒有建立任何 Feature")
		return
	
	mm_lib.set("features", features)
	
	# 驗證
	var check = mm_lib.get("features")
	print("\n設定後 features.size() = ", check.size() if check else "null")
	if check:
		for i in range(check.size()):
			var f = check[i]
			print("  [", i, "] ", f.get_class() if f else "null", " dim=", f.get_dimension_count() if f else -1)
	
	# 9. sampling_rate
	mm_lib.set("sampling_rate", 4.0)
	print("✓ sampling_rate = 4.0")
	
	# 10. 也設定 MMAnimationNode 指向同一個 library
	var anim_tree: AnimationTree = root.get_node_or_null("Player/AnimationTree")
	if anim_tree:
		var tree_root = anim_tree.tree_root
		if not tree_root:
			if ClassDB.class_exists("MMAnimationNode"):
				tree_root = ClassDB.instantiate("MMAnimationNode")
				anim_tree.tree_root = tree_root
				print("✓ 建立 MMAnimationNode")
		if tree_root:
			tree_root.set("animation_library", mm_lib)
			print("✓ MMAnimationNode.animation_library → 同一個 MMAnimationLibrary")
	
	# 10b. 清除 root_motion_track（此骨架沒有地面層級的 Root 骨骼，Hips 在腰部）
	if anim_tree:
		anim_tree.set("root_motion_track", NodePath(""))
		print("✓ root_motion_track 已清除（無 Root 骨骼）")
	
	# 11. 保存
	EditorInterface.save_scene()
	print("\n✓ 場景已保存")
	
	print("\n=== 配置完成！===")
	print("現在可以按 Bake 按鈕了")
	print("Bake 會從 AnimationPlayer 的 '", mm_lib_name, "' library 讀取 features")
