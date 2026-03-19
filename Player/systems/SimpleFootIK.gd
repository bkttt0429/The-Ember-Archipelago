extends Node3D
class_name SimpleFootIK
## 簡單的 Foot IK - 動態 Influence 版本
## 移動時讓動畫播放，站立時 IK 固定腳位置

## ★ 外部控制開關 (SimpleCapsuleMove 在樓梯模式時設為 false)
var ik_enabled: bool = true

@export var skeleton: Skeleton3D
@export var left_target: Marker3D
@export var right_target: Marker3D

@export_group("IK Nodes")
@export var left_ik: SkeletonModifier3D # TwoBoneIK3D 或 CCDIK3D
@export var right_ik: SkeletonModifier3D

@export_group("ShapeCast Ground Detection")
## 左腳 ShapeCast3D（球形掃描，比射線更精確）
@export var left_foot_shape: ShapeCast3D
## 右腳 ShapeCast3D
@export var right_foot_shape: ShapeCast3D

@export_group("IK Settings")
@export var ray_length: float = 1.0
@export var max_step_up: float = 0.5
@export var max_step_down: float = 0.7
## 腳可以延伸的最大距離（從髖關節算起），超過此距離會淡出 IK
@export var max_reach_distance: float = 1.15
@export var smooth_speed: float = 15.0
@export var influence_speed: float = 8.0 # IK 混合速度
## 腳踝骨骼到腳底表面的距離（Mixamo 實際值 0.086）
@export var foot_height_offset: float = 0.086

@export_group("Triple Raycast")
## 腳跟位置偏移（相對於腳骨，向後，Z 負值）
@export var heel_offset: Vector3 = Vector3(0, 0.05, -0.08)
## 腳尖位置偏移（相對於腳骨，向前，Z 正值）
@export var toe_offset: Vector3 = Vector3(0, 0.05, 0.15)
## 腳球位置偏移（中間位置）
@export var ball_offset: Vector3 = Vector3(0, 0.05, 0.05)
## 腳的 Pitch 旋轉速度
@export var foot_rotation_speed: float = 10.0
## 最大 Pitch 角度（度數，防止過度旋轉）
@export var max_pitch_angle: float = 35.0

@export_group("Pelvis Offset")
## 啟用骨盆下沉（解決膠囊體懸空問題）
@export var enable_pelvis_offset: bool = true
## 骨盆下沉的最大距離
@export var max_pelvis_offset: float = 0.5
## 骨盆調整速度
@export var pelvis_smooth_speed: float = 10.0

@export_group("Profiling")
## ★ 臨時效能分析（開啟後每 120 幀 print 一次各段平均耗時）
@export var enable_profiling: bool = false

@export_group("Predictive IK")
## ★ 啟用預測式 IK（GASP-Style 模擬軌跡預測）
@export var enable_predictive_ik: bool = true
## 低於此速度不預測（站立時用當前位置）
@export var min_prediction_speed: float = 0.5
## 預測偏移最大距離（防急轉彎跳動，建議 = 跑步半步幅 ≈ 0.5m）
@export var max_prediction_offset: float = 0.5
## 預測步幅長度（控制前探距離，走路 0.5-0.7，跑步自動按速度縮放）
@export var prediction_stride_length: float = 0.6
## Spring-Damper 阻尼比（1.0 = 臨界阻尼，<1 會震盪，>1 會過阻尼）
@export var spring_damping_ratio: float = 1.0
## Spring-Damper 自然頻率（8=柔軟80ms, 10=平衡64ms, 12=硬朗53ms）
@export var spring_frequency: float = 10.0
## 預測步態額外抬腳高度（無障礙時也會保留自然 swing arc）
@export var predictive_step_clearance: float = 0.08
## 相位低於此值時，視為進入 swing 並觸發新的落腳預測
@export var swing_enter_phase_threshold: float = 0.35
## swing 中相位高於此值時，視為進入 plant/landing
@export var plant_enter_phase_threshold: float = 0.7
## swing 前段若轉向超過此角度，允許重算一次預測落腳點
@export var predictive_replan_turn_degrees: float = 40.0
## ★ Stride Warping：啟用步幅變形消除滑步
@export var enable_stride_warping: bool = true
## Stride Warping 縮放範圍 [min, max]（防止極端拉伸）
@export var stride_warp_min: float = 0.6
@export var stride_warp_max: float = 1.4

@export_group("Influence")
## 移動時的 IK 權重（0=純動畫，1=純IK）
## 建議值：0.0 移動時純動畫，站立時才啟用 IK
@export_range(0.0, 1.0) var moving_influence: float = 0.0
## 站立時的 IK 權重
@export_range(0.0, 1.0) var standing_influence: float = 1.0
## 速度閾值，低於此值視為站立
@export var standing_threshold: float = 0.1

@export_group("Debug")
## 啟用遊戲中的視覺化除錯
@export var debug_draw: bool = true
## 除錯線持續時間
@export var debug_line_duration: float = 0.1

@export_group("Foot Rotation (LookAt)")
## 啟用腳部旋轉 (使用 LookAtModifier3D)
@export var enable_foot_rotation: bool = true
## 左腳 LookAt 目標 (腳尖看向的點)
@export var left_lookat_target: Marker3D
## 右腳 LookAt 目標
@export var right_lookat_target: Marker3D
## 左腳 LookAtModifier3D
@export var left_lookat_modifier: SkeletonModifier3D
## 右腳 LookAtModifier3D
@export var right_lookat_modifier: SkeletonModifier3D
## LookAt 目標距離腳踝的前方距離
@export var lookat_forward_offset: float = 0.2

var _left_foot_idx: int = -1
var _right_foot_idx: int = -1
var _left_hip_idx: int = -1
var _right_hip_idx: int = -1

# 鎖定標記（完全鎖定）
var left_foot_locked: bool = false
var right_foot_locked: bool = false
const STAIR_SUPPORT_LOCK_MIN_GROUND_DIFF: float = 0.06
const STAIR_SUPPORT_RELEASE_EPSILON: float = 0.03
const STAIR_SUPPORT_LOCK_TIMEOUT: float = 0.55
const STAIR_LOCK_STABLE_FRAMES: int = 2
const STAIR_RELEASE_STABLE_FRAMES: int = 3
const STAIR_LOCK_XZ_EPSILON: float = 0.12
const STAIR_STANCE_XZ_DRIFT_EPSILON: float = 0.0
var _stair_support_lock_timer: float = 0.0
var _stair_last_support_foot: String = ""
var _stair_expected_support_foot: String = ""
var _stair_left_lock_candidate_frames: int = 0
var _stair_right_lock_candidate_frames: int = 0
var _stair_left_release_candidate_frames: int = 0
var _stair_right_release_candidate_frames: int = 0


# Y 軸鎖定（支撐腳：鎖 Y 允許 XZ 微調）
var left_foot_y_locked: bool = false
var right_foot_y_locked: bool = false
var _locked_left_y: float = 0.0
var _locked_right_y: float = 0.0

# 當前 IK influence
var _current_influence: float = 0.0

# Per-foot influence 覆蓋（-1 表示不覆蓋，使用全局 influence）
var _left_influence_override: float = -1.0
var _right_influence_override: float = -1.0

# 骨盆偏移相關
var _left_ground_y: float = 0.0
var _right_ground_y: float = 0.0
var _current_pelvis_offset: float = 0.0
var _original_skeleton_y: float = 0.0
var _skeleton_parent: Node3D = null

# Debug 視覺化
var _debug_left_ray_start: Vector3
var _debug_left_ray_end: Vector3
var _debug_left_ground: Vector3
var _debug_right_ray_start: Vector3
var _debug_right_ray_end: Vector3
var _debug_right_ground: Vector3
var _debug_left_hit: bool = false
var _debug_right_hit: bool = false
var _debug_draw_3d = null # ★ 快取 DebugDraw3D singleton

# 腳旋轉數據
var _left_foot_pitch: float = 0.0
var _right_foot_pitch: float = 0.0

# ShapeCast 用：偵測到的地面法線
var _left_ground_normal: Vector3 = Vector3.UP
var _right_ground_normal: Vector3 = Vector3.UP

# 模式追蹤（偵測 B→C 切換用）
var _was_moving: bool = false
var _was_ik_enabled: bool = true  # ★ 追蹤 IK 啟用狀態轉換（跳躍落地 reset 用）

## ★ 停止動畫期間標記（由 SimpleCapsuleMove 設定）
var stop_anim_active: bool = false

## ★ 外部禁用預測標記（如：播放專屬樓梯動畫時）
var temporary_disable_predict_ik: bool = false

## ★ 樓梯 IK 啟動標記（由外部設定，當角色在樓梯上時為 true）
var stair_ik_active: bool = false

# ★ 動態步伐相位 (Animation Height Based)
var _left_foot_phase: float = 1.0
var _right_foot_phase: float = 1.0
var _char_body: CharacterBody3D = null
# ★★★ 動畫原始骨骼高度（在 _process 中讀取，不受 IK 影響）★★★
var _left_anim_foot_y: float = 0.08
var _right_anim_foot_y: float = 0.08

# ★★★ Predictive IK - Spring-Damper 狀態 ★★★
var _left_spring_pos: Vector3 = Vector3.ZERO  # 當前彈簧位置
var _left_spring_vel: Vector3 = Vector3.ZERO  # 當前彈簧速度
var _right_spring_pos: Vector3 = Vector3.ZERO
var _right_spring_vel: Vector3 = Vector3.ZERO
var _spring_initialized: bool = false

# ★★★ Phase C: Stance Locking 狀態 ★★★
# Stance phase 時鎖定地面接觸點，避免每幀重新 raycast 造成微抖
var _left_stance_locked: bool = false
var _right_stance_locked: bool = false
var _left_locked_ground: Vector3 = Vector3.ZERO   # 鎖定的地面位置
var _right_locked_ground: Vector3 = Vector3.ZERO
var _left_ground_pos: Vector3 = Vector3.ZERO
var _right_ground_pos: Vector3 = Vector3.ZERO
var _left_locked_normal: Vector3 = Vector3.UP
var _right_locked_normal: Vector3 = Vector3.UP
const STANCE_LOCK_THRESHOLD: float = 0.85    # phase > 此值 = stance（腳著地）
const SWING_UNLOCK_THRESHOLD: float = 0.5    # phase < 此值 = swing（腳離地）

# ★ Stride Warping - 動畫設計速度（由 SimpleCapsuleMove 寫入）
var _stride_anim_speed: float = 1.4

# ★★★ Predictive IK - Temporal Interpolation 狀態 ★★★
var _prev_left_target: Vector3 = Vector3.ZERO  # 上一物理幀的 target
var _prev_right_target: Vector3 = Vector3.ZERO
var _curr_left_target: Vector3 = Vector3.ZERO   # 當前物理幀的 target
var _curr_right_target: Vector3 = Vector3.ZERO

# ★★★ Predictive IK - Debug 預測點 ★★★
var _debug_left_predict_pos: Vector3 = Vector3.ZERO
var _debug_right_predict_pos: Vector3 = Vector3.ZERO

# ★★★ PredictIK - Swing 步預測狀態（參考 PredictIK.cs）★★★
# 每隻腳在 Swing 開始時 lookahead raycast → 建立高度曲線
var _left_pred_start_pos: Vector3 = Vector3.ZERO  # 起步地面位置
var _left_pred_end_y: float = 0.0                  # 落腳地面 Y
var _left_pred_mid_y: float = 0.0                  # 路徑中障礙物最高點 Y
var _left_pred_mid_t: float = 0.5                  # 障礙物位置 (0~1 正規化)
var _left_pred_active: bool = false                 # 是否有有效的預測
var _left_pred_virtual_y: float = 0.0              # 當前幀的虛擬腳高度
var _left_pred_end_pos: Vector3 = Vector3.ZERO
var _left_pred_forward: Vector3 = Vector3.ZERO
var _left_swing_elapsed: float = 0.0
var _left_swing_duration: float = 0.25
var _left_was_swing: bool = false                   # 上一幀是否在 swing

var _right_pred_start_pos: Vector3 = Vector3.ZERO
var _right_pred_end_y: float = 0.0
var _right_pred_mid_y: float = 0.0
var _right_pred_mid_t: float = 0.5
var _right_pred_active: bool = false
var _right_pred_virtual_y: float = 0.0
var _right_pred_end_pos: Vector3 = Vector3.ZERO
var _right_pred_forward: Vector3 = Vector3.ZERO
var _right_swing_elapsed: float = 0.0
var _right_swing_duration: float = 0.25
var _right_was_swing: bool = false

# SphereCast 碰撞形狀（快取）
var _predict_sphere_shape: SphereShape3D = null

const PREDICT_PATH_SAMPLE_COUNT: int = 3
const MIN_SWING_DURATION: float = 0.16
const MAX_SWING_DURATION: float = 0.48

# ★ Profiling 累計器
var _prof_frame_count: int = 0
var _prof_ground_us: int = 0
var _prof_pelvis_us: int = 0
var _prof_ik_target_us: int = 0
var _prof_ankle_us: int = 0
var _prof_debug_us: int = 0
var _prof_phase_us: int = 0
var _prof_total_us: int = 0

# ★ 快取 PhysicsRayQueryParameters3D（避免每幀分配新物件）
var _cached_ray_query: PhysicsRayQueryParameters3D = null


func _ready() -> void:
	if not skeleton:
		push_error("[SimpleFootIK] No skeleton assigned!")
		return
		
	# ★ IK 位置權重：全開 (1.0)，由 foot phase 控制 swing/stance 混合
	# 注意：腳踝旋轉在移動時已關閉 (ankle_weight=0)，不會干擾動畫
	moving_influence = 1.0
	standing_influence = 1.0
		
	# 尋找 CharacterBody3D 祖先
	var p = get_parent()
	while p:
		if p is CharacterBody3D:
			_char_body = p
			break
		p = p.get_parent()
	if not _char_body:
		push_warning("[SimpleFootIK] ⚠️ No CharacterBody3D found in ancestors!")
	
	# ★ 注意：不強制覆蓋 AnimationTree 或 Skeleton 的 process mode
	# 以免造成 T-Pose。IK 修正在 _physics_process 中計算目標位置即可。
	
	# 檢查 IK 節點是否已設定
	if left_ik:
		left_ik.active = false
		if left_target:
			var path = left_ik.get_path_to(left_target)
			left_ik.set("settings/0/target_node", path)
			# ★ 驗證 target 是否真的可解析
			var resolved = left_ik.get_node_or_null(path)
			print("[SimpleFootIK] Left IK target: %s → resolved=%s" % [path, resolved != null])
	else:
		push_warning("[SimpleFootIK] ⚠️ left_ik not assigned!")
		
	if right_ik:
		right_ik.active = false
		if right_target:
			var path = right_ik.get_path_to(right_target)
			right_ik.set("settings/0/target_node", path)
			var resolved = right_ik.get_node_or_null(path)
			print("[SimpleFootIK] Right IK target: %s → resolved=%s" % [path, resolved != null])
	else:
		push_warning("[SimpleFootIK] ⚠️ right_ik not assigned!")
		
	_left_foot_idx = _find_bone(["LeftFoot", "mixamorig1_LeftFoot"])
	_right_foot_idx = _find_bone(["RightFoot", "mixamorig1_RightFoot"])
	_left_hip_idx = _find_bone(["LeftUpperLeg", "mixamorig1_LeftUpperLeg", "LeftThigh"])
	_right_hip_idx = _find_bone(["RightUpperLeg", "mixamorig1_RightUpperLeg", "RightThigh"])
	
	print("[SimpleFootIK] Left foot bone idx: ", _left_foot_idx)
	print("[SimpleFootIK] Right foot bone idx: ", _right_foot_idx)
	
	if left_lookat_modifier: left_lookat_modifier.active = false  # ★ 延遲啟用
	if right_lookat_modifier: right_lookat_modifier.active = false
	
	# 記錄骨架的原始位置（相對於父節點）
	_skeleton_parent = skeleton.get_parent()
	if _skeleton_parent:
		_original_skeleton_y = skeleton.position.y
		print("[SimpleFootIK] Pelvis offset enabled, original skeleton Y: ", _original_skeleton_y)
	
	# ★ 快取 DebugDraw3D singleton（避免每幀字串查詢）
	if Engine.has_singleton("DebugDraw3D"):
		_debug_draw_3d = Engine.get_singleton("DebugDraw3D")
	
	# ★ 延遲初始化目標位置，避免在第一幀腳被吸到 (0,0,0)
	call_deferred("_init_targets")
	
	# ★ 快取 ray query 物件（每幀重用，省 120+ 次/秒的物件分配）
	_cached_ray_query = PhysicsRayQueryParameters3D.new()
	_cached_ray_query.collision_mask = _get_foot_collision_mask()


