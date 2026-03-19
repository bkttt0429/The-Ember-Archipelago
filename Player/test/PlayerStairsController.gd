class_name PlayerStairsController extends RefCounted
## 玩家階梯/樓梯系統控制器
## 抽離自 SimpleCapsuleMove.gd

# ═══════════ 動畫路徑/名稱常數 ═══════════
const STAIR_WALK_ASCEND_FBX := "res://Player/assets/characters/player/motion/mx/stairs/Walking Up The Stairs.fbx"
const STAIR_DESCEND_FBX := "res://Player/assets/characters/player/motion/mx/stairs/Descending Stairs (1).fbx"
const STAIR_RUN_ASCEND_FBX := "res://Player/assets/characters/player/motion/mx/stairs/Running Up Stairs.fbx"

const STAIR_ANIM_LIB := "stairs"
const STAIR_ASCEND_ANIM := "Walking_Up_Stairs"
const STAIR_DESCEND_ANIM := "Descending_Stairs"
const STAIR_RUN_ASCEND_ANIM := "Running_Up_Stairs"

# ★ 速度門檻與動畫參數
const STAIR_RUN_SPEED_THRESHOLD := 4.5
const STAIR_RM_WALK_H_SPEED := 0.409
const STAIR_RM_RUN_H_SPEED := 0.843
const STAIR_RM_DESCEND_H_SPEED := 0.479
const STAIR_MIN_IK_PHASE := 0.3
const STAIR_DETECT_MIN_HEIGHT := 0.08
const STAIR_ANIM_MIN_HEIGHT := 0.12
const STAIR_DETECT_MIN_HITS := 2
const STAIR_CANDIDATE_MIN_TIME := 0.15
const STAIR_ANIM_MIN_SPEED := 1.2
const STAIR_EXIT_HOLD_TIME := 0.2
const STAIR_FIRST_STEP_PRE_RAISE := 0.28
const STAIR_MAX_IMMEDIATE_RAISE := 0.07
const STAIR_PENDING_STEP_SPEED := 2.2
const STAIR_PENDING_STEP_TIMEOUT := 0.08
const STAIR_PENDING_STEP_MAX := 0.45
const STAIR_SUPPORT_LOCK_MIN_HEIGHT_DIFF := 0.08
const STAIR_SUPPORT_LOCK_MIN_PHASE := 0.6
const STAIR_SUPPORT_RELEASE_HEIGHT_EPSILON := 0.05
const STAIR_SUPPORT_LOCK_TIMEOUT := 0.45

var player: CharacterBody3D
var data = PlayerStairData.new()

var _stair_anims_loaded: bool = false
var _stair_run_anim_loaded: bool = false
var _stair_anim_prefix: String = "stair_animations"

class PlayerStairData:
	var on_stairs: bool = false
	var ascending: bool = true
	var grace_timer: float = 0.0
	var blend_weight: float = 0.0
	var anim_exit_timer: float = 0.0
	var params_valid: bool = false
	var step_height_measured: float = 0.25
	var step_depth: float = 0.3
	var base_pos: Vector3 = Vector3.ZERO
	var dir_xz: Vector2 = Vector2.ZERO
	var root_motion_active: bool = false
	var rm_velocity: Vector3 = Vector3.ZERO
	var step_up_offset: float = 0.0
	var post_step_up_cooldown: int = 0
	var step_up_visual_debt: float = 0.0
	var was_ascending: bool = false
	var dir_committed: bool = false
	var committed_ascending: bool = true
	var dir_commit_timer: float = 0.0
	var collision_disabled: bool = false
	var saved_collision_layer: int = 1
	var candidate_timer: float = 0.0
	var candidate_hits: int = 0
	var anim_ready: bool = false
	var last_confirmed_step_height: float = 0.0
	var pending_step_height: float = 0.0
	var pending_step_timer: float = 0.0
	var pending_step_active: bool = false
	var support_lock_active: bool = false
	var support_lock_is_left: bool = false
	var support_lock_world_pos: Vector3 = Vector3.ZERO
	var support_lock_timer: float = 0.0


func _init(p_player: CharacterBody3D) -> void:
	player = p_player
	load_stair_animations()

