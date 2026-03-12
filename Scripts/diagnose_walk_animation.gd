@tool
extends EditorScript

# 診斷 Walk 動畫的骨骼映射問題
# 對比 Walk 和 Run 動畫的軌道差異

func _run():
	print("=== 診斷 Walk 動畫骨骼映射 ===\n")
	
	var lib_path = "res://Player/assets/characters/player/motion/movement_animations.res"
	var lib = load(lib_path) as AnimationLibrary
	
	if not lib:
		push_error("無法載入動畫庫")
		return
	
	# 對比 Walk_Forward 和 Run_Forward
	var walk_anim = lib.get_animation("Walk_Forward")
	var run_anim = lib.get_animation("Run_Forward")
	
	if not walk_anim or not run_anim:
		push_error("找不到測試動畫")
		return
	
	print("Walk_Forward 軌道數: ", walk_anim.get_track_count())
	print("Run_Forward 軌道數: ", run_anim.get_track_count())
	print()
	
	# 分析 Walk 動畫的軌道
	print("=== Walk_Forward 軌道分析 ===")
	var walk_bones = {}
	var walk_disabled = []
	
	for i in range(walk_anim.get_track_count()):
		var path = str(walk_anim.track_get_path(i))
		var enabled = walk_anim.track_is_enabled(i)
		
		if ":" in path:
			var bone = path.split(":")[1]
			walk_bones[bone] = enabled
			if not enabled:
				walk_disabled.append(bone)
	
	print("Walk 使用的骨骼數: ", walk_bones.size())
	print("Walk 禁用的軌道數: ", walk_disabled.size())
	if walk_disabled.size() > 0:
		print("\nWalk 禁用的骨骼:")
		for bone in walk_disabled:
			print("  - ", bone)
	
	print()
	
	# 分析 Run 動畫的軌道
	print("=== Run_Forward 軌道分析 ===")
	var run_bones = {}
	var run_disabled = []
	
	for i in range(run_anim.get_track_count()):
		var path = str(run_anim.track_get_path(i))
		var enabled = run_anim.track_is_enabled(i)
		
		if ":" in path:
			var bone = path.split(":")[1]
			run_bones[bone] = enabled
			if not enabled:
				run_disabled.append(bone)
	
	print("Run 使用的骨骼數: ", run_bones.size())
	print("Run 禁用的軌道數: ", run_disabled.size())
	if run_disabled.size() > 0:
		print("\nRun 禁用的骨骼:")
		for bone in run_disabled:
			print("  - ", bone)
	
	print()
	
	# 找出差異
	print("=== 軌道差異分析 ===")
	var walk_only = []
	var run_only = []
	
	for bone in walk_bones:
		if not run_bones.has(bone):
			walk_only.append(bone)
	
	for bone in run_bones:
		if not walk_bones.has(bone):
			run_only.append(bone)
	
	if walk_only.size() > 0:
		print("\n只在 Walk 中的骨骼:")
		for bone in walk_only:
			print("  - ", bone, " (enabled: ", walk_bones[bone], ")")
	
	if run_only.size() > 0:
		print("\n只在 Run 中的骨骼:")
		for bone in run_only:
			print("  - ", bone, " (enabled: ", run_bones[bone], ")")
	
	# 檢查啟用狀態差異
	print("\n=== 啟用狀態差異 ===")
	var status_diff = []
	for bone in walk_bones:
		if run_bones.has(bone) and walk_bones[bone] != run_bones[bone]:
			status_diff.append([bone, walk_bones[bone], run_bones[bone]])
	
	if status_diff.size() > 0:
		print("啟用狀態不同的骨骼:")
		for item in status_diff:
			print("  - %s: Walk=%s, Run=%s" % [item[0], item[1], item[2]])
	else:
		print("沒有啟用狀態差異")
	
	# 檢查原始 FBX
	print("\n=== 檢查原始 FBX ===")
	var walk_fbx = "res://Player/assets/characters/player/motion/Human Animations/Animations/Male/Movement/Walk/HumanM@Walk01_Forward.fbx"
	var scene = load(walk_fbx) as PackedScene
	
	if scene:
		var inst = scene.instantiate()
		var anim_player = _find_animation_player(inst)
		
		if anim_player:
			var orig_anim = anim_player.get_animation(anim_player.get_animation_list()[0])
			print("原始 FBX 軌道數: ", orig_anim.get_track_count())
			
			# 檢查原始骨骼名稱
			print("\n原始 FBX 部分骨骼軌道:")
			for i in range(min(10, orig_anim.get_track_count())):
				var path = str(orig_anim.track_get_path(i))
				print("  [%d] %s" % [i, path])
		
		inst.queue_free()
	
	print("\n=== 診斷完成 ===")

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null