func _init_targets() -> void:
	if not skeleton: return
	if left_target and _left_foot_idx >= 0:
		left_target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)
		# ★ 初始化 spring/temporal 到實際腳位
		_left_spring_pos = left_target.global_position
		_prev_left_target = left_target.global_position
		_curr_left_target = left_target.global_position
	if right_target and _right_foot_idx >= 0:
		right_target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)
		_right_spring_pos = right_target.global_position
		_prev_right_target = right_target.global_position
		_curr_right_target = right_target.global_position
	# 初始化 LookAt 目標（腳前方）
	if left_lookat_target and _left_foot_idx >= 0:
		var lfoot = skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)
		left_lookat_target.global_position = lfoot.origin - skeleton.global_transform.basis.z * lookat_forward_offset
	if right_lookat_target and _right_foot_idx >= 0:
		var rfoot = skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)
		right_lookat_target.global_position = rfoot.origin - skeleton.global_transform.basis.z * lookat_forward_offset
	# ★ 極度重要：我們不再於 _init_targets 階段啟動 active = true
	# 因為此時 Skeleton 與世界座標可能還為 0，導致 C++ 內部計算出現 (0,0,0) 並崩潰 (Segment Fault)
	# 改由 _process 內部的安全機制來非同步啟動。


func _find_bone(candidates: Array) -> int:
	for n in candidates:
		var idx = skeleton.find_bone(n)
		if idx != -1:
			return idx
	return -1


func _get_foot_collision_mask() -> int:
	return 2 if _is_stair_ascending_active() else 1


func _physics_process(delta: float) -> void:
	if not skeleton:
		return
	
	# ★ 計算物理幀數（供 temporal interpolation 延遲啟動用）
	if _temporal_physics_frames < 10:
		_temporal_physics_frames += 1
	
	# ★★★ 業界標準：三層 Foot Placement ★★★
	# Layer 1: 偵測地面 (Raycast)
	# Layer 2: 骨盆偏移 (Pelvis Offset) — 讓最低腳能碰到地面
	# Layer 3a: TwoBoneIK — 把較高的腳拉到它的地面接觸點
	# Layer 3b: 腳踝旋轉 (LookAt) — 腳底對齊地面法線
	
	# --- 使用預先找到的 CharacterBody3D ---
	var velocity := Vector3.ZERO
	if _char_body:
		velocity = _char_body.velocity
	var speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = speed > standing_threshold
	# 暫時停用樓梯特化邏輯，回退到一般地形 IK 行為。
	stair_ik_active = false
	if Engine.get_physics_frames() % 60 == 0:
		var _sys = _char_body.get("_stair_system") if _char_body else null
		var _st = _char_body.get("stair") if _char_body else null
		print("[FootIK] stair_ik_active=%s | _stair_system=%s stair.on=%s stair.asc=%s" % [
			stair_ik_active,
			_sys != null,
			_st.on_stairs if _st else "N/A",
			_st.ascending if _st else "N/A"
		])
	
	# ★ 樓梯/外部禁用時：淡出 IK influence 到 0，但仍然執行地面偵測和 debug draw
	if not ik_enabled:
		_current_influence = lerp(_current_influence, 0.0, delta * 10.0)
		if left_ik: left_ik.influence = _current_influence
		if right_ik: right_ik.influence = _current_influence
		_was_moving = is_moving
		# ★ 即使 IK 禁用，仍然執行地面偵測 + 預測計算（為了 debug draw 和數據連續性）
		var space_disabled = get_world_3d().direct_space_state
		var exclude_disabled = [_char_body.get_rid()] if _char_body else []
		if _left_foot_idx >= 0:
			var lr = _detect_ground(_left_foot_idx, left_foot_shape, space_disabled, exclude_disabled)
			_left_ground_y = lr.y
			_left_ground_normal = lr.normal
		if _right_foot_idx >= 0:
			var rr = _detect_ground(_right_foot_idx, right_foot_shape, space_disabled, exclude_disabled)
			_right_ground_y = rr.y
			_right_ground_normal = rr.normal
		if debug_draw:
			_draw_debug()
		# ★ 即使 IK 禁用，樓梯預測仍需運行（預測落腳點 + debug draw）
		if stair_ik_active:
			_update_predict_ik(delta, space_disabled, exclude_disabled)
			_update_stair_support_lock(delta)
		_was_ik_enabled = false
		return
	
	# ★ IK 重新啟用（跳躍落地）時：reset 所有彈簧和 temporal 狀態
	if not _was_ik_enabled:
		_was_ik_enabled = true
		# 取得當前腳骨世界位置
		var l_foot_pos = Vector3.ZERO
		var r_foot_pos = Vector3.ZERO
		if _left_foot_idx >= 0:
			l_foot_pos = (skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)).origin
		if _right_foot_idx >= 0:
			r_foot_pos = (skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)).origin
		# Reset 彈簧
		_left_spring_pos = l_foot_pos
		_left_spring_vel = Vector3.ZERO
		_right_spring_pos = r_foot_pos
		_right_spring_vel = Vector3.ZERO
		# Reset temporal interpolation
		_prev_left_target = l_foot_pos
		_curr_left_target = l_foot_pos
		_prev_right_target = r_foot_pos
		_curr_right_target = r_foot_pos
		# Reset stance lock
		_left_stance_locked = false
		_right_stance_locked = false
		_left_was_swing = false
		_right_was_swing = false
		_left_swing_elapsed = 0.0
		_right_swing_elapsed = 0.0
	
	# --- 樓梯偵測（已移除，平地與樓梯統一判斷）---
	
	# ★ 偵測模式切換：移動→靜止
	var entering_standing = not is_moving
	if entering_standing and _was_moving:
		_left_stance_locked = false
		_right_stance_locked = false
		_left_foot_phase = 1.0
		_right_foot_phase = 1.0
		_left_was_swing = false
		_right_was_swing = false
		_left_swing_elapsed = 0.0
		_right_swing_elapsed = 0.0
		
		# ★ 斜坡判定：平地才歸零 influence，斜坡保持 IK 活躍
		var avg_normal_up = (_left_ground_normal.dot(Vector3.UP) + _right_ground_normal.dot(Vector3.UP)) * 0.5
		if avg_normal_up > 0.95:
			# 平地：snap targets 到骨骼位置，歸零 influence（讓停止動畫自然播放）
			if left_target and _left_foot_idx >= 0:
				left_target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)
			if right_target and _right_foot_idx >= 0:
				right_target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)
			_current_influence = 0.0
			if left_ik: left_ik.influence = 0.0
			if right_ik: right_ik.influence = 0.0
			_was_moving = is_moving
			return
		# 斜坡：不歸零 influence，不 return → 繼續正常 IK 更新流程
	_was_moving = is_moving
	
	var _t0 = Time.get_ticks_usec() if enable_profiling else 0
	# ★★★ 計算動態腳步相位 (Animation Height Based) ★★★
	# ★★★ 核心修正：使用 _process 中讀取的動畫原始骨骼高度 ★★★
	# _left_anim_foot_y / _right_anim_foot_y 在 _process 中讀取
	# → 在 Skeleton modifier (TwoBoneIK) 之前 → 純動畫值
	# → 不受 IK 反饋影響 → 完全打斷反饋迴路
	var body_pos = _char_body.global_position if _char_body else Vector3.ZERO
	var body_y = body_pos.y
	
	var left_target_phase = 1.0
	var right_target_phase = 1.0
	
	if is_moving:
		# ★ 動畫骨骼高度相對於角色腳底的偏移
		# foot_height_offset ≈ 踝骨到鞋底距離
		# 偏移 ≈ 0 → 腳在地面上（Stance）→ phase = 1.0
		# 偏移 > 幾公分 → 腳在空中（Swing）→ phase = 0.0
		var l_above = (_left_anim_foot_y - body_y) - foot_height_offset
		var r_above = (_right_anim_foot_y - body_y) - foot_height_offset
		
		# 平滑閾值：0~2cm = Stance, 2~8cm = 過渡, >8cm = Swing
		left_target_phase = 1.0 - clampf((l_above - 0.02) / 0.06, 0.0, 1.0)
		right_target_phase = 1.0 - clampf((r_above - 0.02) / 0.06, 0.0, 1.0)
	# 站立 → phase 強制 1.0（兩腳都貼地）
	
	# 平滑過渡 Phase
	_left_foot_phase = lerp(_left_foot_phase, left_target_phase, delta * 12.0)
	_right_foot_phase = lerp(_right_foot_phase, right_target_phase, delta * 12.0)
	
	# ★ 雙腳協調 — 防止兩腳同時 Swing（至少一隻在地面）
	if is_moving and _left_foot_phase < 0.3 and _right_foot_phase < 0.3:
		# 強制較低的腳為 Stance
		if _left_anim_foot_y <= _right_anim_foot_y:
			_left_foot_phase = maxf(_left_foot_phase, 0.8)
		else:
			_right_foot_phase = maxf(_right_foot_phase, 0.8)
	
	# ★★★ IK Influence 計算 ★★★
	var target_base_influence = moving_influence if is_moving else standing_influence
	var avg_slope = (_left_ground_normal.dot(Vector3.UP) + _right_ground_normal.dot(Vector3.UP)) * 0.5
	
	# ★ 停止動畫期間：優先讓作者動畫接管，避免腳被 IK 從後方拉住
	if stop_anim_active:
		var on_flat = avg_slope > 0.95
		if on_flat:
			target_base_influence = 0.0
		else:
			target_base_influence = minf(target_base_influence, 0.35)
	
	_current_influence = lerp(_current_influence, target_base_influence, delta * influence_speed)
	
	# 站立時用 phase 降低 swing 腳的 influence
	var final_left_influence: float = _current_influence
	var final_right_influence: float = _current_influence
	if not is_moving:
		final_left_influence = _current_influence * _left_foot_phase
		final_right_influence = _current_influence * _right_foot_phase
	if left_foot_locked:
		final_left_influence = 1.0
	if right_foot_locked:
		final_right_influence = 1.0
	if _left_influence_override >= 0.0:
		final_left_influence = clampf(_left_influence_override, 0.0, 1.0)
	if _right_influence_override >= 0.0:
		final_right_influence = clampf(_right_influence_override, 0.0, 1.0)
	# ★ 方案 B: 樓梯上強制 IK 全權重（走路動畫 + IK 控制腳步）
	if stair_ik_active:
		final_left_influence = 1.0
		final_right_influence = 1.0
	
	if left_ik: left_ik.influence = final_left_influence
	if right_ik: right_ik.influence = final_right_influence
	
	# (verbose IK-DIAG removed — see consolidated output below)
	var _t1 = Time.get_ticks_usec() if enable_profiling else 0
	
	# ═══ 永遠執行 Ground Detection 和 IK (讓腳能適應階梯) ═══
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = [_char_body.get_rid()] if _char_body else []
	_cached_ray_query.collision_mask = _get_foot_collision_mask()
	
	var left_ground_res: GroundResult
	var right_ground_res: GroundResult
	
	# ★★★ PredictIK 更新必須在地面偵測之前 ★★★
	# 確保停止時先清空預測狀態，避免 _detect_ground 使用過時的 pred_end
	_update_predict_ik(delta, space_state, exclude_rid)
	
	# ═══ 永遠偵測地面（兩腳都執行，確保數據即時更新）═══
	if _left_foot_idx >= 0:
		left_ground_res = _detect_ground(_left_foot_idx, left_foot_shape, space_state, exclude_rid)
		_left_ground_y = left_ground_res.y
		_left_ground_pos = left_ground_res.pos
		_left_ground_normal = left_ground_res.normal
	if _right_foot_idx >= 0:
		right_ground_res = _detect_ground(_right_foot_idx, right_foot_shape, space_state, exclude_rid)
		_right_ground_y = right_ground_res.y
		_right_ground_pos = right_ground_res.pos
		_right_ground_normal = right_ground_res.normal
	_update_stair_support_lock(delta)
	var _t2 = Time.get_ticks_usec() if enable_profiling else 0
	
	# --- 骨盆偏移 (盡量只在雙腳都有相位時逐漸生效，避免抖動) ---
	if enable_pelvis_offset and _skeleton_parent:
		var active_phase = max(_left_foot_phase, _right_foot_phase)
		if is_moving:
			_apply_pelvis_offset(delta * 0.5 * active_phase)
		else:
			_apply_pelvis_offset(delta)
			
	var _t3 = Time.get_ticks_usec() if enable_profiling else 0
	# --- IK 目標位置更新 ---
	if left_target and _left_foot_idx >= 0 and left_ground_res:
		_update_ik_target(left_target, _left_foot_idx, _left_hip_idx, left_ground_res, delta)
	if right_target and _right_foot_idx >= 0 and right_ground_res:
		_update_ik_target(right_target, _right_foot_idx, _right_hip_idx, right_ground_res, delta)
	var _t4 = Time.get_ticks_usec() if enable_profiling else 0
	
	# --- 腳踝旋轉已交由 AnkleAlignModifier3D 處理 ---
	
	var _t5 = Time.get_ticks_usec() if enable_profiling else 0
	# 除錯繪製
	if debug_draw:
		_draw_debug()
	var _t6 = Time.get_ticks_usec() if enable_profiling else 0
	
	# ★★★ 精簡診斷：每 120 幀輸出一次斜坡 IK 狀態 ★★★
	if Engine.get_physics_frames() % 120 == 0:
		var body_y_diag = _char_body.global_position.y if _char_body else 0.0
		var l_gnd = _left_ground_y
		var r_gnd = _right_ground_y
		var l_nrm = _left_ground_normal
		var r_nrm = _right_ground_normal
		var l_mk = left_target.global_position.y if left_target else -1.0
		var r_mk = right_target.global_position.y if right_target else -1.0
		var l_infl = left_ik.influence if left_ik else 0.0
		var r_infl = right_ik.influence if right_ik else 0.0
		print("[FootIK] %s body=%.2f | L: ph=%.2f anim=%.3f gnd=%.3f mk=%.3f infl=%.2f n=(%.2f,%.2f,%.2f) | R: ph=%.2f anim=%.3f gnd=%.3f mk=%.3f infl=%.2f n=(%.2f,%.2f,%.2f)" % [
			"MOVE" if is_moving else "IDLE", body_y_diag,
			_left_foot_phase, _left_anim_foot_y, l_gnd, l_mk, l_infl, l_nrm.x, l_nrm.y, l_nrm.z,
			_right_foot_phase, _right_anim_foot_y, r_gnd, r_mk, r_infl, r_nrm.x, r_nrm.y, r_nrm.z
		])
	
	# ★ Profiling 統計輸出
	if enable_profiling:
		_prof_phase_us += _t1 - _t0
		_prof_ground_us += _t2 - _t1
		_prof_pelvis_us += _t3 - _t2
		_prof_ik_target_us += _t4 - _t3
		_prof_ankle_us += _t5 - _t4
		_prof_debug_us += _t6 - _t5
		_prof_total_us += _t6 - _t0
		_prof_frame_count += 1
		if _prof_frame_count >= 120:
			var n := float(_prof_frame_count)
			print("[FootIK Profile] %d frames | phase=%.0fus | ground=%.0fus | pelvis=%.0fus | ik_target=%.0fus | ankle=%.0fus | debug=%.0fus | TOTAL=%.0fus" % [
				_prof_frame_count,
				_prof_phase_us / n, _prof_ground_us / n, _prof_pelvis_us / n,
				_prof_ik_target_us / n, _prof_ankle_us / n, _prof_debug_us / n,
				_prof_total_us / n
			])
			_prof_frame_count = 0
			_prof_ground_us = 0
			_prof_pelvis_us = 0
			_prof_ik_target_us = 0
			_prof_ankle_us = 0
			_prof_debug_us = 0
			_prof_phase_us = 0
			_prof_total_us = 0