func load_stair_animations() -> void:
	if not player.anim_player:
		return
	
	if player.verbose_debug: print(">>> [Stairs-RM] 載入 Root Motion 樓梯動畫...")
	var stair_lib = AnimationLibrary.new()
	var loaded_count = 0
	
	var ascend_anim: Animation = _extract_fbx_animation(STAIR_WALK_ASCEND_FBX)
	if ascend_anim:
		ascend_anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion_from_stair_animation(ascend_anim)
		stair_lib.add_animation(STAIR_ASCEND_ANIM, ascend_anim)
		loaded_count += 1
		if player.verbose_debug: print(">>> [Stairs] ✅ 走路上樓: %s" % STAIR_ASCEND_ANIM)
	
	var descend_anim = _extract_fbx_animation(STAIR_DESCEND_FBX)
	if descend_anim:
		descend_anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion_from_stair_animation(descend_anim)
		stair_lib.add_animation(STAIR_DESCEND_ANIM, descend_anim)
		loaded_count += 1
		if player.verbose_debug: print(">>> [Stairs] ✅ 走路下樓: %s" % STAIR_DESCEND_ANIM)
	
	var run_ascend_anim = _extract_fbx_animation(STAIR_RUN_ASCEND_FBX)
	if run_ascend_anim:
		run_ascend_anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion_from_stair_animation(run_ascend_anim)
		stair_lib.add_animation(STAIR_RUN_ASCEND_ANIM, run_ascend_anim)
		_stair_run_anim_loaded = true
		loaded_count += 1
		if player.verbose_debug: print(">>> [Stairs] ✅ 跑步上樓: %s" % STAIR_RUN_ASCEND_ANIM)
	
	if loaded_count == 0:
		if player.verbose_debug: print(">>> [Stairs-RM] ❌ 沒有載入任何樓梯動畫")
		return
	
	if player.anim_player.has_animation_library(STAIR_ANIM_LIB):
		player.anim_player.remove_animation_library(STAIR_ANIM_LIB)
	
	player.anim_player.add_animation_library(STAIR_ANIM_LIB, stair_lib)
	_stair_anim_prefix = STAIR_ANIM_LIB
	_stair_anims_loaded = true
	if player.verbose_debug: print(">>> [Stairs-RM] ✅ 樓梯動畫庫已載入 (%d 個動畫，run=%s)" % [loaded_count, _stair_run_anim_loaded])

func _extract_fbx_animation(fbx_path: String) -> Animation:
	var fbx_scene = load(fbx_path) as PackedScene
	if not fbx_scene:
		if player.verbose_debug: print(">>> [Stairs] ❌ 無法載入 FBX: %s" % fbx_path)
		return null
	
	var fbx_instance = fbx_scene.instantiate()
	
	var fbx_anim_player: AnimationPlayer = null
	for child in fbx_instance.get_children():
		if child is AnimationPlayer:
			fbx_anim_player = child
			break
		for grandchild in child.get_children():
			if grandchild is AnimationPlayer:
				fbx_anim_player = grandchild
				break
		if fbx_anim_player:
			break
	
	if not fbx_anim_player:
		if player.verbose_debug: print(">>> [Stairs] ❌ FBX 中找不到 AnimationPlayer: %s" % fbx_path)
		fbx_instance.queue_free()
		return null
	
	var found_anim: Animation = null
	for lib_name in fbx_anim_player.get_animation_library_list():
		var lib = fbx_anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			found_anim = lib.get_animation(anim_name)
			if found_anim:
				break
		if found_anim:
			break
	
	if not found_anim:
		fbx_instance.queue_free()
		return null
	
	var our_skeleton_path = "%GeneralSkeleton"
	for i in range(found_anim.get_track_count()):
		var orig_path = found_anim.track_get_path(i)
		var path_str = str(orig_path)
		var colon_pos = path_str.find(":")
		if colon_pos >= 0:
			var bone_part = path_str.substr(colon_pos + 1)
			var new_path = NodePath(our_skeleton_path +":"+ bone_part)
			found_anim.track_set_path(i, new_path)
	
	fbx_instance.queue_free()
	return found_anim

