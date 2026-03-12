@tool
extends EditorScript
## 動畫骨骼軌道診斷工具
## 使用方法：在 Godot 中開啟此腳本，按 Ctrl+Shift+X 執行

# ======== 配置區域 ========
const ANIMATION_LIBRARY_PATH = "res://Player/animations/movement.res"
const SKELETON_SCENE_PATH = "res://Assets/3D/Characters/Player/Human.fbx"
const TARGET_ANIMATION = "Shimmy_Left" # 要診斷的動畫名稱
# ==========================

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("🔍 動畫骨骼軌道診斷工具")
	print("=".repeat(60))
	
	# 載入動畫庫
	var anim_lib = load(ANIMATION_LIBRARY_PATH) as AnimationLibrary
	if not anim_lib:
		push_error("❌ 無法載入動畫庫: " + ANIMATION_LIBRARY_PATH)
		return
	
	print("✅ 動畫庫載入成功")
	print("   可用動畫數量: ", anim_lib.get_animation_list().size())
	
	# 載入骨架場景
	var skeleton_scene = load(SKELETON_SCENE_PATH) as PackedScene
	if not skeleton_scene:
		push_error("❌ 無法載入骨架場景: " + SKELETON_SCENE_PATH)
		return
	
	var skeleton_instance = skeleton_scene.instantiate()
	var skeleton: Skeleton3D = _find_skeleton(skeleton_instance)
	
	if not skeleton:
		push_error("❌ 在場景中找不到 Skeleton3D 節點")
		skeleton_instance.queue_free()
		return
	
	print("✅ 骨架載入成功")
	print("   骨骼數量: ", skeleton.get_bone_count())
	
	# 收集骨架骨骼名稱
	var skeleton_bones: Dictionary = {} # bone_name -> bone_index
	print("\n📦 骨架骨骼列表:")
	for i in skeleton.get_bone_count():
		var bone_name = skeleton.get_bone_name(i)
		skeleton_bones[bone_name] = i
		print("   [%02d] %s" % [i, bone_name])
	
	# 檢查動畫是否存在
	if not anim_lib.has_animation(TARGET_ANIMATION):
		print("\n❌ 動畫 '%s' 不存在於動畫庫!" % TARGET_ANIMATION)
		print("\n可用動畫列表:")
		for anim_name in anim_lib.get_animation_list():
			print("   - ", anim_name)
		skeleton_instance.queue_free()
		return
	
	var anim = anim_lib.get_animation(TARGET_ANIMATION)
	print("\n🎬 分析動畫: ", TARGET_ANIMATION)
	print("   軌道數量: ", anim.get_track_count())
	print("   長度: %.2f 秒" % anim.length)
	
	# 分析每個軌道
	var matched: Array[String] = []
	var unmatched: Array[Dictionary] = []
	
	print("\n📊 軌道匹配分析:")
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		var track_type = anim.track_get_type(i)
		
		# 提取骨骼名稱
		var bone_name = ""
		if ":" in path_str:
			bone_name = path_str.get_slice(":", 1)
		else:
			var parts = path_str.split("/")
			bone_name = parts[-1] if parts.size() > 0 else ""
		
		# 嘗試匹配
		var match_result = _try_match_bone(bone_name, skeleton_bones)
		
		if match_result["matched"]:
			matched.append(bone_name)
		else:
			unmatched.append({
				"track_index": i,
				"path": path_str,
				"bone_name": bone_name,
				"track_type": _get_track_type_name(track_type),
				"suggestions": match_result["suggestions"]
			})
	
	# 輸出結果
	print("\n" + "=".repeat(60))
	print("📈 匹配結果")
	print("=".repeat(60))
	print("✅ 匹配成功: %d/%d" % [matched.size(), anim.get_track_count()])
	print("❌ 未匹配: %d" % unmatched.size())
	
	# 新增：顯示動畫覆蓋了哪些骨骼
	print("\n" + "=".repeat(60))
	print("📦 動畫軌道包含的骨骼:")
	print("=".repeat(60))
	for bone in matched:
		print("   ✅ ", bone)
	
	# 找出骨架中沒有被動畫覆蓋的骨骼
	var covered_bones: Array[String] = []
	for i in anim.get_track_count():
		var path = anim.track_get_path(i)
		var path_str = str(path)
		var bone_name = ""
		if ":" in path_str:
			bone_name = path_str.get_slice(":", 1)
		else:
			bone_name = path_str.split("/")[-1]
		covered_bones.append(bone_name)
	
	var missing_bones: Array[String] = []
	var upper_body_keywords = ["spine", "chest", "shoulder", "arm", "hand", "neck", "head", "clavicle", "thumb", "index", "middle", "ring", "little", "pinky"]
	var missing_upper: Array[String] = []
	
	for skel_bone in skeleton_bones.keys():
		var found = false
		for anim_bone in covered_bones:
			if skel_bone == anim_bone or skel_bone.to_lower() == anim_bone.to_lower():
				found = true
				break
		if not found:
			missing_bones.append(skel_bone)
			for keyword in upper_body_keywords:
				if keyword in skel_bone.to_lower():
					missing_upper.append(skel_bone)
					break
	
	print("\n" + "=".repeat(60))
	print("⚠️ 骨架中沒有動畫軌道的骨骼 (%d個):" % missing_bones.size())
	print("=".repeat(60))
	for bone in missing_bones:
		var is_upper = bone in missing_upper
		var tag = "🔴 [UPPER]" if is_upper else "⚪"
		print("   %s %s" % [tag, bone])
	
	if missing_upper.size() > 0:
		print("\n" + "⚠️".repeat(20))
		print("警告：動畫缺少 %d 個上半身骨骼軌道！" % missing_upper.size())
		print("這就是上半身呈 T-Pose 的原因！")
		print("解決方案：重新從 Mixamo 導出動畫，確保勾選「In Place」或完整骨架")
		print("⚠️".repeat(20))
	
	# 生成修復映射表建議
	if unmatched.size() > 0:
		print("\n" + "=".repeat(60))
		print("🔧 建議的骨骼名稱映射 (複製到程式碼中)")
		print("=".repeat(60))
		print("const BONE_REMAP: Dictionary = {")
		for item in unmatched:
			if item["suggestions"].size() > 0:
				print('\t"%s": "%s",' % [item["bone_name"], item["suggestions"][0]])
			else:
				print('\t# "%s": "???", # 需要手動查找對應骨骼' % item["bone_name"])
		print("}")
	
	skeleton_instance.queue_free()
	print("\n✅ 診斷完成!")

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null