## ★★★ 統一地面偵測：ShapeCast 優先，RayCast 備用 ★★★
class GroundResult:
	var y: float
	var normal: Vector3
	var pos: Vector3
	func _init(p_pos: Vector3, p_normal: Vector3):
		y = p_pos.y
		normal = p_normal
		pos = p_pos

## Debug 用：找最接近 foot_y 的台階頂面
func _find_nearest_step(foot_y: float, step_tops: Array) -> float:
	var nearest = step_tops[0]
	var min_dist = abs(foot_y - nearest)
	for s in step_tops:
		var d = abs(foot_y - s)
		if d < min_dist:
			min_dist = d
			nearest = s
	return nearest

func _detect_ground(foot_idx: int, shape_cast: ShapeCast3D, space: PhysicsDirectSpaceState3D, exclude: Array) -> GroundResult:
	var bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(foot_idx)
	var foot_pos = bone_global.origin
	
	# ★★★ 補償 Pelvis 偏移 ★★★
	# skeleton.position.y 被 _update_pelvis_offset 修改過
	# → bone position 已經包含 pelvis 下推量 → 射線從錯誤高度發射
	# → 在斜坡上會穿過坡面打到平地 → 反饋迴路
	# 修正：將 foot_pos 還原到「沒有 pelvis 偏移」的高度
	foot_pos.y -= _current_pelvis_offset  # 減去偏移 = 還原
	
	# ★★★ GASP-Style Phase-Driven 預測（Phase C 增強）★★★
	# Stance (planted): 鎖定地面接觸點，不再重新 raycast → 消除微抖
	# Swing (in air):   模擬軌跡預測未來落地點 → 提前 raycast
	# Transition:       swing→stance 時彈簧加硬 → 快速收斂到落點
	var predict_pos = foot_pos
	var is_left = (foot_idx == _left_foot_idx)
	var foot_phase = _left_foot_phase if is_left else _right_foot_phase
	var was_locked = _left_stance_locked if is_left else _right_stance_locked
	
	# Phase 狀態機：判斷 Stance Lock / Swing Unlock
	var is_stance = foot_phase > STANCE_LOCK_THRESHOLD
	var _is_swing = foot_phase < SWING_UNLOCK_THRESHOLD
	
	if enable_predictive_ik and _char_body and not temporary_disable_predict_ik and not stop_anim_active:
		var h_vel = Vector3(_char_body.velocity.x, 0, _char_body.velocity.z)
		var h_speed = h_vel.length()
		
		if h_speed > min_prediction_speed:
			var pred_active = _left_pred_active if is_left else _right_pred_active
			var pred_end = _left_pred_end_pos if is_left else _right_pred_end_pos
			if pred_active and foot_phase < plant_enter_phase_threshold:
				predict_pos = Vector3(pred_end.x, foot_pos.y, pred_end.z)
			elif is_stance and was_locked:
				# ★ Stance Phase：使用鎖定的地面位置（不 raycast）
				predict_pos = foot_pos  # 不偏移，用腳骨位置做 raycast
			else:
				# ★ Swing Phase：模擬軌跡預測前方落點
				var swing_factor = 1.0 - foot_phase  # 0=planted, 1=fully swinging
				var predict_time = (prediction_stride_length / h_speed) * swing_factor
				
				var predict_offset = _simulate_trajectory_offset(h_vel, predict_time)
				
				# ★ Feature #6：斜面步幅補償 — 上坡縮短、下坡拉長
				var ground_normal = _left_ground_normal if is_left else _right_ground_normal
				var slope_cos = ground_normal.dot(Vector3.UP)
				if slope_cos < 0.99:  # 不是完全平地
					predict_offset *= slope_cos  # cos(30°)=0.87, cos(45°)=0.71
				
				# ★ Feature #7：轉彎步幅補償 — 內側腳縮短、外側腳拉長
				if _prediction_input_dir.length_squared() > 0.01:
					var target_dir = _prediction_input_dir.normalized()
					var h_dir = h_vel.normalized()
					var turn_cross_y = h_dir.x * target_dir.z - h_dir.z * target_dir.x
					var turn_amount = clampf(absf(turn_cross_y), 0.0, 0.5)
					# turn_cross_y > 0 = 左轉 → 左腳是內側
					var turn_scale: float
					if is_left:
						turn_scale = 1.0 - turn_amount * signf(turn_cross_y)
					else:
						turn_scale = 1.0 + turn_amount * signf(turn_cross_y)
					predict_offset *= clampf(turn_scale, 0.5, 1.5)
				
				# 限制最大偏移（防急轉彎跳動）
				if predict_offset.length() > max_prediction_offset:
					predict_offset = predict_offset.normalized() * max_prediction_offset
				predict_pos = foot_pos + predict_offset
	
	# 保存 debug 預測點
	if foot_idx == _left_foot_idx:
		_debug_left_predict_pos = predict_pos
	else:
		_debug_right_predict_pos = predict_pos
	
	# ★ ShapeCast 已停用（球體在斜坡上「最高碰撞點」比實際地面高 → 造成懸空）
	# 改用下方的 RayCast（精確打在腳正下方的地面）
	#if shape_cast:
	#	...（原 ShapeCast 邏輯保留但不執行）
	
	# ★ 單點 RayCast：從腳踝正下方精準偵測地面
	# 腳趾穿模由 AnkleAlignModifier3D 旋轉腳掌自然解決
	_cached_ray_query.from = predict_pos + Vector3.UP * 0.3
	_cached_ray_query.to = predict_pos + Vector3.DOWN * ray_length
	_cached_ray_query.exclude = exclude
	var result = space.intersect_ray(_cached_ray_query)
	if not result.is_empty():
		return GroundResult.new(result.position, result.normal)
	
	# ★ Feature #4：Swing 落點驗證 — 預測點無地面（懸崖），回退到腳骨位置
	if predict_pos != foot_pos:
		_cached_ray_query.from = foot_pos + Vector3.UP * 0.3
		_cached_ray_query.to = foot_pos + Vector3.DOWN * ray_length
		var fallback = space.intersect_ray(_cached_ray_query)
		if not fallback.is_empty():
			return GroundResult.new(fallback.position, fallback.normal)
	
	return GroundResult.new(foot_pos, Vector3.UP)


func _reset_stair_support_lock() -> void:
	left_foot_locked = false
	right_foot_locked = false
	_stair_support_lock_timer = 0.0
	_stair_last_support_foot = ""
	_stair_expected_support_foot = ""
	_stair_left_lock_candidate_frames = 0
	_stair_right_lock_candidate_frames = 0
	_stair_left_release_candidate_frames = 0
	_stair_right_release_candidate_frames = 0


func _is_stair_ascending_active() -> bool:
	if not _char_body:
		return false
	# 優先檢查 PlayerStairsController 的 data（新系統）
	var stair_sys = _char_body.get("_stair_system")
	if stair_sys and stair_sys.data:
		return bool(stair_sys.data.on_stairs and stair_sys.data.ascending)
	# 退回檢查 SimpleCapsuleMove.stair（舊系統）
	var stair_data = _char_body.get("stair")
	if stair_data == null:
		return false
	return bool(stair_data.on_stairs and stair_data.ascending)


func _update_stair_support_lock(delta: float) -> void:
	_reset_stair_support_lock()
	return
	if not _is_stair_ascending_active():
		_reset_stair_support_lock()
		return

	_stair_support_lock_timer += delta
	
	# 用預測落點判斷哪隻腳在上面
	var l_pred_y = _left_pred_end_y if _left_pred_active else _left_ground_y
	var r_pred_y = _right_pred_end_y if _right_pred_active else _right_ground_y
	var left_higher = l_pred_y > r_pred_y + STAIR_SUPPORT_LOCK_MIN_GROUND_DIFF
	var right_higher = r_pred_y > l_pred_y + STAIR_SUPPORT_LOCK_MIN_GROUND_DIFF

	# 檢查腳是否已經到達預測落點附近
	var l_at_target = false
	var r_at_target = false
	if left_target and _left_pred_active:
		var l_target_xz = Vector2(left_target.global_position.x, left_target.global_position.z)
		var l_pred_xz = Vector2(_left_pred_end_pos.x, _left_pred_end_pos.z)
		l_at_target = absf(left_target.global_position.y - (_left_pred_end_y + foot_height_offset)) < 0.06 and l_target_xz.distance_to(l_pred_xz) < STAIR_LOCK_XZ_EPSILON
	if right_target and _right_pred_active:
		var r_target_xz = Vector2(right_target.global_position.x, right_target.global_position.z)
		var r_pred_xz = Vector2(_right_pred_end_pos.x, _right_pred_end_pos.z)
		r_at_target = absf(right_target.global_position.y - (_right_pred_end_y + foot_height_offset)) < 0.06 and r_target_xz.distance_to(r_pred_xz) < STAIR_LOCK_XZ_EPSILON

	if _stair_expected_support_foot.is_empty():
		if _stair_last_support_foot == "left":
			_stair_expected_support_foot = "right"
		elif _stair_last_support_foot == "right":
			_stair_expected_support_foot = "left"
		elif _left_foot_phase < _right_foot_phase:
			_stair_expected_support_foot = "left"
		else:
			_stair_expected_support_foot = "right"

	if not left_foot_locked and not right_foot_locked:
		var left_lock_ready = _stair_expected_support_foot == "left" and left_higher and l_at_target
		var right_lock_ready = _stair_expected_support_foot == "right" and right_higher and r_at_target

		_stair_left_lock_candidate_frames = _stair_left_lock_candidate_frames + 1 if left_lock_ready else 0
		_stair_right_lock_candidate_frames = _stair_right_lock_candidate_frames + 1 if right_lock_ready else 0

		if _stair_left_lock_candidate_frames >= STAIR_LOCK_STABLE_FRAMES:
			left_foot_locked = true
			_left_locked_ground = left_target.global_position if left_target else (_left_ground_pos + Vector3(0, foot_height_offset, 0))
			_stair_support_lock_timer = 0.0
			_stair_last_support_foot = "left"
			_stair_left_lock_candidate_frames = 0
			_stair_right_lock_candidate_frames = 0
			_stair_left_release_candidate_frames = 0
			_stair_right_release_candidate_frames = 0
			if debug_draw and Engine.get_physics_frames() % 30 == 0:
				print("[StairLock] LEFT 鎖定 y=%.3f expected=%s" % [_left_locked_ground.y, _stair_expected_support_foot])
		elif _stair_right_lock_candidate_frames >= STAIR_LOCK_STABLE_FRAMES:
			right_foot_locked = true
			_right_locked_ground = right_target.global_position if right_target else (_right_ground_pos + Vector3(0, foot_height_offset, 0))
			_stair_support_lock_timer = 0.0
			_stair_last_support_foot = "right"
			_stair_left_lock_candidate_frames = 0
			_stair_right_lock_candidate_frames = 0
			_stair_left_release_candidate_frames = 0
			_stair_right_release_candidate_frames = 0
			if debug_draw and Engine.get_physics_frames() % 30 == 0:
				print("[StairLock] RIGHT 鎖定 y=%.3f expected=%s" % [_right_locked_ground.y, _stair_expected_support_foot])
	elif left_foot_locked:
		# 左腳鎖定，等右腳追上（到達它自己的預測位置附近）
		var right_caught_up = r_at_target or (_right_ground_y >= _left_locked_ground.y - 0.08)
		_stair_right_release_candidate_frames = _stair_right_release_candidate_frames + 1 if right_caught_up else 0
		if (_stair_support_lock_timer >= 0.15 and _stair_right_release_candidate_frames >= STAIR_RELEASE_STABLE_FRAMES) or _stair_support_lock_timer >= STAIR_SUPPORT_LOCK_TIMEOUT:
			left_foot_locked = false
			_stair_support_lock_timer = 0.0
			_stair_last_support_foot = "left"
			_stair_expected_support_foot = "right"
			_stair_left_release_candidate_frames = 0
			_stair_right_release_candidate_frames = 0
			if debug_draw and Engine.get_physics_frames() % 30 == 0:
				print("[StairLock] LEFT 解鎖 (caught=%s next=%s)" % [right_caught_up, _stair_expected_support_foot])
	elif right_foot_locked:
		# 右腳鎖定，等左腳追上
		var left_caught_up = l_at_target or (_left_ground_y >= _right_locked_ground.y - 0.08)
		_stair_left_release_candidate_frames = _stair_left_release_candidate_frames + 1 if left_caught_up else 0
		if (_stair_support_lock_timer >= 0.15 and _stair_left_release_candidate_frames >= STAIR_RELEASE_STABLE_FRAMES) or _stair_support_lock_timer >= STAIR_SUPPORT_LOCK_TIMEOUT:
			right_foot_locked = false
			_stair_support_lock_timer = 0.0
			_stair_last_support_foot = "right"
			_stair_expected_support_foot = "left"
			_stair_left_release_candidate_frames = 0
			_stair_right_release_candidate_frames = 0
			if debug_draw and Engine.get_physics_frames() % 30 == 0:
				print("[StairLock] RIGHT 解鎖 (caught=%s next=%s)" % [left_caught_up, _stair_expected_support_foot])


## ★★★ PredictIK - Swing 開始時預測落腳點 ★★★
## 由步態事件觸發，而不是單純靠距離重算。
## 1. Swing 開始時鎖定一條完整步態預測
## 2. 用模擬軌跡估算落腳水平位移
## 3. Down ray + path samples + sphere cast 求出自然 swing apex
## 4. 後續用時間驅動曲線，而不是用腳骨沿前向投影推進度
func _get_prediction_heading(h_vel: Vector3) -> Vector3:
	var heading = Vector3.ZERO
	if _prediction_input_dir.length_squared() > 0.01:
		heading = _prediction_input_dir
		heading.y = 0.0
	if heading.length_squared() < 0.0001 and h_vel.length_squared() > 0.0001:
		heading = h_vel
		heading.y = 0.0
	if heading.length_squared() < 0.0001 and _char_body:
		heading = -_char_body.global_transform.basis.z
		heading.y = 0.0
	if heading.length_squared() < 0.0001:
		return Vector3.FORWARD
	return heading.normalized()


func _estimate_swing_duration(h_speed: float) -> float:
	var stride_scale = 1.0
	if enable_stride_warping and _stride_anim_speed > 0.1 and h_speed > 0.01:
		stride_scale = clampf(h_speed / _stride_anim_speed, stride_warp_min, stride_warp_max)
	var effective_stride = prediction_stride_length / maxf(stride_scale, 0.1)
	var duration = effective_stride / maxf(h_speed, min_prediction_speed)
	return clampf(duration, MIN_SWING_DURATION, MAX_SWING_DURATION)


func _get_swing_progress(is_left: bool) -> float:
	var elapsed = _left_swing_elapsed
	var duration = _left_swing_duration
	var phase = _left_foot_phase
	if not is_left:
		elapsed = _right_swing_elapsed
		duration = _right_swing_duration
		phase = _right_foot_phase
	var time_t = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	if phase >= plant_enter_phase_threshold:
		return 1.0
	var phase_t = 1.0 - clampf((phase - swing_enter_phase_threshold) / maxf(plant_enter_phase_threshold - swing_enter_phase_threshold, 0.001), 0.0, 1.0)
	return clampf(lerpf(time_t, phase_t, 0.35), 0.0, 1.0)


func _should_replan_prediction(is_left: bool, move_dir: Vector3) -> bool:
	if move_dir.length_squared() < 0.0001:
		return false
	var pred_forward = _left_pred_forward
	var elapsed = _left_swing_elapsed
	var duration = _left_swing_duration
	if not is_left:
		pred_forward = _right_pred_forward
		elapsed = _right_swing_elapsed
		duration = _right_swing_duration
	if pred_forward.length_squared() < 0.0001:
		return false
	if elapsed > duration * 0.45:
		return false
	return pred_forward.dot(move_dir) < cos(deg_to_rad(predictive_replan_turn_degrees))


