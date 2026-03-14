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
@export var max_reach_distance: float = 1.1
@export var smooth_speed: float = 15.0
@export var influence_speed: float = 8.0 # IK 混合速度
## 腳踝到腳底的距離（防止腳穿進地面）
@export var foot_height_offset: float = 0.08

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

# ★ 動態步伐相位 (Procedural Foot Phase)
var _prev_left_y: float = 0.0
var _prev_right_y: float = 0.0
var _left_foot_phase: float = 1.0
var _right_foot_phase: float = 1.0
var _char_body: CharacterBody3D = null

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
var _left_locked_normal: Vector3 = Vector3.UP
var _right_locked_normal: Vector3 = Vector3.UP
const STANCE_LOCK_THRESHOLD: float = 0.85    # phase > 此值 = stance（腳著地）
const SWING_UNLOCK_THRESHOLD: float = 0.5    # phase < 此值 = swing（腳離地）

# ★★★ Predictive IK - Temporal Interpolation 狀態 ★★★
var _prev_left_target: Vector3 = Vector3.ZERO  # 上一物理幀的 target
var _prev_right_target: Vector3 = Vector3.ZERO
var _curr_left_target: Vector3 = Vector3.ZERO   # 當前物理幀的 target
var _curr_right_target: Vector3 = Vector3.ZERO

