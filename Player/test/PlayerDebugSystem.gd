class_name PlayerDebugSystem extends RefCounted
## 玩家除錯系統
## 負責繪製 IK 射線、樓梯形狀、印出 debug 資訊

var player: CharacterBody3D
var imm: ImmediateMesh
var mat: StandardMaterial3D
var mesh_instance: MeshInstance3D

func _init(p_player: CharacterBody3D) -> void:
	player = p_player
	
	imm = ImmediateMesh.new()
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = imm
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# 將 Mesh 延遲加入根節點 (確保不受 RootTransform 影響)
	player.get_tree().root.call_deferred("add_child", mesh_instance)

func draw_stair_debug() -> void:
	if not player._stair_debug_enabled:
		imm.clear_surfaces()
		return
		
	imm.clear_surfaces()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var stair = player.stair
	var base = stair.base_pos if stair.params_valid else player.global_position
	var dir3 = Vector3(stair.dir_xz.x, 0, stair.dir_xz.y) if stair.params_valid else Vector3.FORWARD
	var step_h = stair.step_height_measured if stair.step_height_measured > 0.01 else 0.2
	var step_d = stair.step_depth if stair.step_depth > 0.01 else 0.3
	var cross = dir3.cross(Vector3.UP).normalized() * 0.3
	
	# --- 1. 基準點十字標記（品紅色）---
	var mk_c = Color(1, 0, 1, 1)
	_debug_line(base + Vector3.LEFT * 0.15, base + Vector3.RIGHT * 0.15, mk_c)
	_debug_line(base + Vector3.FORWARD * 0.15, base + Vector3.BACK * 0.15, mk_c)
	_debug_line(base + Vector3.UP * 0.3, base + Vector3.DOWN * 0.05, mk_c)
	
	# --- 2. 階梯方向箭頭（青色）---
	var arrow_c = Color(0, 1, 1, 1)
	var arrow_end = base + dir3 * 1.5 + Vector3.UP * 0.05
	_debug_line(base + Vector3.UP * 0.05, arrow_end, arrow_c)
	var arrow_right = dir3.cross(Vector3.UP).normalized() * 0.15
	_debug_line(arrow_end, arrow_end - dir3 * 0.2 + arrow_right, arrow_c)
	_debug_line(arrow_end, arrow_end - dir3 * 0.2 - arrow_right, arrow_c)
	
	# --- 3. 台階網格（黃色）---
	var grid_c = Color(1, 1, 0, 0.6)
	var n_steps = 8
	for i in range(-2, n_steps):
		var step_base_xz = base + dir3 * (i * step_d)
		var step_y = base.y + i * step_h
		var p = Vector3(step_base_xz.x, step_y, step_base_xz.z)
		_debug_line(p - cross, p + cross, grid_c)
		var p_next = Vector3(step_base_xz.x + dir3.x * step_d, step_y, step_base_xz.z + dir3.z * step_d)
		_debug_line(p - cross, p_next - cross, Color(1, 1, 0, 0.3))
		_debug_line(p + cross, p_next + cross, Color(1, 1, 0, 0.3))
		var rise_end = Vector3(p_next.x, step_y + step_h, p_next.z)
		_debug_line(p_next - cross, rise_end - cross, Color(1, 0.5, 0, 0.5))
		_debug_line(p_next + cross, rise_end + cross, Color(1, 0.5, 0, 0.5))
	
	# --- 4. 右腳鎖定標記 ---
	if player._right_foot_locked:
		var rp = Vector3(player._smoothed_right_ray_xz.x, player._locked_right_world_pos.y, player._smoothed_right_ray_xz.y)
		var lk_c = Color(0, 1, 0, 1)
		_debug_line(rp + Vector3.LEFT * 0.1, rp + Vector3.RIGHT * 0.1, lk_c)
		_debug_line(rp + Vector3(0, 0, -0.1), rp + Vector3(0, 0, 0.1), lk_c)
		_debug_line(rp, rp + Vector3.UP * 0.2, lk_c)
		var ik_r = player._smoothed_right_target if player._smoothed_right_target != Vector3.ZERO else rp + Vector3.UP * 0.08
		_debug_line(ik_r + Vector3.LEFT * 0.05, ik_r + Vector3.RIGHT * 0.05, Color.WHITE)
		_debug_line(ik_r + Vector3(0, 0, -0.05), ik_r + Vector3(0, 0, 0.05), Color.WHITE)
	else:
		if player._smoothed_right_ray_xz != Vector2.ZERO:
			var rp = Vector3(player._smoothed_right_ray_xz.x, player.global_position.y, player._smoothed_right_ray_xz.y)
			var ul_c = Color(1, 0, 0, 0.5)
			_debug_line(rp + Vector3(-0.08, 0, -0.08), rp + Vector3(0.08, 0, 0.08), ul_c)
			_debug_line(rp + Vector3(0.08, 0, -0.08), rp + Vector3(-0.08, 0, 0.08), ul_c)
	
	# --- 5. 左腳鎖定標記 ---
	if player._left_foot_locked:
		var lp = Vector3(player._smoothed_left_ray_xz.x, player._locked_left_world_pos.y, player._smoothed_left_ray_xz.y)
		var lk_c = Color(0, 1, 0, 1)
		_debug_line(lp + Vector3.LEFT * 0.1, lp + Vector3.RIGHT * 0.1, lk_c)
		_debug_line(lp + Vector3(0, 0, -0.1), lp + Vector3(0, 0, 0.1), lk_c)
		_debug_line(lp, lp + Vector3.UP * 0.2, lk_c)
		var ik_l = player._smoothed_left_target if player._smoothed_left_target != Vector3.ZERO else lp + Vector3.UP * 0.08
		_debug_line(ik_l + Vector3.LEFT * 0.05, ik_l + Vector3.RIGHT * 0.05, Color.WHITE)
		_debug_line(ik_l + Vector3(0, 0, -0.05), ik_l + Vector3(0, 0, 0.05), Color.WHITE)
	else:
		if player._smoothed_left_ray_xz != Vector2.ZERO:
			var lp = Vector3(player._smoothed_left_ray_xz.x, player.global_position.y, player._smoothed_left_ray_xz.y)
			var ul_c = Color(1, 0, 0, 0.5)
			_debug_line(lp + Vector3(-0.08, 0, -0.08), lp + Vector3(0.08, 0, 0.08), ul_c)
			_debug_line(lp + Vector3(0.08, 0, -0.08), lp + Vector3(-0.08, 0, 0.08), ul_c)
	
	# --- 6. 狀態資訊面板（角色頭頂）---
	if stair.on_stairs:
		var head = player.global_position + Vector3.UP * 2.0
		var state_c = Color(0, 1, 1, 0.8) if stair.params_valid else Color(1, 0.5, 0, 0.8)
		_debug_line(head, head + Vector3.UP * 0.15, state_c)
		_debug_line(head + Vector3.UP * 0.15, head + Vector3(0.1, 0.1, 0), state_c)
		_debug_line(head + Vector3.UP * 0.15, head + Vector3(-0.1, 0.1, 0), state_c)
	
	# --- 7. ShapeCast IK 射線 ---
	var ray_c_r = Color(0.3, 1.0, 0.3, 0.8)
	var ray_c_l = Color(1.0, 0.3, 0.3, 0.8)
	var hit_c = Color(1, 1, 1, 1)
	
	if player._right_foot_ray:
		var r_origin = player._right_foot_ray.global_position
		var r_end = r_origin + Vector3.DOWN * 1.5
		_debug_line(r_origin, r_end, ray_c_r)
		_debug_line(r_origin + Vector3(-0.03, 0, -0.03), r_origin + Vector3(0.03, 0, 0.03), ray_c_r)
		_debug_line(r_origin + Vector3(0.03, 0, -0.03), r_origin + Vector3(-0.03, 0, 0.03), ray_c_r)
		if player._right_foot_ray.is_colliding():
			var rh = player._right_foot_ray.get_collision_point(0)
			_debug_line(rh + Vector3.LEFT * 0.06, rh + Vector3.RIGHT * 0.06, hit_c)
			_debug_line(rh + Vector3(0, 0, -0.06), rh + Vector3(0, 0, 0.06), hit_c)
			_debug_line(rh, rh + Vector3.UP * 0.08, hit_c)
	
	if player._left_foot_ray:
		var l_origin = player._left_foot_ray.global_position
		var l_end = l_origin + Vector3.DOWN * 1.5
		_debug_line(l_origin, l_end, ray_c_l)
		_debug_line(l_origin + Vector3(-0.03, 0, -0.03), l_origin + Vector3(0.03, 0, 0.03), ray_c_l)
		_debug_line(l_origin + Vector3(0.03, 0, -0.03), l_origin + Vector3(-0.03, 0, 0.03), ray_c_l)
		if player._left_foot_ray.is_colliding():
			var lh = player._left_foot_ray.get_collision_point(0)
			_debug_line(lh + Vector3.LEFT * 0.06, lh + Vector3.RIGHT * 0.06, hit_c)
			_debug_line(lh + Vector3(0, 0, -0.06), lh + Vector3(0, 0, 0.06), hit_c)
			_debug_line(lh, lh + Vector3.UP * 0.08, hit_c)
	
	# --- 8. IK Target 實際位置 ---
	var ik_tc = Color(1, 0.9, 0.3, 1.0)
	if player._smoothed_right_target != Vector3.ZERO:
		var rt = player._smoothed_right_target
		_debug_line(rt + Vector3.LEFT * 0.04, rt + Vector3.RIGHT * 0.04, ik_tc)
		_debug_line(rt + Vector3(0, 0, -0.04), rt + Vector3(0, 0, 0.04), ik_tc)
		_debug_line(rt, rt + Vector3.UP * 0.06, ik_tc)
	if player._smoothed_left_target != Vector3.ZERO:
		var lt = player._smoothed_left_target
		_debug_line(lt + Vector3.LEFT * 0.04, lt + Vector3.RIGHT * 0.04, ik_tc)
		_debug_line(lt + Vector3(0, 0, -0.04), lt + Vector3(0, 0, 0.04), ik_tc)
		_debug_line(lt, lt + Vector3.UP * 0.06, ik_tc)
	
	imm.surface_end()