func _predict_step_landing(foot_idx: int, space: PhysicsDirectSpaceState3D, exclude: Array) -> void:
	var bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(foot_idx)
	var foot_pos = bone_global.origin
	var is_left = (foot_idx == _left_foot_idx)
	var h_vel := Vector3.ZERO
	if _char_body:
		h_vel = Vector3(_char_body.velocity.x, 0, _char_body.velocity.z)
	var h_speed = h_vel.length()
	
	var forward_dir = _get_prediction_heading(h_vel)
	var swing_duration = _left_swing_duration
	if not is_left:
		swing_duration = _right_swing_duration
	if swing_duration <= 0.001:
		swing_duration = _estimate_swing_duration(h_speed)

	var predicted_offset = _simulate_trajectory_offset(h_vel, swing_duration)
	predicted_offset.y = 0.0
	if predicted_offset.length() > max_prediction_offset:
		predicted_offset = predicted_offset.normalized() * max_prediction_offset
	if predicted_offset.length() < 0.05:
		predicted_offset = forward_dir * prediction_stride_length
	else:
		forward_dir = predicted_offset.normalized()
	
	# === Step 1: 起點 — 從腳向下 raycast ===
	_cached_ray_query.from = foot_pos + Vector3.UP * 0.15
	_cached_ray_query.to = foot_pos + Vector3.DOWN * 0.5
	_cached_ray_query.exclude = exclude
	var start_hit = space.intersect_ray(_cached_ray_query)
	
	var start_pos: Vector3
	if not start_hit.is_empty():
		start_pos = start_hit.position
	else:
		start_pos = foot_pos
		start_pos.y = _char_body.global_position.y if _char_body else foot_pos.y
	
	# === Step 2: 終點 — 用預測軌跡的水平位移來找落腳點 ===
	var lookahead_pos = start_pos + predicted_offset + Vector3.UP * (max_step_up + predictive_step_clearance + 0.1)
	_cached_ray_query.from = lookahead_pos
	_cached_ray_query.to = lookahead_pos + Vector3.DOWN * (max_step_up * 4.0)
	var end_hit = space.intersect_ray(_cached_ray_query)
	
	var end_pos: Vector3
	if not end_hit.is_empty():
		end_pos = end_hit.position
	else:
		end_pos = start_pos + predicted_offset
		end_pos.y = start_pos.y
	
	# === Step 2b: 樓梯踏面偵測 — 多段前向 raycast 找第一個台階 ===
	# 每 STAIR_PROBE_STEP 掃描前方，偵測高度突變（riser）→ snap 到踏面
	const STAIR_PROBE_STEP := 0.08   # 每 8cm 一個探測點
	const STAIR_MIN_RISER := 0.05    # 最小台階高度差
	const STAIR_MAX_PROBES := 16     # 最多探測次數（增加以覆蓋更遠距離）
	# ★ 探測範圍 = max(步幅 * 1.5, 1.0m)，確保平地接近樓梯時能偵測到第一階
	var probe_range = maxf(predicted_offset.length() * 1.5, 1.0)
	var probe_count = mini(int(probe_range / STAIR_PROBE_STEP), STAIR_MAX_PROBES)
	var prev_probe_y := start_pos.y
	
	for i in range(probe_count):
		var probe_dist = STAIR_PROBE_STEP * (i + 2)  # 從 0.16m 開始（跳過腳下）
		var probe_origin = start_pos + forward_dir * probe_dist + Vector3.UP * (max_step_up + 0.15)
		_cached_ray_query.from = probe_origin
		_cached_ray_query.to = probe_origin + Vector3.DOWN * (max_step_up * 3.0)
		_cached_ray_query.exclude = exclude
		var probe_hit = space.intersect_ray(_cached_ray_query)
		if probe_hit.is_empty():
			continue
		var probe_y = probe_hit.position.y
		var dy = probe_y - prev_probe_y
		var is_flat_tread = probe_hit.normal.dot(Vector3.UP) > 0.85
		
		# 偵測到上台階 riser（地面突然升高）
		if dy > STAIR_MIN_RISER and is_flat_tread:
			end_pos = probe_hit.position
			end_pos += forward_dir * 0.05  # 偏移到踏面中央，避免踩邊緣
			if Engine.get_physics_frames() % 30 == 0:
				print("[PredIK-Stair] ↑ 偵測到上台階: dy=%.3f pos=(%.2f, %.2f, %.2f)" % [
					dy, end_pos.x, end_pos.y, end_pos.z
				])
			break
		
		# 偵測到下台階 riser（地面突然下降）
		if dy < -STAIR_MIN_RISER and is_flat_tread:
			end_pos = probe_hit.position
			end_pos += forward_dir * 0.05
			if Engine.get_physics_frames() % 30 == 0:
				print("[PredIK-Stair] ↓ 偵測到下台階: dy=%.3f pos=(%.2f, %.2f, %.2f)" % [
					dy, end_pos.x, end_pos.y, end_pos.z
				])
			break
		
		prev_probe_y = probe_y
	
	# === Step 3: 障礙物偵測 — SphereCast 起點→終點 ===
	var has_obstacle := false
	var obstacle_pos := Vector3.ZERO
	
	var move_vec = (end_pos - start_pos)
	var move_dir = forward_dir
	if move_vec.length_squared() > 0.0001:
		move_dir = move_vec.normalized()
	var move_right = Vector3.UP.cross(move_dir).normalized()
	var move_up = move_dir.cross(move_right).normalized()
	
	if not _predict_sphere_shape:
		_predict_sphere_shape = SphereShape3D.new()
		_predict_sphere_shape.radius = 0.06
	
	var shape_query = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _predict_sphere_shape
	shape_query.collision_mask = _cached_ray_query.collision_mask
	shape_query.exclude = exclude
	
	# 從起點上方掃向終點上方，向下偵測障礙物
	var cast_start = start_pos + move_up * max_step_up + move_dir * 0.1
	var cast_end = end_pos + move_up * max_step_up - move_dir * 0.1
	var cast_motion = cast_end - cast_start
	
	shape_query.transform = Transform3D(Basis(), cast_start)
	shape_query.motion = cast_motion
	
	var cast_results = space.cast_motion(shape_query)
	if cast_results[0] < 1.0:
		var hit_point = cast_start + cast_motion * cast_results[0]
		_cached_ray_query.from = hit_point
		_cached_ray_query.to = hit_point + Vector3.DOWN * (max_step_up + 0.3)
		_cached_ray_query.exclude = exclude
		var obs_hit = space.intersect_ray(_cached_ray_query)
		if not obs_hit.is_empty():
			has_obstacle = true
			obstacle_pos = obs_hit.position

	# === Step 3b: 追加路徑取樣 — 補強複雜台階邊緣 ===
	var highest_path_y = -INF
	var highest_path_t = 0.5
	var sample_height = max_step_up + predictive_step_clearance + 0.2
	for i in range(PREDICT_PATH_SAMPLE_COUNT):
		var t = float(i + 1) / float(PREDICT_PATH_SAMPLE_COUNT + 1)
		var sample_origin = start_pos.lerp(end_pos, t) + Vector3.UP * sample_height
		_cached_ray_query.from = sample_origin
		_cached_ray_query.to = sample_origin + Vector3.DOWN * (sample_height + max_step_up + 0.5)
		_cached_ray_query.exclude = exclude
		var sample_hit = space.intersect_ray(_cached_ray_query)
		if not sample_hit.is_empty() and sample_hit.position.y > highest_path_y:
			highest_path_y = sample_hit.position.y
			highest_path_t = t

	var heel_probe = end_pos - forward_dir * absf(heel_offset.z)
	var toe_probe = end_pos + forward_dir * absf(toe_offset.z)
	var heel_probe_start = heel_probe + Vector3.UP * sample_height
	_cached_ray_query.from = heel_probe_start
	_cached_ray_query.to = heel_probe_start + Vector3.DOWN * (sample_height + max_step_up + 0.5)
	_cached_ray_query.exclude = exclude
	var heel_probe_hit = space.intersect_ray(_cached_ray_query)
	if not heel_probe_hit.is_empty() and heel_probe_hit.position.y > highest_path_y:
		highest_path_y = heel_probe_hit.position.y
		highest_path_t = 0.8

	var toe_probe_start = toe_probe + Vector3.UP * sample_height
	_cached_ray_query.from = toe_probe_start
	_cached_ray_query.to = toe_probe_start + Vector3.DOWN * (sample_height + max_step_up + 0.5)
	_cached_ray_query.exclude = exclude
	var toe_probe_hit = space.intersect_ray(_cached_ray_query)
	if not toe_probe_hit.is_empty() and toe_probe_hit.position.y > highest_path_y:
		highest_path_y = toe_probe_hit.position.y
		highest_path_t = 0.85
	
	# === Step 4: 記錄自然 swing arc ===
	var apex_y = maxf(start_pos.y, end_pos.y) + predictive_step_clearance
	var apex_t = 0.5
	var path_len = maxf(start_pos.distance_to(end_pos), 0.001)
	if has_obstacle:
		var obstacle_t = clampf(start_pos.distance_to(obstacle_pos) / path_len, 0.1, 0.9)
		var obstacle_apex = obstacle_pos.y + predictive_step_clearance * 0.5
		if obstacle_apex > apex_y:
			apex_y = obstacle_apex
			apex_t = obstacle_t
	if highest_path_y > -INF:
		var sampled_apex = highest_path_y + predictive_step_clearance * 0.35
		if sampled_apex > apex_y:
			apex_y = sampled_apex
			apex_t = highest_path_t
	apex_t = clampf(apex_t, 0.15, 0.85)

	if is_left:
		_left_pred_start_pos = start_pos
		_left_pred_end_y = end_pos.y
		_left_pred_end_pos = end_pos
		_left_pred_forward = forward_dir
		_left_pred_mid_y = apex_y
		_left_pred_mid_t = apex_t
		_left_pred_active = true
	else:
		_right_pred_start_pos = start_pos
		_right_pred_end_y = end_pos.y
		_right_pred_end_pos = end_pos
		_right_pred_forward = forward_dir
		_right_pred_mid_y = apex_y
		_right_pred_mid_t = apex_t
		_right_pred_active = true


## ★ 3 點高度曲線求值 ★
## t: 0.0 = 起點, 1.0 = 終點
## 返回高度 Y
func _eval_predict_curve(start_y: float, mid_y: float, end_y: float, mid_t: float, t: float) -> float:
	var clamped_t = clampf(t, 0.0, 1.0)
	var peak_y = maxf(mid_y, maxf(start_y, end_y))
	if clamped_t <= mid_t:
		var seg_t = clampf(clamped_t / maxf(mid_t, 0.001), 0.0, 1.0)
		seg_t = seg_t * seg_t * (3.0 - 2.0 * seg_t)
		return lerpf(start_y, peak_y, seg_t)
	var seg_t = clampf((clamped_t - mid_t) / maxf(1.0 - mid_t, 0.001), 0.0, 1.0)
	seg_t = seg_t * seg_t * (3.0 - 2.0 * seg_t)
	return lerpf(peak_y, end_y, seg_t)


## ★ 停用預測時：清除狀態 + 重設彈簧到骨骼位置（避免腳飛回來）
func _deactivate_predictions() -> void:
	var was_active = _left_pred_active or _right_pred_active
	
	_left_pred_active = false
	_right_pred_active = false
	_left_was_swing = false
	_right_was_swing = false
	_left_swing_elapsed = 0.0
	_right_swing_elapsed = 0.0
	
	# ★ 關鍵：如果之前預測是啟用的，彈簧和 IK target 還停留在預測位置
	# 必須立即 snap 回骨骼當前位置，否則會出現「腳從後面飛過來」
	if was_active and skeleton and _spring_initialized:
		if _left_foot_idx >= 0:
			var l_bone = (skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)).origin
			_left_spring_pos = l_bone
			_left_spring_vel = Vector3.ZERO
			if left_target:
				left_target.global_position = l_bone
		if _right_foot_idx >= 0:
			var r_bone = (skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)).origin
			_right_spring_pos = r_bone
			_right_spring_vel = Vector3.ZERO
			if right_target:
				right_target.global_position = r_bone


## ★ 更新 Predictive IK 狀態（每物理幀呼叫）
## 注意：即使樓梯動畫中也持續計算預測（用於 debug 可視化驗證）
## IK 效果由 _update_ik_target 中的 temporary_disable_predict_ik 控制
func _update_predict_ik(delta: float, space: PhysicsDirectSpaceState3D, exclude: Array) -> void:
	if _is_stair_ascending_active():
		_deactivate_predictions()
		return
	if not enable_predictive_ik or not _char_body or stop_anim_active:
		if debug_draw and Engine.get_physics_frames() % 30 == 0:
			print("[PredIK] OFF enable=%s char=%s stop=%s" % [enable_predictive_ik, _char_body != null, stop_anim_active])
		_deactivate_predictions()
		return
	if not skeleton or _left_foot_idx < 0 or _right_foot_idx < 0:
		if debug_draw and Engine.get_physics_frames() % 30 == 0:
			print("[PredIK] WAIT skeleton=%s left=%d right=%d" % [skeleton != null, _left_foot_idx, _right_foot_idx])
		return
	var h_vel = Vector3(_char_body.velocity.x, 0, _char_body.velocity.z)
	var h_speed = h_vel.length()
	if h_speed < min_prediction_speed and _prediction_input_dir.length_squared() < 0.01 and not stair_ik_active:
		if debug_draw and Engine.get_physics_frames() % 30 == 0:
			print("[PredIK] IDLE speed=%.2f input=%.2f" % [h_speed, _prediction_input_dir.length()])
		_deactivate_predictions()
		return
	
	var move_dir = _get_prediction_heading(h_vel)

	# ★★★ 樓梯模式：繞過相位偵測，定期強制更新預測 ★★★
	# 樓梯上行走時 swing/stance 偵測可能不可靠
	# 改為每 10 物理幀強制重新預測兩腳
	if stair_ik_active:
		var should_update = (Engine.get_physics_frames() % 10 == 0)
		if should_update:
			if _left_foot_idx >= 0:
				_predict_step_landing(_left_foot_idx, space, exclude)
			if _right_foot_idx >= 0:
				_predict_step_landing(_right_foot_idx, space, exclude)
		if debug_draw and Engine.get_physics_frames() % 30 == 0:
			print("[PredIK-Stair] active=%s L=%s R=%s speed=%.2f" % [stair_ik_active, _left_pred_active, _right_pred_active, h_speed])
		# 保持 pred_active，不更新 virtual_y（樓梯 IK 直接用 pred_end_y）
		return

	var left_swing_threshold = swing_enter_phase_threshold
	if _left_was_swing:
		left_swing_threshold = plant_enter_phase_threshold
	var left_is_swing = _left_foot_phase < left_swing_threshold
	if left_is_swing and not _left_was_swing:
		_left_swing_elapsed = 0.0
		_left_swing_duration = _estimate_swing_duration(h_speed)
		_predict_step_landing(_left_foot_idx, space, exclude)
	elif left_is_swing:
		_left_swing_elapsed += delta
		if _should_replan_prediction(true, move_dir):
			_left_swing_duration = _estimate_swing_duration(h_speed)
			_predict_step_landing(_left_foot_idx, space, exclude)
	elif _left_pred_active:
		_left_swing_elapsed = _left_swing_duration
	_left_was_swing = left_is_swing

	var right_swing_threshold = swing_enter_phase_threshold
	if _right_was_swing:
		right_swing_threshold = plant_enter_phase_threshold
	var right_is_swing = _right_foot_phase < right_swing_threshold
	if right_is_swing and not _right_was_swing:
		_right_swing_elapsed = 0.0
		_right_swing_duration = _estimate_swing_duration(h_speed)
		_predict_step_landing(_right_foot_idx, space, exclude)
	elif right_is_swing:
		_right_swing_elapsed += delta
		if _should_replan_prediction(false, move_dir):
			_right_swing_duration = _estimate_swing_duration(h_speed)
			_predict_step_landing(_right_foot_idx, space, exclude)
	elif _right_pred_active:
		_right_swing_elapsed = _right_swing_duration
	_right_was_swing = right_is_swing
	
	if _left_pred_active:
		var progress_l = _get_swing_progress(true)
		_left_pred_virtual_y = _eval_predict_curve(_left_pred_start_pos.y, _left_pred_mid_y, _left_pred_end_y, _left_pred_mid_t, progress_l)
	else:
		_left_pred_virtual_y = _left_ground_y
	
	if _right_pred_active:
		var progress_r = _get_swing_progress(false)
		_right_pred_virtual_y = _eval_predict_curve(_right_pred_start_pos.y, _right_pred_mid_y, _right_pred_end_y, _right_pred_mid_t, progress_r)
	else:
		_right_pred_virtual_y = _right_ground_y
	
	# ★ DEBUG
	if Engine.get_physics_frames() % 30 == 0:
		print("[PredIK] L_pred=%s L_vY=%.3f R_pred=%s R_vY=%.3f | speed=%.2f" % [
			_left_pred_active, _left_pred_virtual_y,
			_right_pred_active, _right_pred_virtual_y,
			h_speed
		])


