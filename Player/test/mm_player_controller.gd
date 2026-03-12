class_name MMPlayerController extends Node

## Motion Matching 測試用簡化 Player Controller
## 將 WASD 輸入轉換為 MMCharacter.target_velocity

@export var walk_speed := 1.5
@export var run_speed := 3.5
@export var sprint_speed := 5.5
@export var jump_speed := 4.0

var _character: Node # MMCharacter
var _camera: Node3D

func _ready() -> void:
	# 自動尋找 MMCharacter（父節點）和 CameraPivot
	_character = get_parent()
	if _character and _character.get_class() != "MMCharacter":
		var p = _character
		while p and p.get_class() != "MMCharacter":
			p = p.get_parent()
		if p:
			_character = p
		else:
			_character = null
	
	# 尋找 CameraPivot
	var scene_root = get_tree().current_scene
	if scene_root:
		_camera = scene_root.find_child("CameraPivot", false) as Node3D
	
	print("[CTRL] character = ", _character, " (", _character.get_class() if _character else "null", ")")
	print("[CTRL] camera = ", _camera)
	
	# === 列出骨架名稱 ===
	if _character:
		var skeleton = _character.get("skeleton")
		if skeleton:
			print("[SKEL] Skeleton found: ", skeleton)
			print("[SKEL] Bone count: ", skeleton.get_bone_count())
			var leg_bones := []
			for i in skeleton.get_bone_count():
				var name = skeleton.get_bone_name(i)
				# 找腿部骨骼
				if "leg" in name.to_lower() or "foot" in name.to_lower() or "up" in name.to_lower():
					leg_bones.append(name)
			print("[SKEL] Leg/foot bones: ", leg_bones)
			# 列出所有骨骼名（前30個）
			var all_names := []
			for i in range(min(skeleton.get_bone_count(), 30)):
				all_names.append(skeleton.get_bone_name(i))
			print("[SKEL] First 30 bones: ", all_names)
		else:
			print("[SKEL] !! skeleton property is null !!")
	
	# === 診斷 AnimationTree 和 AnimationPlayer ===
	if _character:
		var anim_tree = _character.find_child("AnimationTree", false)
		var anim_player = _character.find_child("AnimationPlayer", false)
		
		print("[DIAG] --- AnimationTree ---")
		if anim_tree:
			print("[DIAG] active = ", anim_tree.active)
			print("[DIAG] tree_root = ", anim_tree.tree_root)
			print("[DIAG] tree_root class = ", anim_tree.tree_root.get_class() if anim_tree.tree_root else "null")
			print("[DIAG] anim_player = ", anim_tree.anim_player)
			print("[DIAG] root_node = ", anim_tree.root_node)
			# 檢查 BlendTree 內容
			if anim_tree.tree_root:
				var blend_tree = anim_tree.tree_root
				if blend_tree.has_node("MMAnimationNode"):
					var mm_node = blend_tree.get_node("MMAnimationNode")
					print("[DIAG] MMAnimationNode = ", mm_node)
					print("[DIAG] MMAnimationNode class = ", mm_node.get_class())
					var lib_name = mm_node.get("library")
					print("[DIAG] MMAnimationNode.library = '", lib_name, "'")
					if lib_name == null or str(lib_name) == "":
						print("[DIAG]   library is empty → 設定為 'MotionMatchTest'...")
						mm_node.set("library", &"MotionMatchTest")
						print("[DIAG]   ✓ 已設定 library = 'MotionMatchTest'")
					else:
						print("[DIAG]   ✓ library 已設定")
				else:
					print("[DIAG] !! MMAnimationNode not found in BlendTree !!")
		else:
			print("[DIAG] !! AnimationTree not found !!")
		
		print("[DIAG] --- AnimationPlayer ---")
		if anim_player:
			var libs = anim_player.get_animation_library_list()
			for lib_name in libs:
				var lib = anim_player.get_animation_library(lib_name)
				print("[DIAG] lib '", lib_name, "': ", lib.get_class(), " (", lib.get_animation_list().size(), " anims)")
				# === 診斷 MMAnimationLibrary 的 baked data ===
				if lib.get_class() == "MMAnimationLibrary":
					var mm_lib = lib
					var md = mm_lib.get("motion_data")
					var db_ai = mm_lib.get("db_anim_index")
					print("[FEAT] motion_data.size()=", md.size() if md else "null")
					print("[FEAT] db_anim_index.size()=", db_ai.size() if db_ai else "null")
					# List all animation names with their indices
					var anim_list = lib.get_animation_list()
					print("[FEAT] Animation names (", anim_list.size(), "):")
					for ai in range(anim_list.size()):
						print("[FEAT]   [", ai, "] = ", anim_list[ai])
					# Show which anim each pose belongs to
					if db_ai and anim_list.size() > 0:
						var db_ti = mm_lib.get("db_time_index")
						print("[FEAT] First 10 poses mapped:")
						for pi in range(min(10, db_ai.size())):
							var anim_idx = db_ai[pi]
							var anim_name = anim_list[anim_idx] if anim_idx < anim_list.size() else "?"
							var time = db_ti[pi] if db_ti else 0.0
							# Show first 6 dims of this pose
							var dims_str = ""
							if md:
								var dim_count = md.size() / db_ai.size()
								for d in range(min(6, dim_count)):
									dims_str += str(snapped(md[pi * dim_count + d], 0.001)) + " "
							print("[FEAT]   pose[", pi, "] anim=", anim_name, " t=", time, " data=", dims_str)
					var feats = mm_lib.get("features")
					if feats:
						print("[FEAT] features.size()=", feats.size())
						for fi in range(feats.size()):
							var f = feats[fi]
							var cls = f.get_class() if f else "null"
							var w = f.get("weight") if f else 0.0
							var m = f.get("means")
							var sd = f.get("std_devs")
							var mx = f.get("maxes")
							var mn = f.get("mins")
							print("[FEAT] feature[", fi, "] class=", cls, " weight=", w)
							if m and m.size() > 0:
								var m_str = ""
								for k in range(min(m.size(), 6)):
									m_str += str(snapped(m[k], 0.0001)) + " "
								print("[FEAT]   means(", m.size(), ")= ", m_str, "...")
							else:
								print("[FEAT]   means= EMPTY or null")
							if sd and sd.size() > 0:
								var sd_str = ""
								for k in range(min(sd.size(), 6)):
									sd_str += str(snapped(sd[k], 0.0001)) + " "
								print("[FEAT]   std_devs(", sd.size(), ")= ", sd_str, "...")
							else:
								print("[FEAT]   std_devs= EMPTY or null")
							if mn and mx and mn.size() > 0:
								var range_str = ""
								for k in range(min(mn.size(), 6)):
									range_str += "[" + str(snapped(mn[k], 0.001)) + "," + str(snapped(mx[k], 0.001)) + "] "
								print("[FEAT]   ranges(", mn.size(), ")= ", range_str, "...")
							# 檢查是否有非零方差
							if sd and sd.size() > 0:
								var non_zero = 0
								for k in range(sd.size()):
									if abs(sd[k]) > 0.0001:
										non_zero += 1
								print("[FEAT]   non-zero std_dev dims: ", non_zero, "/", sd.size())
					else:
						print("[FEAT] features= null or empty")
		else:
			print("[DIAG] !! AnimationPlayer not found !!")
		
		print("[DIAG] --- MMCharacter ---")
		print("[DIAG] trajectory_point_count = ", _character.get("trajectory_point_count"))
		print("[DIAG] trajectory_delta_time = ", _character.get("trajectory_delta_time"))
		print("[DIAG] history_point_count = ", _character.get("history_point_count"))
		print("[DIAG] history_delta_time = ", _character.get("history_delta_time"))
		print("[DIAG] halflife = ", _character.get("halflife"))
	
	# === 監控 motion matching 查詢結果 ===
	if _character:
		_character.set("emit_result_signal", true)
		if _character.has_signal("on_query_result"):
			_character.connect("on_query_result", _on_query_result)
			print("[DIAG] ✓ 已連接 on_query_result 信號")
		else:
			print("[DIAG] !! on_query_result 信號不存在 !!")
	
	# === 生成參考柱子讓移動可見 ===
	call_deferred("_spawn_reference_poles")