func _debug_line(from: Vector3, to: Vector3, color: Color) -> void:
	imm.surface_set_color(color)
	imm.surface_add_vertex(from)
	imm.surface_set_color(color)
	imm.surface_add_vertex(to)

func print_frame_debug() -> void:
	# ★ 只在每 120 幀輸出一次（減少 console 噪音）
	if Engine.get_physics_frames() % 120 != 0:
		return
	var state = "?"
	if player._fsm.current_state:
		for key in player._fsm.states:
			if player._fsm.states[key] == player._fsm.current_state:
				state = key
				break
	var pos = "%4.2f/%4.2f" % [player.global_position.x, player.global_position.y]
	print("Frame %d: node=%s pos=%s grounded=%s jump=%s" % [
		Engine.get_physics_frames(), state, pos, player.is_on_floor(), player._is_jumping
	])

func debug_bone_after_ik() -> void:
	if not player._skeleton or player.disable_ik_code or not player.verbose_debug:
		return
	var right_foot_idx = player._skeleton.find_bone("RightFoot")
	if right_foot_idx >= 0:
		var right_foot_target = player.get("right_foot_target")
		var right_leg_ik = player.get("right_leg_ik")
		var bone_pose = player._skeleton.global_transform * player._skeleton.get_bone_global_pose(right_foot_idx)
		print(">>> [AFTER IK] RBone=%.2f | Target=%.2f | active=%s" % [
			bone_pose.origin.y,
			right_foot_target.global_position.y if right_foot_target else -999.0,
			right_leg_ik.get("active") if right_leg_ik else false
		])


## 解除安裝時清理 Mesh
func cleanup() -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