func _strip_root_motion_from_stair_animation(anim: Animation) -> void:
	for i in range(anim.get_track_count()):
		var path = str(anim.track_get_path(i))
		if path.ends_with(":Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			if key_count < 2:
				break
			
			var first_val: Vector3 = anim.track_get_key_value(i, 0)
			var last_val: Vector3 = anim.track_get_key_value(i, key_count - 1)
			
			var first_y: float = first_val.y
			var last_y: float = last_val.y
			var total_y_drift: float = last_y - first_y
			var duration: float = anim.length
			
			for k in range(key_count):
				var key_time: float = anim.track_get_key_time(i, k)
				var val: Vector3 = anim.track_get_key_value(i, k)
				
				if abs(total_y_drift) >= 0.01 and duration >= 0.01:
					var trend_y: float = total_y_drift * (key_time / duration)
					val.y = val.y - trend_y
				
				val.x = first_val.x
				val.z = first_val.z
				
				anim.track_set_key_value(i, k, val)
			
			if player.verbose_debug: print(">>> [Stairs] ★ 已將 RootMotion 轉為 In-Place, 並去趨勢 Hips Y（%d keys）" % key_count)
			break

func detect_stairs() -> void:
	var delta = player.get_physics_process_delta_time()
	if data.grace_timer > 0:
		data.grace_timer -= delta
	if data.anim_exit_timer > 0.0:
		data.anim_exit_timer = maxf(data.anim_exit_timer - delta, 0.0)
	# ★ 同步 on_stairs/ascending 到 player.stair（SimpleFootIK 從那裡讀取）
	player.stair.on_stairs = data.on_stairs
	player.stair.ascending = data.ascending
	
	if data.step_up_offset > 0.0 or data.post_step_up_cooldown > 0:
		data.on_stairs = true
		data.ascending = true
		data.grace_timer = 0.3
		data.candidate_timer = STAIR_CANDIDATE_MIN_TIME
		data.anim_ready = data.step_up_offset >= STAIR_ANIM_MIN_HEIGHT or data.last_confirmed_step_height >= STAIR_ANIM_MIN_HEIGHT
		# ★ step_up 觸發上樓 → 也要關碰撞
		if not data.collision_disabled:
			data.saved_collision_layer = player.collision_layer
			data.collision_disabled = true
			player.collision_layer = 0
		return
	
	if not player.is_on_floor() and not player.ground.was_on_floor or player._is_jumping or player._is_landing:
		if data.grace_timer > 0:
			return
		data.on_stairs = false
		data.params_valid = false
		data.step_height_measured = 0.0
		data.candidate_timer = 0.0
		data.candidate_hits = 0
		data.anim_ready = false
		data.pending_step_height = 0.0
		data.pending_step_timer = 0.0
		data.pending_step_active = false
		if data.collision_disabled:
			player.collision_layer = data.saved_collision_layer
			data.collision_disabled = false
		return
	
	if data.step_up_offset > 0.0 or data.post_step_up_cooldown > 0:
		data.on_stairs = true
		data.ascending = true
		data.grace_timer = 0.3
		data.candidate_timer = STAIR_CANDIDATE_MIN_TIME
		data.anim_ready = data.step_up_offset >= STAIR_ANIM_MIN_HEIGHT or data.last_confirmed_step_height >= STAIR_ANIM_MIN_HEIGHT
		if not data.collision_disabled:
			data.saved_collision_layer = player.collision_layer
			data.collision_disabled = true
			player.collision_layer = 0
		return
	
	var move_dir := Vector3.ZERO
	if player._main_camera:
		var raw = Input.get_vector("left", "right", "forward", "backward")
		if raw.length() > 0.1:
			var cam_basis = player._main_camera.global_transform.basis
			var cam_fwd = (-cam_basis.z)
			cam_fwd.y = 0
			cam_fwd = cam_fwd.normalized()
			var cam_right = cam_basis.x
			cam_right.y = 0
			cam_right = cam_right.normalized()
			move_dir = (cam_fwd * (-raw.y) + cam_right * raw.x).normalized()
	
	if move_dir.length() < 0.1:
		data.on_stairs = false
		data.params_valid = false
		data.step_height_measured = 0.0
		data.candidate_timer = 0.0
		data.candidate_hits = 0
		data.anim_ready = false
		data.pending_step_height = 0.0
		data.pending_step_timer = 0.0
		data.pending_step_active = false
		return
	
	var space = player.get_world_3d().direct_space_state
	var hits: Array[Dictionary] = []
	var has_flat_tread := false
	
	for dist in [0.3, 0.6]:
		var check_pos = player.global_position + move_dir * dist + Vector3.UP * 0.6
		var query = PhysicsRayQueryParameters3D.create(check_pos, check_pos + Vector3.DOWN * 1.2)
		query.exclude = [player.get_rid()]
		query.collision_mask = 2
		var hit = space.intersect_ray(query)
		
		if hit:
			var height_diff = hit.position.y - player.global_position.y
			if abs(height_diff) >= STAIR_DETECT_MIN_HEIGHT and abs(height_diff) < player.movement_data.max_step_height:
				var normal_dot = hit.normal.dot(Vector3.UP)
				if normal_dot > 0.9:
					has_flat_tread = true
					hits.append(hit)
	
	var has_riser := false
	if has_flat_tread:
		for check_h in [0.08, 0.15, 0.25]:
			var ray_start = player.global_position + Vector3.UP * check_h
			var ray_end = ray_start + move_dir * 0.5
			var riser_query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
			riser_query.exclude = [player.get_rid()]
			riser_query.collision_mask = 2
			var riser_hit = space.intersect_ray(riser_query)
			
			if riser_hit:
				var riser_normal_y = abs(riser_hit.normal.y)
				if riser_normal_y < 0.3:
					has_riser = true
					break
	
	if hits.size() >= STAIR_DETECT_MIN_HITS and has_flat_tread and has_riser:
		data.on_stairs = true
		var first_h_diff = hits[0].position.y - player.global_position.y
		data.ascending = first_h_diff > 0.05 or data.step_up_offset > 0.0
		data.grace_timer = 0.3
		data.candidate_hits = hits.size()
		data.candidate_timer = minf(data.candidate_timer + delta, STAIR_CANDIDATE_MIN_TIME + STAIR_EXIT_HOLD_TIME)
		# ★ 上樓梯時關掉碰撞體，避免膠囊被台階卡住
		if data.ascending and not data.collision_disabled:
			data.saved_collision_layer = player.collision_layer
			data.collision_disabled = true
			player.collision_layer = 0
			if player.verbose_debug: print(">>> [StairCol] 碰撞體 OFF (上樓梯)")
		
		if data.step_height_measured < 0.01 and first_h_diff > 0.03:
			data.step_height_measured = abs(first_h_diff)
		else:
			data.step_height_measured = lerpf(data.step_height_measured, abs(first_h_diff), 0.25)
		data.last_confirmed_step_height = abs(first_h_diff)
		
		if hits.size() >= 2:
			var h1: Vector3 = hits[0].position
			var h2: Vector3 = hits[1].position
			var dy = abs(h2.y - h1.y)
			var dxz = Vector2(h2.x - h1.x, h2.z - h1.z).length()
			if dy > 0.03 and dxz > 0.05:
				data.step_depth = lerpf(data.step_depth, dxz, 0.3)
		elif data.step_depth < 0.01:
			data.step_depth = 0.30
		
		var new_dir = Vector2(move_dir.x, move_dir.z).normalized()
		if not data.ascending:
			new_dir = - new_dir
		
		if not data.params_valid:
			data.dir_xz = new_dir
		else:
			var dot = data.dir_xz.dot(new_dir)
			if dot < 0.866:
				data.dir_xz = data.dir_xz.lerp(new_dir, 0.1).normalized()
		
		data.base_pos = hits[0].position
		
		if data.step_height_measured > 0.02:
			data.params_valid = true
		
		var has_committed_step = data.step_height_measured >= STAIR_ANIM_MIN_HEIGHT or data.step_up_offset >= STAIR_ANIM_MIN_HEIGHT
		data.anim_ready = data.params_valid and has_committed_step and data.candidate_timer >= STAIR_CANDIDATE_MIN_TIME
		
		if Engine.get_frames_drawn() % 60 == 0 and data.params_valid:
			if player.verbose_debug: print(">>> [StairProj] step_h=%.3f step_d=%.3f dir=(%.2f,%.2f) base_y=%.3f valid=%s" % [
				data.step_height_measured, data.step_depth,
				data.dir_xz.x, data.dir_xz.y, data.base_pos.y, data.params_valid
			])
			if player.verbose_debug: print(">>> [StairGate] hits=%d cand=%.2f anim_ready=%s step=%.3f" % [
				data.candidate_hits, data.candidate_timer, data.anim_ready, data.step_height_measured
			])
		return
	
	if data.grace_timer > 0:
		data.candidate_timer = maxf(data.candidate_timer - delta * 0.5, 0.0)
		data.anim_ready = data.anim_ready and data.candidate_timer > 0.01
		return
	data.on_stairs = false
	data.params_valid = false
	data.step_height_measured = 0.0
	data.candidate_timer = 0.0
	data.candidate_hits = 0
	data.anim_ready = false
	data.pending_step_height = 0.0
	data.pending_step_timer = 0.0
	data.pending_step_active = false
	# ★ 離開樓梯 → 恢復碰撞體
	if data.collision_disabled:
		player.collision_layer = data.saved_collision_layer
		data.collision_disabled = false
		if player.verbose_debug: print(">>> [StairCol] 碰撞體 ON (離開樓梯)")

func _check_step_up() -> float:
	var max_step = player.movement_data.max_step_height
	var h_motion := Vector3.ZERO
	if player._main_camera:
		var raw = Input.get_vector("left", "right", "forward", "backward")
		if raw.length() > 0.1:
			var cam_basis = player._main_camera.global_transform.basis
			var cam_forward = - cam_basis.z
			cam_forward.y = 0
			cam_forward = cam_forward.normalized()
			var cam_right = cam_basis.x
			cam_right.y = 0
			cam_right = cam_right.normalized()
			h_motion = (cam_forward * (-raw.y) + cam_right * raw.x).normalized() * 0.35
	
	if h_motion.length() < 0.001:
		var h_vel = Vector3(player.velocity.x, 0, player.velocity.z)
		if h_vel.length() < 0.1:
			if data.on_stairs and Engine.get_frames_drawn() % 10 == 0:
				if player.verbose_debug: print(">>> [CheckStep] FAIL: no h_motion & h_vel < 0.1 (vel=%.3f)" % h_vel.length())
			return 0.0
		h_motion = h_vel.normalized() * 0.35
	
	if not (data.on_stairs and data.ascending):
		var short_probe = h_motion.normalized() * 0.15
		var from_xform_probe = player.global_transform
		if not player.test_move(from_xform_probe, short_probe):
			return 0.0
	
	var from_xform = player.global_transform
	var raise_motion = Vector3(0, max_step, 0)
	var raise_col = KinematicCollision3D.new()
	var raise_blocked = player.test_move(from_xform, raise_motion, raise_col)
	var actual_raise = max_step
	if raise_blocked:
		actual_raise = raise_col.get_travel().y
	if actual_raise < 0.02:
		return 0.0
	
	var raised_xform = from_xform
	raised_xform.origin.y += actual_raise
	if player.test_move(raised_xform, h_motion):
		if data.on_stairs and Engine.get_frames_drawn() % 10 == 0:
			if player.verbose_debug: print(">>> [CheckStep] FAIL: blocked after raise (raise=%.3f)" % actual_raise)
		return 0.0
	
	var forward_xform = raised_xform
	forward_xform.origin += h_motion
	var drop_motion = Vector3(0, - (actual_raise + 0.05), 0)
	var drop_col = KinematicCollision3D.new()
	if not player.test_move(forward_xform, drop_motion, drop_col):
		if data.on_stairs and Engine.get_frames_drawn() % 10 == 0:
			if player.verbose_debug: print(">>> [CheckStep] FAIL: no ground after forward+drop")
		return 0.0
	
	var drop_travel = drop_col.get_travel().y
	var final_y = forward_xform.origin.y + drop_travel
	var step_height = final_y - player.global_position.y
	
	if step_height > 0.01 and step_height <= max_step:
		var normal = drop_col.get_normal()
		if normal.angle_to(Vector3.UP) <= player.floor_max_angle:
			return step_height
		var nudge_xform = forward_xform
		nudge_xform.origin += h_motion.normalized() * 0.05
		var nudge_col = KinematicCollision3D.new()
		if player.test_move(nudge_xform, drop_motion, nudge_col):
			var nudge_normal = nudge_col.get_normal()
			if nudge_normal.angle_to(Vector3.UP) <= player.floor_max_angle:
				var nudge_y = nudge_xform.origin.y + nudge_col.get_travel().y
				var nudge_step = nudge_y - player.global_position.y
				if nudge_step > 0.01 and nudge_step <= max_step:
					return nudge_step
		return step_height
	return 0.0

func _snap_after_step_up() -> void:
	var space_state = player.get_world_3d().direct_space_state
	var ray_start = player.global_position + Vector3.UP * 0.1
	var ray_end = player.global_position + Vector3.DOWN * (player.movement_data.max_step_height + 0.2)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [player.get_rid()]
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	
	if result:
		player.global_position.y = result.position.y

func snap_up_stairs_check(_delta: float) -> void:
	# 使用樓梯 ramp 給膠囊體平滑上樓；可見台階只給腳部吸附。
	# 一旦進入正式樓梯上行模式，就不要再做離散 snap_up，避免 body 拖腳。
	if data.on_stairs and data.ascending:
		data.pending_step_height = 0.0
		data.pending_step_active = false
		data.pending_step_timer = 0.0
		return

	var h_vel = Vector3(player.velocity.x, 0, player.velocity.z)
	if h_vel.length() < 0.1:
		return
	
	var fwd_dir = h_vel.normalized()
	var max_step = player.movement_data.max_step_height
	var cur_pos = player.global_position
	
	var capsule_r = 0.35
	var col_shape = player.get_node_or_null("CollisionShape3D")
	if col_shape and col_shape.shape:
		if col_shape.shape is CapsuleShape3D or col_shape.shape is CylinderShape3D:
			capsule_r = col_shape.shape.radius
	
	var gate_params = PhysicsTestMotionParameters3D.new()
	gate_params.from = Transform3D(player.global_basis, cur_pos)
	gate_params.motion = fwd_dir * (h_vel.length() * _delta + 0.01)
	var gate_result = PhysicsTestMotionResult3D.new()
	var would_be_blocked = PhysicsServer3D.body_test_motion(player.get_rid(), gate_params, gate_result)
	if not would_be_blocked:
		return
	
	var raise_xform = Transform3D(player.global_basis, cur_pos)
	var raise_params = PhysicsTestMotionParameters3D.new()
	raise_params.from = raise_xform
	raise_params.motion = Vector3(0, max_step, 0)
	var raise_result = PhysicsTestMotionResult3D.new()
	
	var raise_blocked = PhysicsServer3D.body_test_motion(player.get_rid(), raise_params, raise_result)
	var actual_raise = max_step
	if raise_blocked:
		actual_raise = raise_result.get_travel().y
	if actual_raise < 0.02:
		return
	
	var raised_pos = cur_pos + Vector3(0, actual_raise, 0)
	var raised_xform = Transform3D(player.global_basis, raised_pos)
	
	var fwd_dist = capsule_r + 0.1
	var fwd_params = PhysicsTestMotionParameters3D.new()
	fwd_params.from = raised_xform
	fwd_params.motion = fwd_dir * fwd_dist
	var fwd_result = PhysicsTestMotionResult3D.new()
	
	var fwd_blocked = PhysicsServer3D.body_test_motion(player.get_rid(), fwd_params, fwd_result)
	var fwd_travel = fwd_result.get_travel() if fwd_blocked else fwd_dir * fwd_dist
	
	if fwd_travel.length() < 0.001:
		return
	
	var fwd_pos = raised_pos + fwd_travel
	var drop_params = PhysicsTestMotionParameters3D.new()
	drop_params.from = Transform3D(player.global_basis, fwd_pos)
	drop_params.motion = Vector3(0, - (actual_raise + 0.1), 0)
	var drop_result = PhysicsTestMotionResult3D.new()
	
	if not PhysicsServer3D.body_test_motion(player.get_rid(), drop_params, drop_result):
		return
	
	var landing_pos = fwd_pos + drop_result.get_travel()
	var step_height = landing_pos.y - cur_pos.y
	
	if step_height < 0.01 or step_height > max_step:
		return
	
	var normal = drop_result.get_collision_normal()
	if normal.angle_to(Vector3.UP) > player.floor_max_angle:
		var nudge_pos = fwd_pos + fwd_dir * 0.05
		var nudge_params = PhysicsTestMotionParameters3D.new()
		nudge_params.from = Transform3D(player.global_basis, nudge_pos)
		nudge_params.motion = Vector3(0, - (actual_raise + 0.1), 0)
		var nudge_result = PhysicsTestMotionResult3D.new()
		
		if PhysicsServer3D.body_test_motion(player.get_rid(), nudge_params, nudge_result):
			var nudge_normal = nudge_result.get_collision_normal()
			if nudge_normal.angle_to(Vector3.UP) <= player.floor_max_angle:
				landing_pos = nudge_pos + nudge_result.get_travel()
				step_height = landing_pos.y - cur_pos.y
				if step_height < 0.01 or step_height > max_step:
					return
			else:
				return
		else:
			return
	
	var applied_step_height = step_height
	if step_height >= STAIR_DETECT_MIN_HEIGHT:
		var is_first_step = not data.on_stairs and data.grace_timer <= 0.0 and not data.pending_step_active
		var immediate_raise = minf(step_height * STAIR_FIRST_STEP_PRE_RAISE, STAIR_MAX_IMMEDIATE_RAISE)
		if is_first_step:
			immediate_raise = maxf(immediate_raise, minf(step_height * 0.45, 0.07))
		elif data.pending_step_active:
			immediate_raise = minf(immediate_raise, 0.01)
		immediate_raise = minf(immediate_raise, step_height)
		applied_step_height = immediate_raise
		var pending_add = maxf(step_height - applied_step_height, 0.0)
		if pending_add > 0.001:
			data.pending_step_height = minf(data.pending_step_height + pending_add, STAIR_PENDING_STEP_MAX)
			data.pending_step_timer = 0.0
			data.pending_step_active = true
	else:
		data.pending_step_height = 0.0
		data.pending_step_timer = 0.0
		data.pending_step_active = false

	player.global_position.y += applied_step_height
	data.step_up_offset = applied_step_height
	player.ground.snapped_to_stairs_last_frame = true
	
	if data.on_stairs and data.ascending and step_height > 0.02:
		data.step_height_measured = lerpf(data.step_height_measured, step_height, 0.3)
		data.last_confirmed_step_height = step_height
		if step_height >= STAIR_ANIM_MIN_HEIGHT:
			data.candidate_timer = STAIR_CANDIDATE_MIN_TIME
			data.anim_ready = true
	
	if not (data.on_stairs and data.ascending):
		data.step_up_visual_debt -= step_height
	
	if player.verbose_debug: print(">>> [SnapUp] ✅ step=%.3f apply=%.3f pending=%.3f pos=(%.2f,%.3f,%.2f) raise=%.3f" % [step_height, applied_step_height, data.pending_step_height, player.global_position.x, player.global_position.y, player.global_position.z, actual_raise])


func apply_pending_step_up(delta: float) -> void:
	if not data.pending_step_active:
		return

	data.pending_step_timer += delta
	var h_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var has_input = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
	if not has_input and h_speed < 0.15 and not data.support_lock_active:
		data.pending_step_height = 0.0
		data.pending_step_active = false
		data.pending_step_timer = 0.0
		return
	if not data.support_lock_active and data.pending_step_height > STAIR_PENDING_STEP_MAX * 0.75:
		data.pending_step_height = maxf(data.pending_step_height - STAIR_PENDING_STEP_SPEED * delta * 0.1, 0.0)
		if data.pending_step_height <= 0.001:
			data.pending_step_height = 0.0
			data.pending_step_active = false
		return
	var allow_advance = data.support_lock_active
	if not allow_advance:
		return

	var step_rate = maxf(data.last_confirmed_step_height, STAIR_ANIM_MIN_HEIGHT) * STAIR_PENDING_STEP_SPEED
	var step_delta = minf(data.pending_step_height, step_rate * delta)
	if step_delta <= 0.0001:
		data.pending_step_height = 0.0
		data.pending_step_active = false
		return

	player.global_position.y += step_delta
	data.step_up_offset += step_delta
	data.pending_step_height -= step_delta
	player.ground.snapped_to_stairs_last_frame = true

	if data.pending_step_height <= 0.001:
		data.pending_step_height = 0.0
		data.pending_step_active = false

	if player.verbose_debug and Engine.get_physics_frames() % 10 == 0:
		print(">>> [StepAdvance] delta=%.3f remain=%.3f lock=%s" % [step_delta, data.pending_step_height, data.support_lock_active])


func update_stair_foot_adhesion(delta: float) -> void:
	if not data.on_stairs or not data.ascending:
		data.support_lock_active = false
		data.support_lock_timer = 0.0
		return
	if not player.right_foot_target or not player.left_foot_target:
		return

	var right_pos = player.right_foot_target.global_position
	var left_pos = player.left_foot_target.global_position
	var right_phase = player._right_foot_phase_weight
	var left_phase = player._left_foot_phase_weight

	if data.support_lock_active:
		data.support_lock_timer += delta
		if data.support_lock_is_left:
			player.left_foot_target.global_position = data.support_lock_world_pos
			if player.right_foot_target:
				player.right_foot_target.global_position.y = maxf(player.right_foot_target.global_position.y, data.support_lock_world_pos.y - STAIR_SUPPORT_RELEASE_HEIGHT_EPSILON)
			var right_ready = right_phase >= STAIR_SUPPORT_LOCK_MIN_PHASE and absf(right_pos.y - data.support_lock_world_pos.y) <= STAIR_SUPPORT_RELEASE_HEIGHT_EPSILON
			if right_ready or data.support_lock_timer >= STAIR_SUPPORT_LOCK_TIMEOUT:
				data.support_lock_active = false
				data.support_lock_timer = 0.0
		else:
			player.right_foot_target.global_position = data.support_lock_world_pos
			if player.left_foot_target:
				player.left_foot_target.global_position.y = maxf(player.left_foot_target.global_position.y, data.support_lock_world_pos.y - STAIR_SUPPORT_RELEASE_HEIGHT_EPSILON)
			var left_ready = left_phase >= STAIR_SUPPORT_LOCK_MIN_PHASE and absf(left_pos.y - data.support_lock_world_pos.y) <= STAIR_SUPPORT_RELEASE_HEIGHT_EPSILON
			if left_ready or data.support_lock_timer >= STAIR_SUPPORT_LOCK_TIMEOUT:
				data.support_lock_active = false
				data.support_lock_timer = 0.0
		return

	var height_diff = left_pos.y - right_pos.y
	if height_diff > STAIR_SUPPORT_LOCK_MIN_HEIGHT_DIFF and left_phase >= STAIR_SUPPORT_LOCK_MIN_PHASE:
		data.support_lock_active = true
		data.support_lock_is_left = true
		data.support_lock_world_pos = left_pos
		data.support_lock_timer = 0.0
	elif height_diff < -STAIR_SUPPORT_LOCK_MIN_HEIGHT_DIFF and right_phase >= STAIR_SUPPORT_LOCK_MIN_PHASE:
		data.support_lock_active = true
		data.support_lock_is_left = false
		data.support_lock_world_pos = right_pos
		data.support_lock_timer = 0.0

func snap_down_stairs_check() -> void:
	if data.step_up_offset > 0.0:
		return
	
	player.ground.snapped_to_stairs_last_frame = false
	
	if data.on_stairs and data.ascending:
		return
	
	if player.is_on_floor():
		return
	
	if player._is_jumping or player.velocity.y > 0.1:
		return
	
	if data.on_stairs or player.ground.step_down_snapped:
		pass
	else:
		if not player.ground.was_on_floor:
			return
	
	var max_down = player.movement_data.max_step_height
	var down_motion = Vector3(0, -max_down, 0)
	var col = KinematicCollision3D.new()
	
	if not player.test_move(player.global_transform, down_motion, col):
		player.ground.snapped_to_stairs_last_frame = false
		return
	
	var snap_travel = col.get_travel()
	var snap_y = snap_travel.y
	
	var normal = col.get_normal()
	var normal_angle = rad_to_deg(normal.angle_to(Vector3.UP))
	if normal_angle > 65.0:
		player.ground.snapped_to_stairs_last_frame = false
		return
	
	if abs(snap_y) < 0.01 or abs(snap_y) >= max_down:
		player.ground.snapped_to_stairs_last_frame = false
		return
	
	player.global_position.y += snap_y
	player.velocity.y = 0.0
	player.ground.snapped_to_stairs_last_frame = true
	player.ground.step_down_snapped = true
	player.air.air_time = 0.0
	
	if not (data.on_stairs and data.ascending):
		data.step_up_visual_debt += snap_y
	
	if Engine.get_frames_drawn() % 30 == 0:
		if player.verbose_debug: print(">>> [SnapDown] snap_y=%.3f pos_y=%.3f" % [snap_y, player.global_position.y])


func _disable_stair_animation_mode() -> void:
	if not data.root_motion_active and not data.collision_disabled:
		data.blend_weight = 0.0
		data.rm_velocity = Vector3.ZERO
		return

	data.root_motion_active = false
	data.blend_weight = 0.0
	data.rm_velocity = Vector3.ZERO
	data.dir_committed = false
	data.anim_exit_timer = STAIR_EXIT_HOLD_TIME
	data.anim_ready = false
	player.air.air_time = 0.0

	if player.anim_player:
		player.anim_player.stop()
		player.anim_player.speed_scale = 1.0
		var empty_track = NodePath("")
		if player.anim_player.root_motion_track != empty_track:
			player.anim_player.root_motion_track = empty_track

	if player.anim_tree:
		player._blend_position = Vector2.ZERO
		player.anim_tree.set("parameters/movement/stand_movement/blend_position", Vector2.ZERO)
		if not player.anim_tree.active:
			player.anim_tree.active = true
		var playback = player.anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel("movement")

	if player._foot_ik_system:
		player._foot_ik_system.temporary_disable_predict_ik = false

	if data.collision_disabled:
		player.collision_layer = data.saved_collision_layer
		data.collision_disabled = false
		if player.verbose_debug:
			print(">>> [StairAnim] 碰撞體 ON")

	if player.verbose_debug:
		print(">>> [StairAnim] 停止 → 恢復 AnimationTree")

func update_stair_animation(_delta: float) -> void:
	# ★ 方案 B: 樓梯不播專用動畫，用一般走路動畫 + IK 預測落腳點
	# AnimationTree 保持啟用，SimpleFootIK 的 stair_ik_active 控制腳步
	data.root_motion_active = false
	return