func _spawn_reference_poles() -> void:
	var sr = get_tree().current_scene
	if !sr:
		return
	for i in range(-5, 6):
		for j in range(-5, 6):
			if (i + j) % 2 == 0:
				continue
			var pole = MeshInstance3D.new()
			var mesh = CylinderMesh.new()
			mesh.top_radius = 0.05
			mesh.bottom_radius = 0.05
			mesh.height = 2.0
			pole.mesh = mesh
			pole.position = Vector3(i * 3.0, 1.0, j * 3.0)
			sr.add_child(pole)

var _debug_timer: float = 0.0
var _w_print_count: int = 0
var _query_count: int = 0

func _on_query_result(data: Dictionary) -> void:
	_query_count += 1
	if _query_count <= 10 or _query_count % 20 == 0:
		var anim_name = data.get("animation", "?")
		var time_val = snapped(data.get("time", 0.0), 0.01)
		var cost_val = snapped(data.get("total_cost", 0.0), 0.000001)
		var frame_data = data.get("frame_data", PackedFloat32Array())
		var feature_costs_str = ""
		for key in data.keys():
			if key not in ["animation", "time", "total_cost", "frame_data"]:
				feature_costs_str += " " + str(key) + "=" + str(data[key])
		print("[QUERY #", _query_count, "] anim=", anim_name, " time=", time_val, " cost=", cost_val, " dims=", frame_data.size(), feature_costs_str)
		# For first query, dump matched frame data and trajectory info
		if _query_count == 1:
			if frame_data.size() > 0:
				var fd_str = ""
				for k in range(min(frame_data.size(), 33)):
					fd_str += str(snapped(frame_data[k], 0.001)) + " "
				print("[QUERY] matched_frame_data(", frame_data.size(), ")= ", fd_str)
			# Dump character trajectory data
			if _character:
				var traj = _character.get_trajectory()
				var hist = _character.get_trajectory_history()
				print("[QUERY] trajectory (", traj.size() if traj else 0, " points):")
				if traj:
					for i in range(traj.size()):
						var pt = traj[i]
						print("[QUERY]   traj[", i, "] pos=", pt.get("position"), " facing=", pt.get("facing_angle"))
				print("[QUERY] history (", hist.size() if hist else 0, " points):")
				if hist:
					for i in range(hist.size()):
						var pt = hist[i]
						print("[QUERY]   hist[", i, "] pos=", pt.get("position"), " facing=", pt.get("facing_angle"))