# ★★★ Predictive IK - Debug 預測點 ★★★
var _debug_left_predict_pos: Vector3 = Vector3.ZERO
var _debug_right_predict_pos: Vector3 = Vector3.ZERO


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
		left_ik.active = false  # ★ 延遲啟用，等 _init_targets 設定好目標位置後才開
		if left_target:
			var path = left_ik.get_path_to(left_target)
			left_ik.set("settings/0/target_node", path)
			print("[SimpleFootIK] Assigned Left IK target path: ", path)
	else:
		push_warning("[SimpleFootIK] ⚠️ left_ik not assigned! IK influence control disabled for left foot.")
		
	if right_ik:
		right_ik.active = false  # ★ 同上
		if right_target:
			var path = right_ik.get_path_to(right_target)
			right_ik.set("settings/0/target_node", path)
			print("[SimpleFootIK] Assigned Right IK target path: ", path)
	else:
		push_warning("[SimpleFootIK] ⚠️ right_ik not assigned! IK influence control disabled for right foot.")
		
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
	
	# --- 樓梯偵測（已移除，平地與樓梯統一判斷）---
	
	# ★ 偵測模式切換：移動(A)變成靜止(B)時，snap IK 目標到腳骨
	var entering_standing = not is_moving
	if entering_standing and _was_moving:
		# 從移動/樓梯切換到站立 → 立即 snap IK 目標到當前腳骨位置
		if left_target and _left_foot_idx >= 0:
			left_target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)
		if right_target and _right_foot_idx >= 0:
			right_target.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)
		# snap IK influence 讓目標立即生效
		_current_influence = standing_influence
		_left_foot_phase = 1.0
		_right_foot_phase = 1.0
		if left_ik: left_ik.influence = _current_influence
		if right_ik: right_ik.influence = _current_influence
		# (mode switch snap — 省略 print 以減少 I/O)
		_was_moving = is_moving
		# ★ 這一幀不進入任何模式，讓 snap 生效，下一幀從正確位置開始
		return
	_was_moving = is_moving
	
	# ★★★ 計算動態腳步相位 (Procedural Foot Phase - Height Based) ★★★
	# 原理：直接量測動畫提供的骨骼高度 (相對於 Skeleton)。
	# 如果腳骨高度接近 0.1 (腳踝靜止高度)，代表是在地面 (Planted)。
	# 如果腳骨高度超過 0.25 (抬腳揮桿中)，代表是在空中 (Swinging)。
	var left_cur_y = 0.0
	var right_cur_y = 0.0
	if _left_foot_idx >= 0: left_cur_y = skeleton.get_bone_global_pose(_left_foot_idx).origin.y
	if _right_foot_idx >= 0: right_cur_y = skeleton.get_bone_global_pose(_right_foot_idx).origin.y
	
	_prev_left_y = left_cur_y # 保留變數以防其他地方使用
	_prev_right_y = right_cur_y
	
	# clampf(1.0 - (y - min_height) / range, 0.0, 1.0)
	# min_height = 0.12, max_height = 0.25 -> range = 0.13
	var left_target_phase = clampf(1.0 - (left_cur_y - 0.12) / 0.13, 0.0, 1.0)
	var right_target_phase = clampf(1.0 - (right_cur_y - 0.12) / 0.13, 0.0, 1.0)
	
	# 如果是站立狀態，強制 phase 為 1.0
	if not is_moving:
		left_target_phase = 1.0
		right_target_phase = 1.0
		
	# 平滑過渡 Phase
	_left_foot_phase = lerp(_left_foot_phase, left_target_phase, delta * 15.0)
	_right_foot_phase = lerp(_right_foot_phase, right_target_phase, delta * 15.0)
	
	# ★ 計算兩腳各自的 IK 權重
	var target_base_influence = moving_influence if is_moving else standing_influence
	_current_influence = lerp(_current_influence, target_base_influence, delta * influence_speed)
	
	# 當腳懸空時 (phase=0)，IK 權重為 0，讓動畫完全接管；落地時 (phase=1)，IK 權重為設定值
	# 這裡我們允許設定 moving_influence = 1.0，讓移動時也能開啟 IK
	# ※業界標準：移動時 IK 權重通常在 0.3~1.0 之間
	var final_left_influence = _current_influence * _left_foot_phase
	var final_right_influence = _current_influence * _right_foot_phase
	
	if left_ik: left_ik.influence = final_left_influence
	if right_ik: right_ik.influence = final_right_influence
	
	# ═══ 永遠執行 Ground Detection 和 IK (讓腳能適應階梯) ═══
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = [_char_body.get_rid()] if _char_body else []
	
	var left_ground_res: GroundResult
	var right_ground_res: GroundResult
	
	# ═══ 永遠偵測地面（兩腳都執行，確保數據即時更新）═══
	if _left_foot_idx >= 0:
		left_ground_res = _detect_ground(_left_foot_idx, left_foot_shape, space_state, exclude_rid)
		_left_ground_y = left_ground_res.y
		_left_ground_normal = left_ground_res.normal
	if _right_foot_idx >= 0:
		right_ground_res = _detect_ground(_right_foot_idx, right_foot_shape, space_state, exclude_rid)
		_right_ground_y = right_ground_res.y
		_right_ground_normal = right_ground_res.normal
	
	# --- 骨盆偏移 (盡量只在雙腳都有相位時逐漸生效，避免抖動) ---
	if enable_pelvis_offset and _skeleton_parent:
		var active_phase = max(_left_foot_phase, _right_foot_phase)
		if is_moving:
			_apply_pelvis_offset(delta * 0.5 * active_phase)
		else:
			_apply_pelvis_offset(delta)
			
	# --- IK 目標位置更新 ---
	if left_target and _left_foot_idx >= 0 and left_ground_res:
		_update_ik_target(left_target, _left_foot_idx, _left_hip_idx, left_ground_res, delta)
	if right_target and _right_foot_idx >= 0 and right_ground_res:
		_update_ik_target(right_target, _right_foot_idx, _right_hip_idx, right_ground_res, delta)
	
	# --- 腳掌貼地旋轉 (Ankle Pitch) ---
	# ★ 只在站立時對齊斜面，移動時讓動畫完全控制（避免腳跟先著地+上下身分離）
	if enable_foot_rotation:
		var ankle_weight = 0.0 if is_moving else 1.0
		_apply_ankle_pitch(delta, ankle_weight)
	
	# 除錯繪製
	if debug_draw:
		_draw_debug()


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
	
	if enable_predictive_ik and _char_body:
		var h_vel = Vector3(_char_body.velocity.x, 0, _char_body.velocity.z)
		var h_speed = h_vel.length()
		
		if h_speed > min_prediction_speed:
			if is_stance and was_locked:
				# ★ Stance Phase：使用鎖定的地面位置（不 raycast）
				predict_pos = foot_pos  # 不偏移，用腳骨位置做 raycast
			else:
				# ★ Swing Phase：模擬軌跡預測前方落點
				var swing_factor = 1.0 - foot_phase  # 0=planted, 1=fully swinging
				var predict_time = (prediction_stride_length / h_speed) * swing_factor
				
				var predict_offset = _simulate_trajectory_offset(h_vel, predict_time)
				
				# 限制最大偏移（防急轉彎跳動）
				if predict_offset.length() > max_prediction_offset:
					predict_offset = predict_offset.normalized() * max_prediction_offset
				predict_pos = foot_pos + predict_offset
	
	# 保存 debug 預測點
	if foot_idx == _left_foot_idx:
		_debug_left_predict_pos = predict_pos
	else:
		_debug_right_predict_pos = predict_pos
	
	# ★ 方法一：ShapeCast（球形掃描，更準確）
	if shape_cast:
		# 讓 ShapeCast 跟隨預測位置（而非腳骨位置）
		var parent_node = shape_cast.get_parent()
		if parent_node:
			var local_pos = parent_node.global_transform.affine_inverse() * predict_pos
			# 從預測位置上方 0.3m 開始掃描
			shape_cast.position = Vector3(local_pos.x, local_pos.y + 0.3, local_pos.z)
		
		shape_cast.force_shapecast_update()
		
		if shape_cast.is_colliding():
			# 取最近的碰撞點
			var closest_point = Vector3(0, -INF, 0)
			var closest_normal = Vector3.UP
			for i in shape_cast.get_collision_count():
				var point = shape_cast.get_collision_point(i)
				var normal = shape_cast.get_collision_normal(i)
				if point.y > closest_point.y:
					closest_point = point
					closest_normal = normal
			return GroundResult.new(closest_point, closest_normal)
	
	# ★ 方法二：RayCast 備用（也使用預測位置）
	var ray_start = predict_pos + Vector3.UP * 0.3
	var ray_end = predict_pos + Vector3.DOWN * ray_length
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1
	query.exclude = exclude
	
	var result = space.intersect_ray(query)
	if not result.is_empty():
		return GroundResult.new(result.position, result.normal)
	return GroundResult.new(foot_pos, Vector3.UP) # 沒擊中 → 用動畫位置