## ★ 更新 IK 目標位置（Spring-Damper + 防懸空牽引）
func _update_ik_target(target: Marker3D, foot_idx: int, hip_idx: int, ground_res: GroundResult, delta: float) -> void:
	var bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(foot_idx)
	var foot_pos = bone_global.origin
	if _char_body:
		var stair_sys = _char_body.get("_stair_system")
		if stair_sys and stair_sys.data.support_lock_active:
			var is_left_target = (foot_idx == _left_foot_idx)
			if stair_sys.data.support_lock_is_left == is_left_target:
				target.global_position = stair_sys.data.support_lock_world_pos
				return
	
	var is_left_side = (foot_idx == _left_foot_idx)
	var pred_active = _left_pred_active if is_left_side else _right_pred_active
	var pred_virtual_y = _left_pred_virtual_y if is_left_side else _right_pred_virtual_y
	var is_stair_locked = stair_ik_active and ((is_left_side and left_foot_locked) or (not is_left_side and right_foot_locked))
	if is_stair_locked:
		var hard_lock_pos = _left_locked_ground if is_left_side else _right_locked_ground
		target.global_position = hard_lock_pos
		return
	
	# ★★★ 樓梯 PredictIK：直接用預測落點高度覆蓋 IK 目標 Y ★★★
	# 樓梯上行走時，swing 腳朝預測踏面移動，support 腳由 hard lock 分支固定。
	if stair_ik_active and pred_active and enable_predictive_ik:
		var pred_end_y = _left_pred_end_y if is_left_side else _right_pred_end_y
		var pred_end_pos = _left_pred_end_pos if is_left_side else _right_pred_end_pos
		var foot_phase = _left_foot_phase if is_left_side else _right_foot_phase
		var expected_support = _stair_expected_support_foot
		var expected_is_this_foot = (expected_support == "left" and is_left_side) or (expected_support == "right" and not is_left_side)
		var is_stance = foot_phase > 0.7
		
		# 還沒正式 commit 之前，預期支撐腳不能沿階面前滑。
		# 只允許極小的 XZ 漂移，主要用來穩定接觸點；真正的前進只交給 swing 腳。
		if expected_is_this_foot and is_stance:
			var stance_goal = target.global_position
			stance_goal.y = maxf(ground_res.y, pred_end_y) + foot_height_offset
			var xz_drift = pred_end_pos - target.global_position
			xz_drift.y = 0.0
			if xz_drift.length() > STAIR_STANCE_XZ_DRIFT_EPSILON:
				xz_drift = xz_drift.normalized() * STAIR_STANCE_XZ_DRIFT_EPSILON
			stance_goal.x += xz_drift.x
			stance_goal.z += xz_drift.z
			target.global_position = target.global_position.lerp(stance_goal, delta * smooth_speed * 1.5)
			return
		
		# ★ Swing 腳：跟隨動畫的抬腳弧線，Y 軸逐步逼近預測踏面
		var swing_blend = clampf(1.0 - foot_phase, 0.15, 1.0)
		
		# IK 目標 = 從動畫骨骼逐步逼近預測踏面，避免只改 Y 造成懸空。
		var stair_goal_y = maxf(ground_res.y, pred_end_y) + foot_height_offset
		var stair_goal_x = lerpf(foot_pos.x, pred_end_pos.x, swing_blend)
		var stair_goal_z = lerpf(foot_pos.z, pred_end_pos.z, swing_blend)
		var stair_goal = Vector3(stair_goal_x, stair_goal_y, stair_goal_z)
		
		# 安全檢查：不讓腳離髖關節太遠
		if hip_idx >= 0:
			var hip_global = skeleton.global_transform * skeleton.get_bone_global_pose(hip_idx)
			var hip_pos = hip_global.origin
			var d = stair_goal.distance_to(hip_pos)
			if d > max_reach_distance:
				stair_goal = stair_goal.lerp(foot_pos, (d - max_reach_distance) / 0.3)
		
		# 用 lerp 平滑：讓動畫的抬腳動作仍有一定效果
		target.global_position = target.global_position.lerp(stair_goal, delta * smooth_speed * 2.0)
		
		if Engine.get_physics_frames() % 120 == 0:
			var side = "L" if is_left_side else "R"
			print("[StairIK-%s] pred=(%.2f,%.2f,%.2f) swing=%.2f bone=(%.2f,%.2f) tgt=(%.2f,%.2f)" % [
				side, pred_end_pos.x, pred_end_y, pred_end_pos.z, swing_blend,
				foot_pos.x, foot_pos.z, target.global_position.x, target.global_position.z
			])
		return
	
	# ★★★ PredictIK 模式（一般地形）：完全使用 PredictIK.cs 架構 ★★★
	# 繞過 Phase-Driven blend，直接用 bone.y + (virtualFoot - virtualHeight)
	if pred_active and enable_predictive_ik and not temporary_disable_predict_ik and not stop_anim_active:
		var virtual_height = minf(_left_pred_virtual_y, _right_pred_virtual_y)
		var foot_offset = pred_virtual_y - virtual_height
		# IK 目標 = 動畫腳位置 + 高度偏移
		var pred_goal_pos = Vector3(foot_pos.x, foot_pos.y + foot_offset, foot_pos.z)
		
		# DEBUG
		if Engine.get_physics_frames() % 15 == 0:
			var side = "L" if is_left_side else "R"
			print("[PredIK-%s] vY=%.3f vH=%.3f offset=%.3f boneY=%.3f goalY=%.3f" % [
				side, pred_virtual_y, virtual_height, foot_offset, foot_pos.y, pred_goal_pos.y
			])
		
		# 平滑 IK 目標
		target.global_position = target.global_position.lerp(pred_goal_pos, delta * smooth_speed)
		return
	
	# === 一般模式（非 PredictIK）===
	var target_y = ground_res.y + foot_height_offset + 0.01
	
	# 高度差檢查
	var height_diff = target_y - foot_pos.y
	if height_diff < -max_step_down or height_diff > max_step_up:
		if Engine.get_physics_frames() % 60 == 0:
			print("[IK-DIAG] %s REJECTED height_diff=%.3f" % [
				"L" if is_left_side else "R", height_diff
			])
		target.global_position = target.global_position.lerp(foot_pos, delta * smooth_speed)
		return
	
	# === 邊緣防懸空邏輯 (Edge Anti-Hover) ===
	var target_xz = Vector2(foot_pos.x, foot_pos.z)
	var hit_xz = Vector2(ground_res.pos.x, ground_res.pos.z)
	var xz_dist = target_xz.distance_to(hit_xz)
	if xz_dist > 0.05:
		target_xz = target_xz.lerp(hit_xz, 0.5)
	
	# 目標位置（地面 + 偏移）
	var goal_pos = Vector3(target_xz.x, target_y, target_xz.y)
	
	# ★★★ Phase-Driven 目標混合（一般行走用）★★★
	var foot_phase_blend = _left_foot_phase if is_left_side else _right_foot_phase
	var char_is_moving_blend = _char_body and Vector2(_char_body.velocity.x, _char_body.velocity.z).length() > standing_threshold
	var is_hard_locked = (is_left_side and left_foot_locked) or ((not is_left_side) and right_foot_locked)
	if is_hard_locked:
		var locked_pos = _left_locked_ground if is_left_side else _right_locked_ground
		if is_left_side:
			_left_spring_pos = locked_pos
			_left_spring_vel = Vector3.ZERO
		else:
			_right_spring_pos = locked_pos
			_right_spring_vel = Vector3.ZERO
		target.global_position = locked_pos
		return
	
	if char_is_moving_blend:
		var sharp_phase = pow(foot_phase_blend, 0.3)
		var anim_y = _left_anim_foot_y if is_left_side else _right_anim_foot_y
		var anim_goal = Vector3(foot_pos.x, anim_y, foot_pos.z)
		goal_pos = anim_goal.lerp(goal_pos, sharp_phase)
	
	# ★ Feature #1：Stride Warping — 消除滑步
	if enable_stride_warping and _char_body and _stride_anim_speed > 0.1:
		var actual_speed = Vector2(_char_body.velocity.x, _char_body.velocity.z).length()
		if actual_speed > 0.5:  # 只在移動時
			var stride_scale = clampf(actual_speed / _stride_anim_speed, stride_warp_min, stride_warp_max)
			# 沿移動方向偏移 goal_pos
			var move_dir = Vector3(_char_body.velocity.x, 0, _char_body.velocity.z).normalized()
			var foot_to_goal = goal_pos - foot_pos
			var along_movement = foot_to_goal.dot(move_dir)
			# 只調整沿移動方向的分量（拉伸/壓縮步幅）
			goal_pos += move_dir * along_movement * (stride_scale - 1.0)
	
	var foot_phase_ik = _left_foot_phase if (foot_idx == _left_foot_idx) else _right_foot_phase
	
	# 距離限制：防止腳延伸超過腿的長度
	if hip_idx >= 0:
		var hip_global = skeleton.global_transform * skeleton.get_bone_global_pose(hip_idx)
		var hip_pos = hip_global.origin
		var dist = goal_pos.distance_to(hip_pos)
		
		# ★ 防呆機制：如果腿被拉得太長，強制解除 Stance Lock，讓 IK 彈回動畫位置
		if dist > max_reach_distance:
			if (foot_idx == _left_foot_idx):
				_left_stance_locked = false
			else:
				_right_stance_locked = false
			
			foot_phase_ik = 0.0  # 強制進入 Swing，防止等一下又被意外鎖定回去
			goal_pos = goal_pos.lerp(foot_pos, (dist - max_reach_distance) / 0.3)
	
	# ★★★ Phase-Driven Spring-Damper（Phase C 增強）★★★
	# Swing→Stance 過渡時加硬彈簧，讓腳快速到位
	var new_pos: Vector3
	var is_left_ik = (foot_idx == _left_foot_idx)
	
	if enable_predictive_ik:
		if not _spring_initialized:
			# 首次初始化彈簧到動畫位置
			_left_spring_pos = foot_pos
			_right_spring_pos = foot_pos
			_spring_initialized = true
		
		# ★ Phase-Driven 彈簧硬度：
		# Swing→Stance (落地中): 加硬 2x → 快速收斂到地面
		# Full Stance (已著地): 正常硬度 → 平滑跟隨
		# Full Swing (空中):    正常硬度 → 自然擺動
		var orig_freq = spring_frequency
		var is_landing = foot_phase_ik > 0.4 and foot_phase_ik < STANCE_LOCK_THRESHOLD
		if is_landing:
			spring_frequency = orig_freq * 2.0  # 暫時加硬
		
		# ★★★ 膠囊體移動系統專用 Stance Lock ★★★
		# 關鍵洞見：膠囊體移動 ≠ Root Motion！
		# 膠囊體系統中，整個 Skeleton 會跟著膠囊體一起平移。
		# 如果 Stance Lock 釘死世界 XZ，身體往前走，腳卻被固定在後方 → 無限拉長。
		# 正確做法：移動中只鎖定 Y（地面高度），XZ 交給動畫控制。
		#           站立時才鎖定完整的 XYZ（防微滑）。
		var char_is_moving = stop_anim_active or (_char_body and Vector2(_char_body.velocity.x, _char_body.velocity.z).length() > standing_threshold)
		
		if is_left_ik:
			if _left_stance_locked:
				if char_is_moving:
					pass  # goal_pos 保持地面偵測的最新值
				else:
					# ★ 站立中：XZ 鎖定防微滑，Y 用新鮮地面偵測值
					# 防止 pelvis 調整後 locked_y 過時導致腳浮空
					goal_pos.x = _left_locked_ground.x
					goal_pos.z = _left_locked_ground.z
					# goal_pos.y 保留地面偵測 + offset 的新鮮值

			# ★ Stance 時跳過彈簧 → 直達地面（消除 spring lag）
			if _left_stance_locked:
				_left_spring_pos = goal_pos
				_left_spring_vel = Vector3.ZERO
				new_pos = goal_pos
			else:
				new_pos = _apply_spring_damper_step(true, goal_pos, delta)
			
			# ★ 更新 Stance Lock 狀態
			if foot_phase_ik > STANCE_LOCK_THRESHOLD and not _left_stance_locked:
				_left_stance_locked = true
				_left_locked_ground = goal_pos
				_left_locked_normal = _left_ground_normal
				_left_spring_vel = Vector3.ZERO
				_left_spring_pos = goal_pos
				new_pos = goal_pos
				_prev_left_target = goal_pos
				_curr_left_target = goal_pos
			elif foot_phase_ik < SWING_UNLOCK_THRESHOLD:
				_left_stance_locked = false
		else:
			if _right_stance_locked:
				if char_is_moving:
					pass
				else:
					# ★ 同左腳：XZ 鎖定，Y 用新鮮值
					goal_pos.x = _right_locked_ground.x
					goal_pos.z = _right_locked_ground.z

			# ★ Stance 時跳過彈簧 → 直達地面
			if _right_stance_locked:
				_right_spring_pos = goal_pos
				_right_spring_vel = Vector3.ZERO
				new_pos = goal_pos
			else:
				new_pos = _apply_spring_damper_step(false, goal_pos, delta)
			
			# ★ 更新 Stance Lock 狀態
			if foot_phase_ik > STANCE_LOCK_THRESHOLD and not _right_stance_locked:
				_right_stance_locked = true
				_right_locked_ground = goal_pos
				_right_locked_normal = _right_ground_normal
				_right_spring_vel = Vector3.ZERO
				_right_spring_pos = goal_pos
				new_pos = goal_pos
				_prev_right_target = goal_pos
				_curr_right_target = goal_pos
			elif foot_phase_ik < SWING_UNLOCK_THRESHOLD:
				_right_stance_locked = false
		
		# 恢復原始頻率
		spring_frequency = orig_freq
	else:
		# 不用 predictive IK → 舊的 lerp 邏輯
		new_pos = target.global_position.lerp(goal_pos, delta * smooth_speed)
	
	# ★ 儲存 temporal interpolation 狀態（供 _process 使用）
	if is_left_ik:
		_prev_left_target = _curr_left_target
		_curr_left_target = new_pos
	else:
		_prev_right_target = _curr_right_target
		_curr_right_target = new_pos
	
	# ★ 直接寫入 target.global_position（_process 已不再覆蓋）
	# TwoBoneIK 讀取的就是這個位置 → 確保精確貼地
	target.global_position = new_pos


## ★ 直接骨骼旋轉：讓腳踝對齊地面法線（不需 LookAt Modifier）
var _left_foot_rot: Quaternion = Quaternion.IDENTITY
var _right_foot_rot: Quaternion = Quaternion.IDENTITY

func _apply_foot_rotation(delta: float) -> void:
	# 對每隻腳，根據地面法線計算旋轉
	if _left_foot_idx >= 0:
		_rotate_foot_bone(_left_foot_idx, _left_ground_normal, true, delta)
	if _right_foot_idx >= 0:
		_rotate_foot_bone(_right_foot_idx, _right_ground_normal, false, delta)