func _physics_process(_delta: float) -> void:
	if !_camera or !_character:
		return
	
	# 測試鍵盤檢測 (每次 W 按下只打印一次)
	var w_logical = Input.is_key_pressed(KEY_W)
	var w_physical = Input.is_physical_key_pressed(KEY_W)
	if (w_logical or w_physical) and _w_print_count < 3:
		print("[INPUT] W detected: logical=", w_logical, " physical=", w_physical)
		_w_print_count += 1
	if not w_logical and not w_physical:
		_w_print_count = 0
	
	# 讀取 WASD 輸入
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_W): input_dir.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_S): input_dir.y -= 1
	if Input.is_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()
	
	# 決定速度
	var speed := walk_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed = sprint_speed
	elif input_dir.length() > 0.5:
		speed = run_speed
	
	# 轉換到世界座標（基於攝影機方向）
	var stick_world := Vector3(-input_dir.x, 0, input_dir.y)
	var desired_velocity := (stick_world * speed).rotated(Vector3.UP, _camera.rotation.y)
	_character.set("target_velocity", desired_velocity)
	
	# === 每2秒列印一次運行時狀態 ===
	_debug_timer += _delta
	if _debug_timer > 2.0:
		_debug_timer = 0.0
		var actual_vel = _character.velocity
		var target_vel = _character.get("target_velocity")
		print("[TICK] input=", input_dir, " target_vel=", target_vel, " actual_vel=", actual_vel)
		print("[TICK] char_pos=", _character.global_position, " on_floor=", _character.is_on_floor())

func _input(event: InputEvent) -> void:
	if !_character:
		return
	
	# 偵測任何鍵盤事件用於調試
	if event is InputEventKey and event.pressed:
		print("[KEY] keycode=", event.keycode, " physical=", event.physical_keycode, " label=", OS.get_keycode_string(event.keycode))
	
	# 跳躍
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if _character.call("is_on_floor"):
			_character.velocity += Vector3.UP * jump_speed
	
	# 切換 Strafe 模式
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_character.set("is_strafing", !_character.get("is_strafing"))
	
	# ESC 釋放滑鼠
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