## ★ 更新 IK 目標位置（Spring-Damper + 防懸空牽引）
func _update_ik_target(target: Marker3D, foot_idx: int, hip_idx: int, ground_res: GroundResult, delta: float) -> void:
	var bone_global = skeleton.global_transform * skeleton.get_bone_global_pose(foot_idx)
	var foot_pos = bone_global.origin
	
	# 目標 Y = 地面 + 腳踝到腳底的偏移
	var target_y = ground_res.y + foot_height_offset
	
	# 高度差檢查
	var height_diff = target_y - foot_pos.y
	if height_diff < -max_step_down or height_diff > max_step_up:
		# 超出合理範圍 → 平滑回到動畫位置
		target.global_position = target.global_position.lerp(foot_pos, delta * smooth_speed)
		return
	
	# === 邊緣防懸空邏輯 (Edge Anti-Hover) ===
	var target_xz = Vector2(foot_pos.x, foot_pos.z)
	var hit_xz = Vector2(ground_res.pos.x, ground_res.pos.z)
	var xz_dist = target_xz.distance_to(hit_xz)
	if xz_dist > 0.05:
		target_xz = target_xz.lerp(hit_xz, 0.5)
	
	# 目標位置
	var goal_pos = Vector3(target_xz.x, target_y, target_xz.y)
	
	# 距離限制：防止腳延伸超過腿的長度
	if hip_idx >= 0:
		var hip_global = skeleton.global_transform * skeleton.get_bone_global_pose(hip_idx)
		var hip_pos = hip_global.origin
		var dist = goal_pos.distance_to(hip_pos)
		if dist > max_reach_distance:
			goal_pos = goal_pos.lerp(foot_pos, (dist - max_reach_distance) / 0.3)
	
	# ★★★ Phase-Driven Spring-Damper（Phase C 增強）★★★
	# Swing→Stance 過渡時加硬彈簧，讓腳快速到位
	var new_pos: Vector3
	var foot_phase_ik = _left_foot_phase if (foot_idx == _left_foot_idx) else _right_foot_phase
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
		
		if is_left_ik:
			var result = _spring_damper_vec3(_left_spring_pos, _left_spring_vel, goal_pos, delta)
			_left_spring_pos = result[0]
			_left_spring_vel = result[1]
			new_pos = _left_spring_pos
			# ★ 更新 Stance Lock 狀態
			if foot_phase_ik > STANCE_LOCK_THRESHOLD and not _left_stance_locked:
				_left_stance_locked = true
				_left_locked_ground = goal_pos
				_left_locked_normal = _left_ground_normal
				# ★ 關鍵修復：進入 Stance 時清除彈簧殘留速度，防止過沖甩向後方
				_left_spring_vel = Vector3.ZERO
				_left_spring_pos = goal_pos
				new_pos = goal_pos
				# ★ 同步 temporal interpolation，防止 _process 的 lerp 拉回舊位置
				_prev_left_target = goal_pos
				_curr_left_target = goal_pos
			elif foot_phase_ik < SWING_UNLOCK_THRESHOLD:
				_left_stance_locked = false
		else:
			var result = _spring_damper_vec3(_right_spring_pos, _right_spring_vel, goal_pos, delta)
			_right_spring_pos = result[0]
			_right_spring_vel = result[1]
			new_pos = _right_spring_pos
			# ★ 更新 Stance Lock 狀態
			if foot_phase_ik > STANCE_LOCK_THRESHOLD and not _right_stance_locked:
				_right_stance_locked = true
				_right_locked_ground = goal_pos
				_right_locked_normal = _right_ground_normal
				# ★ 關鍵修復：進入 Stance 時清除彈簧殘留速度
				_right_spring_vel = Vector3.ZERO
				_right_spring_pos = goal_pos
				new_pos = goal_pos
				# ★ 同步 temporal interpolation
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
	
	target.global_position = new_pos