func _rotate_foot_bone(foot_idx: int, ground_normal: Vector3, is_left: bool, delta: float) -> void:
	if ground_normal.is_zero_approx():
		return
	
	# ★ 斜坡因子：平地不旋轉，斜坡才旋轉
	var slope_dot = ground_normal.dot(Vector3.UP)
	var slope_factor = clampf((0.98 - slope_dot) / 0.03, 0.0, 1.0)
	if slope_factor < 0.01:
		# 平地 → 清除旋轉覆蓋，用動畫原生旋轉
		if is_left:
			_left_foot_rot = _left_foot_rot.slerp(Quaternion.IDENTITY, delta * foot_rotation_speed)
		else:
			_right_foot_rot = _right_foot_rot.slerp(Quaternion.IDENTITY, delta * foot_rotation_speed)
		return
	
	# 計算需要的旋轉：從 UP 到 ground_normal
	var axis = Vector3.UP.cross(ground_normal)
	if axis.length_squared() < 0.0001:
		return
	axis = axis.normalized()
	var angle = acos(clampf(slope_dot, -1.0, 1.0))
	angle = clampf(angle, 0.0, deg_to_rad(max_pitch_angle))
	
	var target_rot = Quaternion(axis, angle * slope_factor)
	
	# 平滑插值
	if is_left:
		_left_foot_rot = _left_foot_rot.slerp(target_rot, delta * foot_rotation_speed)
		# 將旋轉疊加到當前骨骼旋轉上
		var current = skeleton.get_bone_pose_rotation(foot_idx)
		skeleton.set_bone_pose_rotation(foot_idx, _left_foot_rot * current)
	else:
		_right_foot_rot = _right_foot_rot.slerp(target_rot, delta * foot_rotation_speed)
		var current = skeleton.get_bone_pose_rotation(foot_idx)
		skeleton.set_bone_pose_rotation(foot_idx, _right_foot_rot * current)

## ★★★ GASP-Style 模擬軌跡預測 ★★★
## 取代線性預測 (vel * time)，模擬未來 N 步的加速/減速/轉向
## 
## 原理（對應 UE5 GASP 的 Trajectory Component）：
##   1. 讀取玩家目前的輸入方向（決定「目標速度」）
##   2. 用 move_toward 模擬加速/減速（與 SimpleCapsuleMove 相同的物理模型）
##   3. 累積每一步的位移差，得到預測偏移
##
## 效果差異（vs 線性預測）：
##   停止時：軌跡會減速到零（線性的會繼續直線衝出去）
##   轉彎時：軌跡會彎曲（線性的指向舊方向）
##   加速時：軌跡會短些（線性的假設已達全速）
##
## 參考 MovementData：ground_accel=12, ground_decel=15, walk=3.5, sprint=6.0

## 外部可設定（由 SimpleCapsuleMove 在每幀寫入）
var _prediction_input_dir: Vector3 = Vector3.ZERO    # 玩家搖桿方向（世界空間）
var _prediction_max_speed: float = 3.5               # 當前目標速度（walk/sprint）
var _prediction_accel: float = 12.0                  # 加速率
var _prediction_decel: float = 15.0                  # 減速率

const TRAJECTORY_SAMPLES: int = 6  # 軌跡采樣點數量

func _simulate_trajectory_offset(current_vel: Vector3, total_time: float) -> Vector3:
	if total_time <= 0.001:
		return Vector3.ZERO
	
	# 計算目標速度向量
	var target_vel: Vector3
	if _prediction_input_dir.length_squared() > 0.01:
		# 玩家有輸入 → 目標速度 = 輸入方向 × 最大速度
		target_vel = _prediction_input_dir.normalized() * _prediction_max_speed
	else:
		# 玩家無輸入 → 目標速度 = 0（減速停止）
		target_vel = Vector3.ZERO
	
	# 向前模擬 N 步
	var sim_vel = current_vel
	var total_offset = Vector3.ZERO
	var step_dt = total_time / float(TRAJECTORY_SAMPLES)
	
	for i in range(TRAJECTORY_SAMPLES):
		# 決定使用加速或減速率
		var approaching = sim_vel.dot(target_vel) > 0 and sim_vel.length() < target_vel.length()
		var rate = _prediction_accel if approaching else _prediction_decel
		
		# 模擬 move_toward（與 SimpleCapsuleMove._apply_horizontal_movement 相同模型）
		sim_vel.x = move_toward(sim_vel.x, target_vel.x, rate * step_dt)
		sim_vel.z = move_toward(sim_vel.z, target_vel.z, rate * step_dt)
		
		# 累積位移
		total_offset += sim_vel * step_dt
	
	return total_offset
## Critically-Damped Spring-Damper（臨界阻尼彈簧）
## 比 lerp 更自然：有慣性、不會突然跳動、收斂速度可控
## 參考：https://theorangeduck.com/page/spring-roll-call
func _apply_spring_damper_step(is_left: bool, target_val: Vector3, dt: float) -> Vector3:
	var current = _left_spring_pos if is_left else _right_spring_pos
	var velocity = _left_spring_vel if is_left else _right_spring_vel
	if dt <= 0.0001:
		return current
	
	var omega = spring_frequency * TAU  # 角頻率 = 2π * f
	
	# ★★★ 解析解：Closed-Form Critically Damped Spring ★★★
	# 取代顯式歐拉（Explicit Euler），後者在 omega*dt 接近穩定邊界時會指數爆炸到 NaN。
	# 此公式對任何 dt 和任何 spring_frequency 都保證收斂（無條件穩定）。
	# 來源：Daniel Holden "Spring-It-On" (GDC 2016)
	var exp_term = exp(-omega * dt)
	var j0 = current - target_val           # 位移誤差
	var j1 = velocity + j0 * omega          # 衍生項
	
	var new_pos = target_val + (j0 + j1 * dt) * exp_term
	var new_vel = (velocity - j1 * omega * dt) * exp_term
	if is_left:
		_left_spring_pos = new_pos
		_left_spring_vel = new_vel
	else:
		_right_spring_pos = new_pos
		_right_spring_vel = new_vel
	return new_pos


## ★★★ Temporal Interpolation：在渲染幀之間插值 IK Target ★★★
## 消除物理幀（固定 60Hz）和渲染幀（可變 FPS）之間的 1 幀延遲抖動
var _temporal_physics_frames: int = 0  # 已經過的物理幀數
var _safe_startup_delay: float = 0.0

func _process(_delta: float) -> void:
	if not skeleton or not left_target or not right_target:
		return
	
	# ★★★ 讀取動畫原始骨骼高度（核心！打斷 IK 反饋迴路）★★★
	# _process 在 Skeleton modifier (TwoBoneIK) 之前執行（場景樹順序）
	# 這裡的 get_bone_global_pose 回傳的是 AnimationTree 套用後的純動畫值
	# 不包含 TwoBoneIK 的修改 → 不受 IK 反饋影響
	if _left_foot_idx >= 0:
		_left_anim_foot_y = (skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)).origin.y
	if _right_foot_idx >= 0:
		_right_anim_foot_y = (skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)).origin.y
	
	# ★ 防當機策略：必須在 enable_predictive_ik 判斷之前！
	# 不然 enable_predictive_ik=false 時 IK 永遠不會被啟動！
	if _safe_startup_delay < 1.0:
		_safe_startup_delay += _delta
		if _safe_startup_delay >= 0.5 and _left_hip_idx >= 0:
			var l_hip = skeleton.global_transform * skeleton.get_bone_global_pose(_left_hip_idx)
			if left_target.global_position.distance_to(l_hip.origin) > 0.1:
				if left_ik and not left_ik.active: left_ik.active = true
				if right_ik and not right_ik.active: right_ik.active = true
				if left_lookat_modifier and not left_lookat_modifier.active: left_lookat_modifier.active = true
				# ★ 一次性 IK 狀態診斷
				if left_ik:
					var lt = left_ik.get("settings/0/target_node")
					var lt_ok = left_ik.get_node_or_null(lt) if lt else null
					print("[FootIK-DIAG] LeftIK: active=%s infl=%.2f target=%s resolved=%s" % [left_ik.active, left_ik.influence, lt, lt_ok != null])
				if right_ik:
					var rt = right_ik.get("settings/0/target_node")
					var rt_ok = right_ik.get_node_or_null(rt) if rt else null
					print("[FootIK-DIAG] RightIK: active=%s infl=%.2f target=%s resolved=%s" % [right_ik.active, right_ik.influence, rt, rt_ok != null])
				_safe_startup_delay = 10.0  # ★ 只印一次
				if right_lookat_modifier and not right_lookat_modifier.active: right_lookat_modifier.active = true
	
	if not enable_predictive_ik:
		return
	
	# 如果 IK 被外部禁用，不做插值
	if not ik_enabled:
		return
	
	# ★ 等待至少 2 個物理幀，確保 prev/curr 都有有效數據（4.7 physics interpolation 更穩）
	if _temporal_physics_frames < 2:
		return
	
	# ★ 安全檢查：prev/curr 不能是零向量
	if _prev_left_target.is_zero_approx() or _curr_left_target.is_zero_approx():
		return
	if _prev_right_target.is_zero_approx() or _curr_right_target.is_zero_approx():
		return
	
	# ★ Temporal interpolation 已移除
	# 問題：_process 插值後的位置比 physics 計算的 curr 滯後 1 幀  
	# → 斜坡上 TwoBoneIK 讀的是滯後位置 → 腳永遠到不了地面
	# 解決：_physics_process 直接寫入 target（唯一真實位置），_process 不覆蓋
	# 下面這行保留以防萬一，但實際由 _physics_process 決定 target 位置
	# left_target.global_position = _prev_left_target.lerp(_curr_left_target, frac)
	# right_target.global_position = _prev_right_target.lerp(_curr_right_target, frac)



## 將腳骨旋轉對齊地面法線（在 IK 之後覆寫）
func _align_foot_to_ground(foot_idx: int, ground_normal: Vector3, delta: float, is_left: bool, ankle_weight: float = 1.0) -> void:
	if foot_idx < 0 or not skeleton:
		return
	
	# 平地（法線接近 UP）→ 清除 override
	if ground_normal.dot(Vector3.UP) > 0.98:
		if is_left:
			_left_foot_pitch = lerp(_left_foot_pitch, 0.0, delta * foot_rotation_speed)
		else:
			_right_foot_pitch = lerp(_right_foot_pitch, 0.0, delta * foot_rotation_speed)
		skeleton.set_bone_global_pose_override(foot_idx, Transform3D(), 0.0, false)
		return
	
	# 將世界空間的法線轉換到骨架空間
	var skel_basis_inv = skeleton.global_transform.basis.inverse()
	var raw_normal = skel_basis_inv * ground_normal
	if raw_normal.is_zero_approx():
		return
	var local_normal = raw_normal.normalized()
	
	# 計算從 UP 到法線的旋轉
	var from_up = Vector3.UP
	var rot_axis = from_up.cross(local_normal)
	if rot_axis.is_zero_approx() or rot_axis.length_squared() < 0.0001:
		return
	rot_axis = rot_axis.normalized()
	var rot_angle = from_up.angle_to(local_normal)
	
	# 限制角度
	var max_rad = deg_to_rad(max_pitch_angle)
	rot_angle = clampf(rot_angle, 0.0, max_rad)
	
	# 平滑過渡角度
	if is_left:
		_left_foot_pitch = lerp(_left_foot_pitch, rot_angle, delta * foot_rotation_speed)
		rot_angle = _left_foot_pitch
	else:
		_right_foot_pitch = lerp(_right_foot_pitch, rot_angle, delta * foot_rotation_speed)
		rot_angle = _right_foot_pitch
	
	if abs(rot_angle) < 0.005:
		skeleton.set_bone_global_pose_override(foot_idx, Transform3D(), 0.0, false)
		return
	
	# 讀取乾淨的 IK 姿態（不含上一幀的 override）
	var bone_pose = skeleton.get_bone_global_pose_no_override(foot_idx)
	var current_basis = bone_pose.basis.orthonormalized()
	
	# 應用旋轉：繞法線交叉軸旋轉
	var align_quat = Quaternion(rot_axis, rot_angle)
	var new_basis = (Basis(align_quat) * current_basis).orthonormalized()
	
	var override_transform = Transform3D(new_basis, bone_pose.origin)
	# ★ ankle_weight 控制旋轉強度：移動時=0.2（微弱），站立時=1.0（完全）
	var weight = clampf(_current_influence * ankle_weight, 0.0, 1.0)
	skeleton.set_bone_global_pose_override(foot_idx, override_transform, weight, true)

## 最小 IK 測試版本 - 只更新位置，不旋轉
func _update_foot_target_minimal(target: Marker3D, bone_idx: int, hip_idx: int, delta: float, is_left: bool = true) -> float:
	var bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	var foot_pos = bone_global.origin
	
	# 計算髖關節位置（用於距離限制）
	var hip_pos = foot_pos # 預設
	if hip_idx >= 0:
		var hip_global = skeleton.global_transform * skeleton.get_bone_global_pose(hip_idx)
		hip_pos = hip_global.origin
	
	# 單條射線偵測地面
	var parent = _char_body
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = [parent.get_rid()] if parent is CharacterBody3D else []
	
	var ray_start = foot_pos + Vector3.UP * 0.3 # 從腳踝上方開始
	var ray_end = foot_pos + Vector3.DOWN * ray_length
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1 # 層 1 = 地面
	query.exclude = exclude_rid
	
	var result = space_state.intersect_ray(query)
	
	# 診斷輸出 - 每60幀輸出一次
	if Engine.get_process_frames() % 60 == 0:
		print("[FootIK] influence=%.2f target=%s hit=%s" % [
			_current_influence,
			str(target.name) if target else "NULL",
			not result.is_empty()
		])
		if not result.is_empty():
			print("  ground_y=%.2f foot_y=%.2f diff=%.2f" % [
				result.position.y, foot_pos.y, result.position.y - foot_pos.y
			])
			print("  target_pos=(%.2f, %.2f, %.2f)" % [
				target.global_position.x, target.global_position.y, target.global_position.z
			])
	
	if result.is_empty():
		# 沒擊中地面（腳在邊緣懸空）- 平滑回到動畫位置
		# 不能直接 return，必須更新 target 以避免腳卡在舊位置
		target.global_position = target.global_position.lerp(foot_pos, delta * smooth_speed)
		return foot_pos.y
	
	var ground_y = result.position.y
	var height_diff = ground_y - foot_pos.y
	
	# 高度差檢查
	if height_diff < -max_step_down or height_diff > max_step_up:
		target.global_position = target.global_position.lerp(foot_pos, delta * smooth_speed)
		return foot_pos.y
	
	# 計算目標位置
	var new_pos = Vector3(foot_pos.x, ground_y + foot_height_offset, foot_pos.z)
	
	# ★★★ Y 軸鎖定：支撐腳鎖定 Y，允許 XZ 微調 ★★★
	if is_left and left_foot_y_locked:
		new_pos.y = _locked_left_y + foot_height_offset
	elif not is_left and right_foot_y_locked:
		new_pos.y = _locked_right_y + foot_height_offset
	
	# ★★★ 距離限制：防止腳延伸超過腿的長度 ★★★
	if hip_idx >= 0:
		var distance_to_hip = new_pos.distance_to(hip_pos)
		if distance_to_hip > max_reach_distance:
			# 超出最大距離→用動畫位置代替，並平滑過渡
			new_pos = new_pos.lerp(foot_pos, (distance_to_hip - max_reach_distance) / 0.3)
			# 0.3 是過渡區域，距離超出越多越接近動畫位置
	
	target.global_position = target.global_position.lerp(new_pos, delta * smooth_speed)
	
	# 不改變目標旋轉！
	
	return ground_y