func _try_match_bone(anim_bone: String, skeleton_bones: Dictionary) -> Dictionary:
	var result = {"matched": false, "suggestions": []}
	
	# 直接匹配
	if skeleton_bones.has(anim_bone):
		result["matched"] = true
		return result
	
	# 嘗試去除前綴 (mixamorig:, mixamorig_)
	var cleaned = anim_bone
	for prefix in ["mixamorig:", "mixamorig_", "mixamo:", "Armature/"]:
		if anim_bone.begins_with(prefix):
			cleaned = anim_bone.substr(prefix.length())
			break
	
	if skeleton_bones.has(cleaned):
		result["matched"] = true
		return result
	
	# 模糊匹配 - 尋找相似的骨骼名稱
	var anim_lower = cleaned.to_lower()
	for skel_bone in skeleton_bones.keys():
		var skel_lower = skel_bone.to_lower()
		
		# 相似度檢查
		if anim_lower in skel_lower or skel_lower in anim_lower:
			result["suggestions"].append(skel_bone)
		elif anim_lower.replace("_", "") == skel_lower.replace("_", ""):
			result["suggestions"].append(skel_bone)
	
	return result

func _get_track_type_name(type: int) -> String:
	match type:
		Animation.TYPE_VALUE: return "Value"
		Animation.TYPE_POSITION_3D: return "Position3D"
		Animation.TYPE_ROTATION_3D: return "Rotation3D"
		Animation.TYPE_SCALE_3D: return "Scale3D"
		Animation.TYPE_BLEND_SHAPE: return "BlendShape"
		Animation.TYPE_METHOD: return "Method"
		Animation.TYPE_BEZIER: return "Bezier"
		Animation.TYPE_AUDIO: return "Audio"
		Animation.TYPE_ANIMATION: return "Animation"
		_: return "Unknown(%d)" % type