# ═══════════════════════════════════════════════════════════════
# ★★★ Predictive IK - 核心工具函數 ★★★
# ═══════════════════════════════════════════════════════════════

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
func _spring_damper_vec3(current: Vector3, velocity: Vector3, target_val: Vector3, dt: float) -> Array:
	# ★ 保護：無效 dt
	if dt <= 0.0001:
		return [current, velocity]
	
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
	
	return [new_pos, new_vel]


## ★★★ Temporal Interpolation：在渲染幀之間插值 IK Target ★★★
## 消除物理幀（固定 60Hz）和渲染幀（可變 FPS）之間的 1 幀延遲抖動
var _temporal_physics_frames: int = 0  # 已經過的物理幀數
var _safe_startup_delay: float = 0.0

func _process(_delta: float) -> void:
	if not skeleton or not left_target or not right_target:
		return
	
	# ★ 防當機策略：必須在 enable_predictive_ik 判斷之前！
	# 不然 enable_predictive_ik=false 時 IK 永遠不會被啟動！
	if _safe_startup_delay < 1.0:
		_safe_startup_delay += _delta
		if _safe_startup_delay >= 0.5 and _left_hip_idx >= 0:
			# 確認骨架已經與臀部骨骼有實質距離（表示骨架已完整載入）
			var l_hip = skeleton.global_transform * skeleton.get_bone_global_pose(_left_hip_idx)
			if left_target.global_position.distance_to(l_hip.origin) > 0.1:
				if left_ik and not left_ik.active: left_ik.active = true
				if right_ik and not right_ik.active: right_ik.active = true
				if left_lookat_modifier and not left_lookat_modifier.active: left_lookat_modifier.active = true
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
	
	# 取得渲染幀在兩個物理步驟之間的比例（0.0 ~ 1.0）
	var frac = Engine.get_physics_interpolation_fraction()
	
	# 在 prev 和 curr 之間線性插值
	left_target.global_position = _prev_left_target.lerp(_curr_left_target, frac)
	right_target.global_position = _prev_right_target.lerp(_curr_right_target, frac)


## ★★★ 腳踝對齊地面法線（直接法線旋轉，不依賴骨骼軸向） ★★★
func _apply_ankle_pitch(delta: float, ankle_weight: float = 1.0) -> void:
	# 左腳
	if _left_foot_idx >= 0:
		_align_foot_to_ground(_left_foot_idx, _left_ground_normal, delta, true, ankle_weight)
	# 右腳
	if _right_foot_idx >= 0:
		_align_foot_to_ground(_right_foot_idx, _right_ground_normal, delta, false, ankle_weight)


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