## 更新 LookAt 目標位置 - 讓腳掌與地面平行
func _update_lookat_targets(delta: float) -> void:
	"""使用 Quaternion.LookRotation 原理：
	   target = foot_pos + project(char_forward, ground_plane) * offset
	   → LookAtModifier 讓腳尖朝向 target → 腳掌自動平行地面
	"""
	var parent = _char_body
	if not parent:
		return
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = [parent.get_rid()] if parent is CharacterBody3D else []
	var char_forward = -parent.global_transform.basis.z
	var smooth_speed_lookat = 15.0
	
	# ★ 通用函數：計算單腳 LookAt 目標
	# ground_normal: 地面法線, foot_pos: 腳踝世界座標
	# 回傳：LookAt target 世界座標
	var _calc_target = func(foot_pos: Vector3, ground_normal: Vector3) -> Vector3:
		# 將 char_forward 投影到地面法線定義的平面上
		# slope_forward = forward - normal * dot(forward, normal)
		var slope_forward = char_forward - ground_normal * char_forward.dot(ground_normal)
		if slope_forward.length_squared() < 0.0001:
			slope_forward = char_forward  # fallback
		else:
			slope_forward = slope_forward.normalized()
		
		# target = 腳踝 + 沿地面的前方 * 偏移
		# 這樣在上坡時 target.y > foot.y → 腳尖朝上
		# 在下坡時 target.y < foot.y → 腳尖朝下
		return foot_pos + slope_forward * lookat_forward_offset
	
	# ★ 通用函數：射線偵測並更新 LookAt target
	var _update_foot_lookat = func(
		foot_idx: int, lookat_target: Marker3D, is_left: bool
	) -> void:
		var foot_global = skeleton.global_transform * skeleton.get_bone_global_pose(foot_idx)
		var foot_pos = foot_global.origin
		
		# 射線偵測地面
		var ray_start = foot_pos + Vector3.UP * 0.3
		var ray_end = foot_pos + Vector3.DOWN * ray_length
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1
		query.exclude = exclude_rid
		var result = space_state.intersect_ray(query)
		
		var target_pos: Vector3
		if not result.is_empty():
			target_pos = _calc_target.call(foot_pos, result.normal)
		else:
			# 沒擊中地面 → 水平前方
			target_pos = foot_pos + char_forward * lookat_forward_offset
		
		# 平滑
		lookat_target.global_position = lookat_target.global_position.lerp(
			target_pos, delta * smooth_speed_lookat
		)
	
	# 更新左腳
	if left_lookat_target and _left_foot_idx >= 0:
		_update_foot_lookat.call(_left_foot_idx, left_lookat_target, true)
	
	# 更新右腳
	if right_lookat_target and _right_foot_idx >= 0:
		_update_foot_lookat.call(_right_foot_idx, right_lookat_target, false)
	
	# ★ LookAt influence = Phase × IK × 斜坡因子
	# 平地 (normal·UP > 0.98) → influence=0 → 動畫原生旋轉（不需修正）
	# 斜坡 (normal·UP < 0.95) → influence=1 → 旋轉貼合斜面
	var l_slope_dot = _left_ground_normal.dot(Vector3.UP)
	var r_slope_dot = _right_ground_normal.dot(Vector3.UP)
	# 0.98 → 0.0,  0.95 → 1.0 的平滑映射
	var l_slope_factor = clampf((0.98 - l_slope_dot) / 0.03, 0.0, 1.0)
	var r_slope_factor = clampf((0.98 - r_slope_dot) / 0.03, 0.0, 1.0)
	
	var l_lookat_infl = _current_influence * _left_foot_phase * l_slope_factor
	var r_lookat_infl = _current_influence * _right_foot_phase * r_slope_factor
	if left_lookat_modifier:
		left_lookat_modifier.influence = l_lookat_infl
	if right_lookat_modifier:
		right_lookat_modifier.influence = r_lookat_infl


func _update_foot_target_with_rotation(target: Marker3D, bone_idx: int, delta: float, is_left: bool) -> float:
	"""Triple Raycast 偵測地面，更新目標位置，並應用安全的相對旋轉"""
	var bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	var foot_pos = bone_global.origin
	
	# 獲取角色朝向（用於計算腳跟/腳尖位置）
	var parent = _char_body
	var char_forward = - parent.global_transform.basis.z if parent else Vector3.FORWARD
	
	# 計算三個射線的起點（使用角色朝向，不是腳骨朝向 - 穩定性）
	var heel_pos = foot_pos + char_forward * heel_offset.z + Vector3.UP * heel_offset.y
	var toe_pos = foot_pos + char_forward * toe_offset.z + Vector3.UP * toe_offset.y
	var ball_pos = foot_pos + char_forward * ball_offset.z + Vector3.UP * ball_offset.y
	
	# 執行三條射線
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = [parent.get_rid()] if parent is CharacterBody3D else []
	
	var heel_hit = _cast_ground_ray(space_state, heel_pos, exclude_rid)
	var toe_hit = _cast_ground_ray(space_state, toe_pos, exclude_rid)
	var ball_hit = _cast_ground_ray(space_state, ball_pos, exclude_rid)
	
	# 存儲 debug 數據
	if is_left:
		_debug_left_ray_start = ball_pos
		_debug_left_ray_end = ball_pos + Vector3.DOWN * ray_length
	else:
		_debug_right_ray_start = ball_pos
		_debug_right_ray_end = ball_pos + Vector3.DOWN * ray_length
	
	# 收集有效的擊中點
	var hits: Array[Dictionary] = []
	if heel_hit.hit: hits.append(heel_hit)
	if toe_hit.hit: hits.append(toe_hit)
	if ball_hit.hit: hits.append(ball_hit)
	
	if hits.size() == 0:
		if is_left:
			_debug_left_hit = false
		else:
			_debug_right_hit = false
		target.global_position = target.global_position.lerp(foot_pos, delta * smooth_speed)
		return foot_pos.y
	
	# 取最高的擊中點作為地面高度（防止穿模）
	var highest_y = - INF
	var avg_normal = Vector3.ZERO
	for hit in hits:
		if hit.position.y > highest_y:
			highest_y = hit.position.y
		avg_normal += hit.normal
	avg_normal = avg_normal.normalized()
	
	# 存儲 debug 地面點
	if is_left:
		_debug_left_ground = Vector3(foot_pos.x, highest_y, foot_pos.z)
		_debug_left_hit = true
	else:
		_debug_right_ground = Vector3(foot_pos.x, highest_y, foot_pos.z)
		_debug_right_hit = true
	
	# 檢查高度差是否在合理範圍內
	var height_diff = highest_y - foot_pos.y
	if height_diff < -max_step_down or height_diff > max_step_up:
		target.global_position = target.global_position.lerp(foot_pos, delta * smooth_speed)
		return foot_pos.y
	
	# 計算腳的 Pitch 角度（從腳跟到腳尖的傾斜）
	var pitch_angle = 0.0
	if heel_hit.hit and toe_hit.hit:
		var heel_to_toe_dist = abs(toe_offset.z - heel_offset.z)
		var height_change = toe_hit.position.y - heel_hit.position.y
		pitch_angle = atan2(height_change, heel_to_toe_dist)
		# 限制 pitch 角度範圍
		var max_pitch_rad = deg_to_rad(max_pitch_angle)
		pitch_angle = clamp(pitch_angle, -max_pitch_rad, max_pitch_rad)
	
	# 計算 Roll 角度（從地面法線）
	var roll_angle = 0.0
	if avg_normal.length_squared() > 0.01 and parent:
		var char_basis = parent.global_transform.basis
		var local_normal = char_basis.inverse() * avg_normal
		# 在角色局部空間的 X-Y 平面投影獲得 Roll
		roll_angle = - atan2(local_normal.x, local_normal.y)
		# 限制 roll 角度（人類腳踝通常只能 ±15°）
		roll_angle = clamp(roll_angle, deg_to_rad(-15.0), deg_to_rad(15.0))
	
	# 目標位置：X/Z 跟隨腳，Y = 最高地面 + 腳踝偏移
	var new_pos = Vector3(foot_pos.x, highest_y + foot_height_offset, foot_pos.z)
	target.global_position = target.global_position.lerp(new_pos, delta * smooth_speed)
	
	# 應用安全的相對旋轉（使用 DELTA，不是絕對覆蓋）
	_rotate_foot_bone_relative(bone_idx, pitch_angle, roll_angle, delta)
	
	return highest_y


## 安全的相對旋轉 - 使用 DELTA 避免反摺
func _rotate_foot_bone_relative(bone_idx: int, pitch: float, roll: float, delta: float) -> void:
	"""使用相對旋轉調整腳骨。
	關鍵：將 pitch/roll 作為 DELTA 乘上當前 basis，而非絕對覆蓋。
	這保留了動畫的基礎方向，只添加斜坡對齊調整。"""
	if bone_idx < 0 or not skeleton:
		return
	
	var current_global = skeleton.global_transform * skeleton.get_bone_global_pose(bone_idx)
	var current_basis = current_global.basis.orthonormalized()
	
	# 縮放旋轉量基於 influence
	var scaled_pitch = pitch * _current_influence
	var scaled_roll = roll * _current_influence
	
	# 構建旋轉調整四元數 (DELTA，不是絕對值)
	# 注意：這裡使用負 pitch 因為骨骼坐標系可能需要
	var adjust_quat = Quaternion.from_euler(Vector3(-scaled_pitch, 0, scaled_roll))
	
	# 將調整乘上當前 basis（保留動畫的 yaw）
	var new_basis = (current_basis * Basis(adjust_quat)).orthonormalized()
	var override_transform = Transform3D(new_basis, current_global.origin)
	
	# 使用 global_pose_override 在 IK 之後應用
	var weight = clampf(delta * foot_rotation_speed, 0.0, 1.0)
	skeleton.set_bone_global_pose_override(bone_idx, override_transform, weight, true)


func _cast_ground_ray(space_state: PhysicsDirectSpaceState3D, origin: Vector3, exclude: Array) -> Dictionary:
	"""執行單條地面射線"""
	var ray_end = origin + Vector3.DOWN * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collision_mask = 1
	query.exclude = exclude
	
	var result = space_state.intersect_ray(query)
	if result:
		return {"hit": true, "position": result.position, "normal": result.normal}
	return {"hit": false, "position": Vector3.ZERO, "normal": Vector3.UP}


func _rotate_foot_bone_legacy(bone_idx: int, pitch: float, normal: Vector3, delta: float) -> void:
	"""使用 pose_override 在 IK 之後旋轉腳骨"""
	if bone_idx < 0 or not skeleton:
		return
	
	# 獲取當前骨骼全局姿態（IK 解算後的結果）
	var current_global = skeleton.get_bone_global_pose(bone_idx)
	
	# 獲取父骨骼的旋轉來計算世界空間的基準
	var parent = _char_body
	if not parent:
		return
	var char_yaw = parent.global_rotation.y
	
	# 目標旋轉角度（絕對值，不是增量）
	# Pitch (X 軸) - 從地面傾斜計算
	var target_pitch = pitch * _current_influence
	
	# Roll (Z 軸) - 從地面法線計算
	var target_roll = 0.0
	if normal.length_squared() > 0.01:
		# 計算法線相對於 UP 的傾斜
		var side_tilt = atan2(normal.x, normal.y) * _current_influence
		target_roll = - side_tilt # 負號讓腳向正確方向傾斜
	
	# 構建目標旋轉（使用角色的 yaw + 我們計算的 pitch/roll）
	# 注意：保持 pitch 為負值讓腳尖向下傾斜時是正常的斜坡行為
	var target_euler = Vector3(-target_pitch, char_yaw, target_roll)
	var target_basis = Basis.from_euler(target_euler).orthonormalized()
	
	# 平滑插值到目標 - 需要正規化 Basis 才能使用 slerp
	var current_basis = current_global.basis.orthonormalized()
	var smooth_basis = current_basis.slerp(target_basis, clampf(delta * foot_rotation_speed, 0.0, 1.0))
	
	var override_transform = Transform3D(smooth_basis, current_global.origin)
	
	# 使用 global_pose_override - 這會在 IK modifier 之後應用
	skeleton.set_bone_global_pose_override(bone_idx, override_transform, _current_influence, true)


func _apply_foot_pitch(target: Marker3D, pitch: float, normal: Vector3, delta: float) -> void:
	"""應用腳的 Pitch 旋轉和地面對齊"""
	# 計算目標旋轉
	var target_rotation = target.rotation
	
	# Pitch (X 軸旋轉) 來自腳跟-腳尖高度差
	target_rotation.x = lerp_angle(target_rotation.x, pitch, delta * foot_rotation_speed)
	
	# Roll (Z 軸旋轉) 來自地面法線
	if normal.length_squared() > 0.01:
		var up = Vector3.UP
		var axis = up.cross(normal)
		if axis.length_squared() > 0.001:
			var angle = up.angle_to(normal)
			# 只取 Roll 分量
			target_rotation.z = lerp_angle(target_rotation.z, axis.z * angle, delta * foot_rotation_speed)
	
	target.rotation = target_rotation


func _align_to_normal(target: Marker3D, normal: Vector3, delta: float) -> void:
	"""讓目標對齊地面法線"""
	if normal.length_squared() < 0.01:
		return
	
	var up = Vector3.UP
	var axis = up.cross(normal)
	if axis.length_squared() < 0.001:
		return
	
	axis = axis.normalized()
	var angle = acos(clamp(up.dot(normal), -1.0, 1.0))
	
	var target_quat = Quaternion(axis, angle)
	var current_quat = Quaternion(target.transform.basis.orthonormalized())
	var smoothed = current_quat.slerp(target_quat, delta * smooth_speed * 0.3)
	target.transform.basis = Basis(smoothed)


func _apply_pelvis_offset(delta: float) -> void:
	"""根據地面高度調整骨架位置，解決膠囊體懸空問題"""
	var parent = _char_body
	if not parent:
		return
	
	# ★ 空中保護：跳躍/掉落時不做 pelvis 下沉
	if not parent.is_on_floor():
		_current_pelvis_offset = lerp(_current_pelvis_offset, 0.0, delta * pelvis_smooth_speed * 0.5)
		skeleton.position.y = _original_skeleton_y + _current_pelvis_offset
		return
	
	# ★ 方案 B: 樓梯上不做 pelvis 下沉（地面射線在不同台階高度會造成異常下蹲）
	if stair_ik_active:
		_current_pelvis_offset = lerp(_current_pelvis_offset, 0.0, delta * pelvis_smooth_speed)
		skeleton.position.y = _original_skeleton_y + _current_pelvis_offset
		return
	
	var body_y = parent.global_position.y
	
	# ★★★ PredictIK 模式：Pelvis 跟隨最低虛擬腳 ★★★
	# 樓梯上不要直接使用虛擬腳高度驅動骨盆，否則 body_y 與預測踏面高度落差過大時
	# 會出現明顯的下蹲/吸地。樓梯交給一般模式用真實地面高度處理。
	if enable_predictive_ik and not stair_ik_active and not temporary_disable_predict_ik and _left_pred_active and _right_pred_active:
		var virtual_height = minf(_left_pred_virtual_y, _right_pred_virtual_y)
		# 動畫 Pelvis 偏移 = 骨盆到角色原點的高度
		var anim_pelvis_offset = _original_skeleton_y
		# 目標 pelvis Y = virtualHeight - body_y (相對偏移)
		var target_pelvis = virtual_height - body_y + anim_pelvis_offset
		_current_pelvis_offset = lerp(_current_pelvis_offset, target_pelvis, delta * pelvis_smooth_speed)
		skeleton.position.y = _original_skeleton_y + _current_pelvis_offset
		
		if Engine.get_physics_frames() % 30 == 0:
			print("[PredIK-Pelvis] vH=%.3f body=%.3f tgt=%.3f cur=%.3f" % [
				virtual_height, body_y, target_pelvis, _current_pelvis_offset
			])
		return
	
	# === 一般模式 ===
	# ★ 懸崖防暴跌：過濾掉不合理的地面值
	var l_valid = (_left_ground_y - body_y) > -max_reach_distance
	var r_valid = (_right_ground_y - body_y) > -max_reach_distance
	var l_gnd = _left_ground_y if l_valid else body_y
	var r_gnd = _right_ground_y if r_valid else body_y
	
	var lowest_ground = min(l_gnd, r_gnd)
	var highest_ground = max(l_gnd, r_gnd)
	
	# ★★★ IK 到達距離感知 pelvis 偏移 ★★★
	var hip_rest_height := 0.93
	var leg_length := 0.86
	var reach_margin := 0.05
	var effective_reach := leg_length - reach_margin
	
	var l_target_y = l_gnd + foot_height_offset
	var r_target_y = r_gnd + foot_height_offset
	var hip_y = body_y + hip_rest_height
	
	var l_needed_drop = effective_reach - (hip_y - l_target_y)
	var r_needed_drop = effective_reach - (hip_y - r_target_y)
	
	var needed_drop = min(l_needed_drop, r_needed_drop)
	var reference_ground: float
	if needed_drop < 0.0:
		reference_ground = body_y + needed_drop
	else:
		reference_ground = body_y
	
	var needed_offset = reference_ground - body_y
	
	var target_offset = 0.0
	if needed_offset < -0.01:
		target_offset = clamp(needed_offset, -max_pelvis_offset, 0.0)
		
		# ★ 關鍵：防穿模保護。
		# 當骨盆下沉時，高腳 (highest_ground) 相對於新骨盆位置會越來越高。
		# 我們不希望高腳被過度壓縮（不能超過 max_step_up）。
		# 新骨盆 Y = body_y + target_offset
		# 高腳相對高度 = highest_ground - 新骨盆 Y = highest_ground - body_y - target_offset
		# 限制：highest_ground - body_y - target_offset <= max_step_up
		# => -target_offset <= max_step_up - (highest_ground - body_y)
		# => target_offset >= (highest_ground - body_y) - max_step_up
		var min_allowed_offset = (highest_ground - body_y) - max_step_up
		target_offset = max(target_offset, min_allowed_offset)
	
	# 平滑過渡
	_current_pelvis_offset = lerp(_current_pelvis_offset, target_offset, delta * pelvis_smooth_speed)
	
	# 應用到骨架位置
	skeleton.position.y = _original_skeleton_y + _current_pelvis_offset
	
	# 日誌
	if Engine.get_process_frames() % 120 == 0:
		if debug_draw: print("[SimpleFootIK] Pelvis: %.3f (body=%.2f lo_gnd=%.2f hi_gnd=%.2f) tgt=%.3f min=%.3f" % [
			_current_pelvis_offset, body_y, lowest_ground, highest_ground, target_offset, (highest_ground - body_y) - max_step_up
		])