## 更新 LookAt 目標位置 - 使用地面法線讓腳平行於斜坡
func _update_lookat_targets(delta: float) -> void:
	"""計算並更新 LookAt 目標位置。
	使用地面法線計算腳應該指向的方向，使腳底平行於斜坡表面。"""
	var parent = _char_body
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = [parent.get_rid()] if parent is CharacterBody3D else []
	var char_forward = - parent.global_transform.basis.z if parent else Vector3.FORWARD
	
	# 更新左腳 LookAt 目標
	if left_lookat_target and _left_foot_idx >= 0:
		var left_foot_global = skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)
		var left_foot_pos = left_foot_global.origin
		
		# 在腳下方射線偵測地面法線
		var ray_start = left_foot_pos + Vector3.UP * 0.3
		var ray_end = left_foot_pos + Vector3.DOWN * ray_length
		
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1
		query.exclude = exclude_rid
		var result = space_state.intersect_ray(query)
		
		if not result.is_empty():
			var ground_normal = result.normal
			var ground_point = result.position
			
			# 檢查是否在斜坡上 (法線偏離 UP 的程度)
			var slope_angle = ground_normal.angle_to(Vector3.UP)
			var is_on_slope = slope_angle > 0.05 # 約 3 度以上視為斜坡
			
			if is_on_slope:
				# 在斜坡上：計算沿著斜坡的前進方向
				var slope_forward = char_forward - ground_normal * char_forward.dot(ground_normal)
				slope_forward = slope_forward.normalized()
				
				# LookAt 目標 = 地面點 + 沿斜坡方向的偏移
				var target_pos = ground_point + slope_forward * lookat_forward_offset
				target_pos.y += 0.02 # 微小抬升
				
				left_lookat_target.global_position = left_lookat_target.global_position.lerp(
					target_pos, delta * smooth_speed
				)
			else:
				# 在平地上：目標放在腳的高度，保持腳平
				var target_pos = left_foot_pos + char_forward * lookat_forward_offset
				left_lookat_target.global_position = left_lookat_target.global_position.lerp(
					target_pos, delta * smooth_speed
				)
		else:
			# 沒擊中地面時，保持在腳正前方水平
			var fallback_pos = left_foot_pos + char_forward * lookat_forward_offset
			left_lookat_target.global_position = left_lookat_target.global_position.lerp(
				fallback_pos, delta * smooth_speed
			)
	
	# 更新右腳 LookAt 目標
	if right_lookat_target and _right_foot_idx >= 0:
		var right_foot_global = skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)
		var right_foot_pos = right_foot_global.origin
		
		# 在腳下方射線偵測地面法線
		var ray_start = right_foot_pos + Vector3.UP * 0.3
		var ray_end = right_foot_pos + Vector3.DOWN * ray_length
		
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1
		query.exclude = exclude_rid
		var result = space_state.intersect_ray(query)
		
		if not result.is_empty():
			var ground_normal = result.normal
			var ground_point = result.position
			
			# 檢查是否在斜坡上
			var slope_angle = ground_normal.angle_to(Vector3.UP)
			var is_on_slope = slope_angle > 0.05 # 約 3 度以上視為斜坡
			
			if is_on_slope:
				# 在斜坡上：計算沿著斜坡的前進方向
				var slope_forward = char_forward - ground_normal * char_forward.dot(ground_normal)
				slope_forward = slope_forward.normalized()
				
				var target_pos = ground_point + slope_forward * lookat_forward_offset
				target_pos.y += 0.02
				
				right_lookat_target.global_position = right_lookat_target.global_position.lerp(
					target_pos, delta * smooth_speed
				)
			else:
				# 在平地上：目標放在腳的高度，保持腳平
				var target_pos = right_foot_pos + char_forward * lookat_forward_offset
				right_lookat_target.global_position = right_lookat_target.global_position.lerp(
					target_pos, delta * smooth_speed
				)
		else:
			var fallback_pos = right_foot_pos + char_forward * lookat_forward_offset
			right_lookat_target.global_position = right_lookat_target.global_position.lerp(
				fallback_pos, delta * smooth_speed
			)
	
	# 更新 LookAtModifier 的 influence
	if left_lookat_modifier:
		left_lookat_modifier.influence = _current_influence
	if right_lookat_modifier:
		right_lookat_modifier.influence = _current_influence
	
	# 診斷輸出 - 顯示 LookAt 目標位置
	if Engine.get_process_frames() % 60 == 0:
		var left_pos = left_lookat_target.global_position if left_lookat_target else Vector3.ZERO
		var right_pos = right_lookat_target.global_position if right_lookat_target else Vector3.ZERO
		print("[LookAt] L=(%.2f, %.2f, %.2f) R=(%.2f, %.2f, %.2f)" % [
			left_pos.x, left_pos.y, left_pos.z,
			right_pos.x, right_pos.y, right_pos.z
		])


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


func _rotate_foot_bone(bone_idx: int, pitch: float, normal: Vector3, delta: float) -> void:
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
	
	var body_y = parent.global_position.y
	
	var lowest_ground = min(_left_ground_y, _right_ground_y)
	var highest_ground = max(_left_ground_y, _right_ground_y)
	
	# 如果其中一隻腳沒有有效偵測到地面 (例如極端懸空為 0.0, body_y=0.6)，我們要避免因此造成骨盆暴跌。
	# 我們計算 lower 和 higher 的 deficit。
	var needed_offset = lowest_ground - body_y
	
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
	"""繪製除錯視覺化 - 使用 DebugDraw3D 或 print 輸出"""
	# 使用快取的 singleton（在 _ready 中初始化）
	var dd = _debug_draw_3d
	if dd:
		# 左腳 raycast (綠色)
		dd.draw_line(_debug_left_ray_start, _debug_left_ray_end, Color.GREEN)
		if _debug_left_hit:
			dd.draw_sphere(_debug_left_ground, 0.05, Color.GREEN)
		if left_target:
			dd.draw_sphere(left_target.global_position, 0.03, Color.LIME)
		
		# 右腳 raycast (藍色)
		dd.draw_line(_debug_right_ray_start, _debug_right_ray_end, Color.CYAN)
		if _debug_right_hit:
			dd.draw_sphere(_debug_right_ground, 0.05, Color.CYAN)
		if right_target:
			dd.draw_sphere(right_target.global_position, 0.03, Color.AQUA)
		
		# 骨盆偏移指示 (黃色)
		if skeleton:
			var pelvis_pos = skeleton.global_position
			dd.draw_line(pelvis_pos, pelvis_pos + Vector3.DOWN * abs(_current_pelvis_offset), Color.YELLOW)
		
		# ★ Phase-Driven Predictive IK 預測點
		if enable_predictive_ik:
			# 預測點：stance=綠色(鎖定), swing=紅色(預測中), 過渡=橙色(落地中)
			var l_color = Color.GREEN if _left_stance_locked else (Color.ORANGE if _left_foot_phase > 0.4 else Color.RED)
			var r_color = Color.GREEN if _right_stance_locked else (Color.ORANGE if _right_foot_phase > 0.4 else Color.RED)
			dd.draw_sphere(_debug_left_predict_pos, 0.04, l_color)
			dd.draw_sphere(_debug_right_predict_pos, 0.04, r_color)
			# 預測方向線（stance 時短線，swing 時長線）
			if left_target:
				dd.draw_line(left_target.global_position, _debug_left_predict_pos, l_color)
			if right_target:
				dd.draw_line(right_target.global_position, _debug_right_predict_pos, r_color)
			# ★ Phase 數值標記（在腳骨上方顯示 L/R）
			if skeleton and _left_foot_idx >= 0:
				var lf_pos = (skeleton.global_transform * skeleton.get_bone_global_pose(_left_foot_idx)).origin
				dd.draw_sphere(lf_pos + Vector3.UP * 0.15, 0.02, l_color)
			if skeleton and _right_foot_idx >= 0:
				var rf_pos = (skeleton.global_transform * skeleton.get_bone_global_pose(_right_foot_idx)).origin
				dd.draw_sphere(rf_pos + Vector3.UP * 0.15, 0.02, r_color)
	else:
		# 沒有 DebugDraw3D，每隔一段時間輸出文字
		if Engine.get_process_frames() % 30 == 0:
			print("[FootIK Debug] L_hit=%s L_ground=%.2f | R_hit=%s R_ground=%.2f | Pelvis=%.3f" % [
				_debug_left_hit, _debug_left_ground.y if _debug_left_hit else 0.0,
				_debug_right_hit, _debug_right_ground.y if _debug_right_hit else 0.0,
				_current_pelvis_offset
			])