## 獲取左腳世界座標 (供 StepPlanner 使用)
func get_left_foot_position() -> Vector3:
	if skeleton and _left_foot_idx >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx).origin
	return Vector3.ZERO


## 獲取右腳世界座標 (供 StepPlanner 使用)
func get_right_foot_position() -> Vector3:
	if skeleton and _right_foot_idx >= 0:
		return skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx).origin
	return Vector3.ZERO


# =============================================
# ★★★ 支撐腳 Y 軸鎖定 API ★★★
# =============================================

## 鎖定腳的 Y 軸（記錄當前地面高度，之後 target Y 不再更新）
func lock_y(foot: String) -> void:
	if foot == "left":
		_locked_left_y = _left_ground_y
		left_foot_y_locked = true
		if Engine.get_process_frames() % 10 == 0:
			print("[SimpleFootIK] 左腳 Y 鎖定在 %.3f" % _locked_left_y)
	else:
		_locked_right_y = _right_ground_y
		right_foot_y_locked = true
		if Engine.get_process_frames() % 10 == 0:
			print("[SimpleFootIK] 右腳 Y 鎖定在 %.3f" % _locked_right_y)


## 解鎖腳的 Y 軸
func unlock_y(foot: String) -> void:
	if foot == "left":
		left_foot_y_locked = false
	else:
		right_foot_y_locked = false


# =============================================
# ★★★ Per-Foot Influence 覆蓋 API ★★★
# =============================================

## 設定左腳 IK influence（覆蓋全局值）
func set_left_influence(value: float) -> void:
	_left_influence_override = value


## 設定右腳 IK influence（覆蓋全局值）
func set_right_influence(value: float) -> void:
	_right_influence_override = value


## 清除左腳 influence 覆蓋（恢復使用全局值）
func clear_left_influence_override() -> void:
	_left_influence_override = -1.0


## 清除右腳 influence 覆蓋（恢復使用全局值）
func clear_right_influence_override() -> void:
	_right_influence_override = -1.0


func _draw_debug() -> void:
	var dd = _debug_draw_3d
	if not dd:
		if Engine.get_process_frames() % 60 == 0:
			print("[FootIK Debug] DebugDraw3D not found. Set debug_draw=false to suppress.")
		return
	if not skeleton:
		return

	# ─── 顏色定義 ───────────────────────────────────────────────
	var C_STANCE   := Color(0.2, 1.0, 0.2, 1.0)   # 亮綠：stance（貼地）
	var C_TRANSIT  := Color(1.0, 0.8, 0.0, 1.0)   # 黃：過渡（landing）
	var C_SWING    := Color(1.0, 0.3, 0.1, 1.0)   # 橙紅：swing（空中）
	var C_TARGET   := Color(0.3, 0.9, 1.0, 1.0)   # 青：IK Target
	var C_GROUND   := Color(0.5, 0.5, 1.0, 1.0)   # 藍紫：地面偵測
	var C_PELVIS   := Color(1.0, 1.0, 0.3, 0.8)   # 黃：骨盆
	var C_PRED_ARC := Color(1.0, 0.6, 0.0, 0.9)   # 橙：預測軌跡弧
	var C_PRED_END := Color(1.0, 0.9, 0.1, 1.0)   # 亮黃：預測落點

	# ─── 輔助：根據 Phase 回傳顏色 ──────────────────────────────
	var l_col: Color
	if _left_stance_locked or _left_foot_phase >= STANCE_LOCK_THRESHOLD:
		l_col = C_STANCE
	elif _left_foot_phase >= plant_enter_phase_threshold:
		l_col = C_TRANSIT
	else:
		l_col = C_SWING
	
	var r_col: Color
	if _right_stance_locked or _right_foot_phase >= STANCE_LOCK_THRESHOLD:
		r_col = C_STANCE
	elif _right_foot_phase >= plant_enter_phase_threshold:
		r_col = C_TRANSIT
	else:
		r_col = C_SWING

	# ─── 取得骨骼位置 ──────────────────────────────────────────
	var l_bone_pos := Vector3.ZERO
	var r_bone_pos := Vector3.ZERO
	if _left_foot_idx >= 0:
		l_bone_pos = (skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)).origin
	if _right_foot_idx >= 0:
		r_bone_pos = (skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)).origin

	# ─────────────────────────────────────────────
	# 1. 地面偵測射線 + 法線（左=藍紫，右=藍紫）
	# ─────────────────────────────────────────────
	dd.draw_line(_debug_left_ray_start, _debug_left_ray_end, Color(C_GROUND, 0.4))
	if _debug_left_hit:
		dd.draw_sphere(_debug_left_ground, 0.04, C_GROUND)
		dd.draw_line(_debug_left_ground, _debug_left_ground + _left_ground_normal * 0.12, Color(C_GROUND, 0.7))

	dd.draw_line(_debug_right_ray_start, _debug_right_ray_end, Color(C_GROUND, 0.4))
	if _debug_right_hit:
		dd.draw_sphere(_debug_right_ground, 0.04, C_GROUND)
		dd.draw_line(_debug_right_ground, _debug_right_ground + _right_ground_normal * 0.12, Color(C_GROUND, 0.7))

	# ─────────────────────────────────────────────
	# 2. 骨骼實際位置（相位顏色的小球）
	# ─────────────────────────────────────────────
	if _left_foot_idx >= 0:
		dd.draw_sphere(l_bone_pos, 0.035, l_col)
	if _right_foot_idx >= 0:
		dd.draw_sphere(r_bone_pos, 0.035, r_col)

	# ─────────────────────────────────────────────
	# 3. IK Target（青色大球 + 目標到骨骼的誤差線）
	# ─────────────────────────────────────────────
	if left_target:
		var lt = left_target.global_position
		dd.draw_sphere(lt, 0.05, C_TARGET)
		if _left_foot_idx >= 0:
			dd.draw_line(lt, l_bone_pos, Color(C_TARGET, 0.5))
	if right_target:
		var rt = right_target.global_position
		dd.draw_sphere(rt, 0.05, C_TARGET)
		if _right_foot_idx >= 0:
			dd.draw_line(rt, r_bone_pos, Color(C_TARGET, 0.5))

	# ─────────────────────────────────────────────
	# 4. PredictIK 預測軌跡弧 + 預測落點
	# ─────────────────────────────────────────────
	if enable_predictive_ik:  # 樓梯時也顯示，用於驗證台階偵測準確度
		const ARC_STEPS := 10
		const DEBUG_ARC_LIFT := 0.15  # 弧線往上抬，避免被地面蓋住

		# 左腳預測弧
		if _left_pred_active:
			var prev_arc_pos := Vector3.ZERO
			for i in range(ARC_STEPS + 1):
				var t = float(i) / float(ARC_STEPS)
				var arc_y = _eval_predict_curve(
					_left_pred_start_pos.y, _left_pred_mid_y, _left_pred_end_y,
					_left_pred_mid_t, t
				)
				var arc_pos = _left_pred_start_pos.lerp(_left_pred_end_pos, t)
				# 實際弧高 + 視覺抬升 + swing 拋物線（平地也有弧形）
				var parabola = 4.0 * t * (1.0 - t) * 0.12  # 拋物線 apex=0.12m
				arc_pos.y = arc_y + DEBUG_ARC_LIFT + parabola
				if i > 0:
					dd.draw_line(prev_arc_pos, arc_pos, C_PRED_ARC)
				dd.draw_sphere(arc_pos, 0.018, C_PRED_ARC if i > 0 and i < ARC_STEPS else C_PRED_END)
				prev_arc_pos = arc_pos

			# 預測落點圈（地面高程）
			var l_end_ground = _left_pred_end_pos
			l_end_ground.y = _left_pred_end_y + DEBUG_ARC_LIFT
			dd.draw_sphere(l_end_ground, 0.07, C_PRED_END)

			# 當前進度指示（現在走到哪了）
			var prog_l = _get_swing_progress(true)
			var cur_l_y = _eval_predict_curve(
				_left_pred_start_pos.y, _left_pred_mid_y, _left_pred_end_y,
				_left_pred_mid_t, prog_l
			)
			var cur_parabola_l = 4.0 * prog_l * (1.0 - prog_l) * 0.12
			var cur_l_pos = _left_pred_start_pos.lerp(_left_pred_end_pos, prog_l)
			cur_l_pos.y = cur_l_y + DEBUG_ARC_LIFT + cur_parabola_l
			dd.draw_sphere(cur_l_pos, 0.04, Color.WHITE)
			dd.draw_line(l_bone_pos, cur_l_pos, Color(1, 1, 1, 0.5))

		# 右腳預測弧
		if _right_pred_active:
			var prev_arc_pos := Vector3.ZERO
			for i in range(ARC_STEPS + 1):
				var t = float(i) / float(ARC_STEPS)
				var arc_y = _eval_predict_curve(
					_right_pred_start_pos.y, _right_pred_mid_y, _right_pred_end_y,
					_right_pred_mid_t, t
				)
				var arc_pos = _right_pred_start_pos.lerp(_right_pred_end_pos, t)
				var parabola = 4.0 * t * (1.0 - t) * 0.12
				arc_pos.y = arc_y + DEBUG_ARC_LIFT + parabola
				if i > 0:
					dd.draw_line(prev_arc_pos, arc_pos, C_PRED_ARC)
				dd.draw_sphere(arc_pos, 0.018, C_PRED_ARC if i > 0 and i < ARC_STEPS else C_PRED_END)
				prev_arc_pos = arc_pos

			var r_end_ground = _right_pred_end_pos
			r_end_ground.y = _right_pred_end_y + DEBUG_ARC_LIFT
			dd.draw_sphere(r_end_ground, 0.07, C_PRED_END)

			var prog_r = _get_swing_progress(false)
			var cur_r_y = _eval_predict_curve(
				_right_pred_start_pos.y, _right_pred_mid_y, _right_pred_end_y,
				_right_pred_mid_t, prog_r
			)
			var cur_parabola_r = 4.0 * prog_r * (1.0 - prog_r) * 0.12
			var cur_r_pos = _right_pred_start_pos.lerp(_right_pred_end_pos, prog_r)
			cur_r_pos.y = cur_r_y + DEBUG_ARC_LIFT + cur_parabola_r
			dd.draw_sphere(cur_r_pos, 0.04, Color.WHITE)
			dd.draw_line(r_bone_pos, cur_r_pos, Color(1, 1, 1, 0.5))

		# 虛擬高度水平面（薄黃線連接兩腳）
		if _left_pred_active and _right_pred_active:
			var l_virt = l_bone_pos
			l_virt.y = _left_pred_virtual_y
			var r_virt = r_bone_pos
			r_virt.y = _right_pred_virtual_y
			dd.draw_sphere(l_virt, 0.03, Color(1, 1, 0, 0.6))
			dd.draw_sphere(r_virt, 0.03, Color(1, 1, 0, 0.6))

	# ─────────────────────────────────────────────
	# 5. 骨盆偏移指示
	# ─────────────────────────────────────────────
	if skeleton and abs(_current_pelvis_offset) > 0.002:
		var sk_pos = skeleton.global_position
		var pelvis_target_pos = sk_pos + Vector3(0, _current_pelvis_offset, 0)
		dd.draw_line(sk_pos, pelvis_target_pos, C_PELVIS)
		dd.draw_sphere(pelvis_target_pos, 0.04, C_PELVIS)

	# ─────────────────────────────────────────────
	# 6. 相位狀態小菱形（左右腳骨骨骼正上方）
	# ─────────────────────────────────────────────
	if _left_foot_idx >= 0:
		var lf_indicator = l_bone_pos + Vector3.UP * 0.22
		dd.draw_sphere(lf_indicator, 0.025, l_col)
	if _right_foot_idx >= 0:
		var rf_indicator = r_bone_pos + Vector3.UP * 0.22
		dd.draw_sphere(rf_indicator, 0.025, r_col)

	# ─────────────────────────────────────────────
	# 7. 樓梯支撐腳鎖定 + 預測落點可視化
	# ─────────────────────────────────────────────
	var C_LOCK := Color(1.0, 0.0, 1.0, 1.0)  # 洋紅：鎖定支撐腳
	var C_STAIR_ON := Color(0.0, 1.0, 0.5, 1.0)  # 綠：樓梯模式開
	var C_STAIR_OFF := Color(0.5, 0.5, 0.5, 0.5)  # 灰：樓梯模式關

	# 樓梯模式指示器（角色頭頂上方）
	if _char_body:
		var head_pos = _char_body.global_position + Vector3.UP * 2.0
		var stair_col = C_STAIR_ON if stair_ik_active else C_STAIR_OFF
		dd.draw_sphere(head_pos, 0.06, stair_col)

	# 鎖定支撐腳位置（洋紅大球 + 線到骨骼）
	if left_foot_locked:
		dd.draw_sphere(_left_locked_ground, 0.08, C_LOCK)
		if _left_foot_idx >= 0:
			dd.draw_line(l_bone_pos, _left_locked_ground, C_LOCK)
	if right_foot_locked:
		dd.draw_sphere(_right_locked_ground, 0.08, C_LOCK)
		if _right_foot_idx >= 0:
			dd.draw_line(r_bone_pos, _right_locked_ground, C_LOCK)

	# 樓梯 IK 目標踏面高度指示（pred_end_y 水平線）
	if stair_ik_active and enable_predictive_ik:
		if _left_pred_active:
			var l_tread = Vector3(l_bone_pos.x, _left_pred_end_y + foot_height_offset, l_bone_pos.z)
			dd.draw_sphere(l_tread, 0.05, Color(0.0, 1.0, 1.0, 0.8))
			dd.draw_line(l_tread + Vector3(-0.15, 0, 0), l_tread + Vector3(0.15, 0, 0), Color(0.0, 1.0, 1.0, 0.8))
		if _right_pred_active:
			var r_tread = Vector3(r_bone_pos.x, _right_pred_end_y + foot_height_offset, r_bone_pos.z)
			dd.draw_sphere(r_tread, 0.05, Color(0.0, 1.0, 1.0, 0.8))
			dd.draw_line(r_tread + Vector3(-0.15, 0, 0), r_tread + Vector3(0.15, 0, 0), Color(0.0, 1.0, 1.0, 0.8))
