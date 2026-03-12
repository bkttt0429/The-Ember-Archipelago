extends CharacterBody3D
## 移動 + 動畫 + 相機控制
## 使用純條件控制 AnimationTree StateMachine
## 完全不用 start() 或 travel()

@export_group("Movement Data")
@export var movement_data: MovementData ## 移動參數資源（速度/加速度/跳躍/轉向）
@export var mouse_sensitivity: float = 0.003

@export_group("Slope Traversal")
## 最大可行走斜坡角度（度）— 預設 Godot 45° 太小，55° 覆蓋大多數遊戲斜坡
@export var slope_max_angle_deg: float = 55.0
## 地板吸附距離 — 越大越能貼住斜坡（預設 Godot 0.1 太小）
@export var slope_snap_length: float = 0.3

@export_group("IK Debug")
@export var disable_ik_code: bool = true ## ★ 禁用內部 IK，完全交給外部的 SimpleFootIK 處理

@export_group("Debug")
## ★ 開啟後才會輸出 >>> 開頭的 debug print（預設關閉減少 I/O）
@export var verbose_debug: bool = false

@export_group("Animation")
# 自動找到 AnimationTree (不用在 Inspector 設定)
@onready var anim_tree: AnimationTree = $AnimationTree
# AnimationPlayer 引用 - 用於繞過 BlendTree 狀態機限制直接播放跳躍動畫
@onready var anim_player: AnimationPlayer = $AnimationPlayer

@export_group("Camera")
# ★ PhantomCamera3D 第三人稱模式
@export var cam_mouse_sensitivity: float = 0.05
@export var cam_min_pitch: float = -60.0
@export var cam_max_pitch: float = 50.0

# PhantomCamera 引用（場景中需要 %PlayerPhantomCamera3D 和 %MainCamera）
var _pcam: Node = null # PhantomCamera3D
var _main_camera: Camera3D = null # MainCamera（被 PhantomCameraHost 控制）

@export_group("Ground Detection")
@onready var ground_ray: RayCast3D = $GroundRay
@export var ground_check_distance: float = 1.2 # 地面檢測距離

# 視覺模型引用（用於鎖定 Root Motion）
@onready var visuals_node: Node3D = $Visuals/Human
@onready var skeleton: Skeleton3D = null # 動態查找，見 _ready()

# 地面資訊
# ==================== State Structs (Phase 2 Data Driven) ====================
class GroundData:
	var info: Dictionary = {"is_grounded": false, "surface_normal": Vector3.UP, "collision_point": Vector3.ZERO, "distance": 0.0, "collider": null}
	var was_on_floor: bool = true
	var step_down_snapped: bool = false
	var snapped_to_stairs_last_frame: bool = false

class AirData:
	var air_time: float = 0.0
	var fall_velocity_peak: float = 0.0
	var landing_timer: float = 0.0
	var post_landing_blend_timer: float = 0.0
	var coyote_timer: float = 0.0
	var jump_grace_timer: float = 0.0
	var jump_buffer_timer: float = 0.0
	var jump_hold_timer: float = 0.0
	var jump_start_timer: float = 0.0
	var jump_phase: int = 0
	var is_ascending: bool = false
	var jump_to_type: int = 0

class StairData:
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

class ClimbData:
	var state: int = 0
	var grab_point: Vector3 = Vector3.ZERO
	var surface_normal: Vector3 = Vector3.FORWARD
	var ledge_height: float = 0.0
	var mantle_root_motion_active: bool = false
	var mantle_start_pos: Vector3 = Vector3.ZERO
	var mantle_target_y: float = 0.0
	var mantle_height_compensation: float = 0.0
	var mantle_elapsed: float = 0.0
	var mantle_duration: float = 1.0
	var mantle_wall_point: Vector3 = Vector3.ZERO
	var mantle_rm_loaded: bool = false
	var wall_point: Vector3 = Vector3.ZERO
	var is_shimmying: bool = false
	var shimmy_direction: int = 0
	var shimmy_target_pos: Vector3 = Vector3.ZERO

class AnimState:
	var gait: MovementEnums.Gait = MovementEnums.Gait.WALK
	var motion_state: MovementEnums.MotionState = MovementEnums.MotionState.IDLE

# ==================== Phase 3: Hierarchical State Machine (HSM) ====================
class PlayerState:
	var player: Node # Reference to CharacterBody3D (SimpleCapsuleMove)
	func _init(p: Node) -> void: player = p
	func enter(_msg: Dictionary = {}) -> void: pass
	func exit() -> void: pass
	func physics_update(_delta: float) -> void: pass
	func update(_delta: float) -> void: pass

class StateMachine:
	var states: Dictionary = {}
	var current_state: PlayerState = null
	
	func init_machine(initial_state: String) -> void:
		if states.has(initial_state):
			current_state = states[initial_state]
			current_state.enter()
			
	func physics_update(delta: float) -> void:
		if current_state: current_state.physics_update(delta)
		
	func update(delta: float) -> void:
		if current_state: current_state.update(delta)
		
	func change_state(new_state: String, msg: Dictionary = {}) -> void:
		if not states.has(new_state) or current_state == states[new_state]: return
		if current_state: current_state.exit()
		current_state = states[new_state]
		current_state.enter(msg)

class StateGround extends PlayerState:
	## 統一地面/空中/樓梯物理 — 保留原本 StateNormal 的完整流程
	## 子系統（重力、樓梯、跳躍）有深度交叉依賴，
	## 必須在同一幀內按順序全部執行，不可用 early-return 拆分。
	func physics_update(delta: float) -> void:
		var p = player
		if p.climb.state != p.ClimbState.NONE:
			p._fsm.change_state("climb")
			return
		
		p._update_ground_info()
		p._process_first_frame_init()
		p._print_frame_debug()
		
		p._gather_input()
		p._process_test_keys()
		
		p._process_timers_and_fall(delta)
		p._process_jump_system(delta)
		
		# 重力（跟原版一致：不在地面、不停止、不在上樓梯時施加）
		if not p.is_on_floor() and not p._is_stopping and not (p.stair.on_stairs and p.stair.ascending):
			p.velocity.y -= p.movement_data.gravity * delta
		
		p._process_ledge_grab()
		if p.climb.state != p.ClimbState.NONE:
			p._fsm.change_state("climb")
			return
		
		p._process_horizontal_movement(delta)
		
		# ══════ 物理管線（明確執行順序，move_and_slide 只在這裡呼叫一次） ══════
		# Step 1: 偵測樓梯
		p._detect_stairs()
		
		# Step 2: 樓梯上升時壓制正 Y 速度
		p.stair.step_up_offset = 0.0
		if p.stair.on_stairs and p.stair.ascending and not p._is_jumping:
			p.velocity.y = min(p.velocity.y, 0.0)
		
		# Step 3: SnapUp（跨上台階）
		if p.movement_data.step_enabled and not p._is_jumping and not p._is_landing:
			if p.is_on_floor() or p.ground.snapped_to_stairs_last_frame or (p.stair.on_stairs and p.stair.ascending):
				p._snap_up_stairs_check(delta)
		
		# Step 4: ★ move_and_slide() — 唯一一處 ★
		var saved_snap = p.floor_snap_length
		if (p.stair.on_stairs and p.stair.ascending) or p.ground.snapped_to_stairs_last_frame:
			p.floor_snap_length = 1.0
		var pre_y = p.global_position.y
		p.move_and_slide()
		p.floor_snap_length = saved_snap
		var post_mas_y = p.global_position.y
		
		# Step 5: SnapDown（跨下台階）
		p._snap_down_stairs_check()
		var post_sd_y = p.global_position.y
		
		# Step 6: 落地偵測
		if p.air.jump_grace_timer <= 0 and not p.ground.was_on_floor and p.is_on_floor():
			if (p.air.jump_phase == p.JumpPhase.LOOP or p._is_falling or p._is_jumping) and p.air.jump_to_type != p.JumpToType.TO_STAGE:
				p._set_motion_state(MovementEnums.MotionState.LANDING)
				p.air.landing_timer = p.LAND_ANIMATION_DURATION
				p._trigger_land_animation()
			p.air.air_time = 0.0
			p.air.fall_velocity_peak = 0.0
		
		# Step 7: Debug 紀錄
		if p.stair.on_stairs and p.stair.ascending:
			var md = post_mas_y - pre_y
			var sd = post_sd_y - post_mas_y
			if abs(md) > 0.005 or abs(sd) > 0.005:
				if p.verbose_debug: print(">>> [PhysDelta] pre=%.3f →MAS→ %.3f (Δ%.3f) →SD→ %.3f (Δ%.3f) step_up=%.3f snapped=%s" % [pre_y, post_mas_y, md, post_sd_y, sd, p.stair.step_up_offset, p.ground.snapped_to_stairs_last_frame])
		# ══════ 物理管線結束 ══════
		
		p._update_stair_animation(delta)
		if p.stair.step_up_offset <= 0.0:
			p._snap_to_foot_ground(delta)
		p._apply_realistic_movement(p._move_dir, delta)
		
		p._process_stop_animation(delta)
		p._check_footsteps()
		p._process_physics_fallback_stop()
		p._update_animation_conditions(p._is_moving_frame, p.is_on_floor())
		p._process_blendspace(delta)
		p._process_stopping_interrupt()
		p._draw_stair_debug()

class StateClimb extends PlayerState:
	func physics_update(delta: float) -> void:
		var p = player
		if p.climb.state == p.ClimbState.NONE:
			p._fsm.change_state("ground")
			return
			
		p._process_hanging_input(delta)
		if p.climb.state == p.ClimbState.CLIMBING_UP and p.climb.mantle_root_motion_active:
			p._process_root_motion_mantle(delta)
			return
		if p.climb.state == p.ClimbState.HANGING:
			return

var _fsm := StateMachine.new()
# ===================================================================================

var ground := GroundData.new()
var air := AirData.new()
var stair := StairData.new()
var climb := ClimbData.new()
var state_anim := AnimState.new()
# =============================================================================

# Internal state
# ★ Enum 狀態機（取代分散的 bool 旗標）
# REMOVED_BY_REFACTOR: var _motion_state: MovementEnums.MotionState = MovementEnums.MotionState.IDLE
# REMOVED_BY_REFACTOR: var _gait: MovementEnums.Gait = MovementEnums.Gait.WALK
# REMOVED_BY_REFACTOR: var _coyote_timer: float = 0.0
# REMOVED_BY_REFACTOR: var _was_on_floor: bool = true
# REMOVED_BY_REFACTOR: var _step_down_snapped: bool = false # ★ step-down snap 後強制下幀視為在地面
# REMOVED_BY_REFACTOR: var _snapped_to_stairs_last_frame: bool = false # ★ 上幀是否有執行 stair snap（用於連續步進）

# ★ Phase-Aware Foot IK（階段 2：骨骼速度偵測 stance/swing）
var _prev_right_foot_y: float = 0.0
var _prev_left_foot_y: float = 0.0
var _right_foot_phase_weight: float = 1.0 # 1.0=著地相, 0.0=擺動相
var _left_foot_phase_weight: float = 1.0

# ★ 階梯投影系統（Stair Projection）— 解析式腳步 Y 計算
# REMOVED_BY_REFACTOR: var _stair_step_height_measured: float = 0.25 # 量測的單階高度（running average）
# REMOVED_BY_REFACTOR: var _stair_step_depth: float = 0.3 # 量測的單階深度
# REMOVED_BY_REFACTOR: var _stair_base_pos: Vector3 = Vector3.ZERO # 階梯基準點（第一個 hit）
# REMOVED_BY_REFACTOR: var _stair_dir_xz: Vector2 = Vector2.ZERO # 階梯方向（XZ 平面，normalized）
# REMOVED_BY_REFACTOR: var _stair_params_valid: bool = false # 階梯參數是否有效

# ★ Foot Locking 系統 — 著地時鎖定 IK target 的完整世界座標，擺動時釋放
var _right_foot_locked: bool = false
var _left_foot_locked: bool = false
var _locked_right_step_y: float = 0.0 # 鎖定的右腳台階 Y（保留向後相容）
var _locked_left_step_y: float = 0.0 # 鎖定的左腳台階 Y（保留向後相容）
var _locked_right_world_pos: Vector3 = Vector3.ZERO # ★ 鎖定的右腳完整世界座標
var _locked_left_world_pos: Vector3 = Vector3.ZERO # ★ 鎖定的左腳完整世界座標
var _foot_lock_timer: float = 0.0 # ★ 鎖定計時器（防止快速交換）
const MIN_FOOT_LOCK_DURATION: float = 0.25 # ★ 最少鎖定時間（秒）
var _prev_right_foot_vel_y: float = 0.0 # 上幀右腳 Y 速度（鎖定偵測用）
var _prev_left_foot_vel_y: float = 0.0 # 上幀左腳 Y 速度

# ★ 階梯投影 Debug 可視化
var _stair_debug_enabled: bool = false # F4 切換
var _stair_debug_mesh: MeshInstance3D = null
var _stair_debug_imm: ImmediateMesh = null
var _stair_debug_mat: StandardMaterial3D = null

# ═══════════ PredictIK 預測式樓梯 IK 子系統 — 精確移植自 PredictIK.cs ═══════════
const PREDICT_STEP_LENGTH := 0.6 # StepLength — 一步前進距離
const PREDICT_STEP_HEIGHT := 0.4 # StepHeight — 抬腿偵測高度
const PREDICT_DAMP_TIME := 0.1 # damptime — 重心 SmoothDamp 時間
const PREDICT_OFFSET_SCALE := 0.1 # offsetScale — 坡度重心偏移

# AnimationCurve → 分段線性 [{"d": float, "h": float}]
var _predict_right_curve: Array = []
var _predict_left_curve: Array = []
# LastLeftPosition / LastRightPosition (原始碼: StepPerdict 返回的 start_point)
var _predict_last_left_pos: Vector3 = Vector3.ZERO
var _predict_last_right_pos: Vector3 = Vector3.ZERO
# LastBipHeight
var _predict_last_bip_height: float = 0.0
# SmoothDamp velocity ref
var _predict_bip_vel: float = 0.0
# LeftCurveTangent / RightCurveTangent (坡度)
var _predict_left_tangent: float = 0.0
var _predict_right_tangent: float = 0.0
# 系統狀態
var _predict_ik_active: bool = false
var _predict_prev_right_locked: bool = false
var _predict_prev_left_locked: bool = false
var _predict_initialized: bool = false
var _predict_prev_root_y: float = 0.0 # 上幀 root Y，用于補償 CharacterBody3D 爬樓導致的參照系偏移

# Jump state
# REMOVED_BY_REFACTOR: var _jump_buffer_timer: float = 0.0 # 跳躍緩衝計時器
# REMOVED_BY_REFACTOR: var _is_ascending: bool = false # 是否在跳躍上升階段
# _is_jumping 已遷移到 state_anim.motion_state == MotionState.JUMPING
# REMOVED_BY_REFACTOR: var _jump_hold_timer: float = 0.0 # 跳躍保持計時器
# REMOVED_BY_REFACTOR: var _jump_grace_timer: float = 0.0 # 起跳保護計時器 (防止 Frame-Perfect Cut-off)

# 跳躍動畫階段
enum JumpPhase {NONE, START, LOOP, LAND}
# REMOVED_BY_REFACTOR: var _jump_phase: JumpPhase = JumpPhase.NONE
# REMOVED_BY_REFACTOR: var _jump_start_timer: float = 0.0 # 起跳動畫計時器
const JUMP_START_DURATION: float = 0.25 # 起跳動畫播放時間（加速播放）

# Fall state (用於長時間下落和重落地)
# REMOVED_BY_REFACTOR: var _air_time: float = 0.0 # 離地時間
# _is_falling 已遷移到 state_anim.motion_state == MotionState.FALLING
# REMOVED_BY_REFACTOR: var _fall_velocity_peak: float = 0.0 # 下落速度峰值 (用於判斷重落地)
const FALL_TRIGGER_TIME: float = 0.4 # 離地多久觸發下落動畫
const HARD_LAND_VELOCITY: float = 10.0 # 觸發重落地的速度閾值
const LAND_ANIMATION_DURATION: float = 0.3 # 落地動畫持續時間（禁用 IK）
const POST_LANDING_BLEND_DURATION: float = 0.3 # ★ 落地後快速淡入期（高速 IK 平滑）
# REMOVED_BY_REFACTOR: var _landing_timer: float = 0.0 # 落地計時器
# REMOVED_BY_REFACTOR: var _post_landing_blend_timer: float = 0.0 # ★ 落地後淡入計時器
var _test_h_pressed: bool = false # 測試 H 鍵狀態
var _test_g_pressed: bool = false # 測試 G 鍵狀態
var _test_g_start_pos: Vector3 = Vector3.ZERO # G 動畫起始位置

# 分段跳躍動畫 (使用新匯入的 HumanM@Jump01)
const JUMP_START_ANIM: String = "Jump01_Start" # 起跳動畫
const JUMP_LOOP_ANIM: String = "Fall01_Loop" # 空中循環
const JUMP_LAND_ANIM: String = "Jump01_Land" # 落地動畫
const JUMP_TO_STAGE_ANIM: String = "Jump_ToStage" # 跳上平台動畫
const JUMP_FROM_STAGE_ANIM: String = "Falling_To_Landing" # 跳下平台動畫

# 攀爬動畫 (Climb 資料夾匯入)
const HANG_IDLE_ANIM: String = "Hanging_Idle" # 懸掛待機
const HANG_TO_CROUCH_ANIM: String = "Hang_To_Crouch" # 攀上蹲下 (Mantle)
const HANG_DROP_ANIM: String = "Hang_Drop" # 放手下落
const SHIMMY_LEFT_ANIM: String = "Shimmy_Left" # 左移
const SHIMMY_RIGHT_ANIM: String = "Shimmy_Right" # 右移

# 平台偵測參數 (業界標準)
const MIN_PLATFORM_HEIGHT: float = 0.3 # 最低平台高度 (30cm，太矮不觸發)
const MAX_PLATFORM_HEIGHT: float = 1.0 # 最高平台高度 = Obstacle 高度 (1m)
const FORWARD_DETECT_RANGE: float = 1.5 # 前方偵測距離

# 跳躍類型
enum JumpToType {NORMAL, TO_STAGE, FROM_STAGE}
var _detected_platform_pos: Vector3 = Vector3.ZERO # 偵測到的平台位置
var _detected_drop_pos: Vector3 = Vector3.ZERO # 偵測到的落點位置
# REMOVED_BY_REFACTOR: var _jump_to_type: JumpToType = JumpToType.NORMAL

# ==================== 攀爬系統 ====================
# 攀爬狀態枚舉
enum ClimbState {
	NONE, # 正常狀態
	GRABBING, # 正在抓握動畫
	HANGING, # 懸掛中
	CLIMBING_UP, # 攀上中 (Mantle)
	DROPPING # 放手下落
}

# 攀爬偵測參數
const CLIMB_WALL_DETECT_DIST: float = 0.6 # 牆面偵測距離
const CLIMB_GRAB_HEIGHT_MIN: float = 1.5 # 最低抓握高度 (角色腳底算起)
const CLIMB_GRAB_HEIGHT_MAX: float = 2.8 # 最高抓握高度
const CLIMB_LEDGE_DEPTH_MIN: float = 0.2 # 邊緣最小深度

# 攻爠狀態變數
# REMOVED_BY_REFACTOR: var _climb_state: ClimbState = ClimbState.NONE
# REMOVED_BY_REFACTOR: var _climb_grab_point: Vector3 = Vector3.ZERO # 抓握點世界座標
# REMOVED_BY_REFACTOR: var _climb_surface_normal: Vector3 = Vector3.FORWARD # 牆面法線
# REMOVED_BY_REFACTOR: var _climb_ledge_height: float = 0.0 # 邊緣高度

# ★ Root Motion Mantle 變數
# REMOVED_BY_REFACTOR: var _mantle_root_motion_active: bool = false # Root Motion 是否啟用中
# REMOVED_BY_REFACTOR: var _mantle_start_pos: Vector3 = Vector3.ZERO # Mantle 開始位置
# REMOVED_BY_REFACTOR: var _mantle_target_y: float = 0.0 # 目標 Y 高度（邊緣上方）
# REMOVED_BY_REFACTOR: var _mantle_height_compensation: float = 0.0 # 高度補償（牆高 - 動畫內建高度）
# REMOVED_BY_REFACTOR: var _mantle_elapsed: float = 0.0 # 已經過時間
# REMOVED_BY_REFACTOR: var _mantle_duration: float = 1.0 # 動畫總時長
# REMOVED_BY_REFACTOR: var _mantle_wall_point: Vector3 = Vector3.ZERO # 牆面碰撞點（用於距離約束）
const MANTLE_ANIM_CLIMB_HEIGHT: float = 2.0 # ★ 動畫內建攀爬高度（需根據實際動畫調整）
const MANTLE_MIN_WALL_DIST: float = 0.25 # ★ 角色到牆面的最小距離（防穿牆）
const MANTLE_RM_FBX_PATH: String = "res://Player/assets/characters/player/motion/mx/Climb/Braced Hang To Crouch.fbx"
const MANTLE_RM_ANIM_LIB: String = "mantle_rm" # Root Motion 動畫庫名稱
const MANTLE_RM_ANIM_NAME: String = "Hang_To_Crouch_RM" # Root Motion 動畫名稱
# REMOVED_BY_REFACTOR: var _mantle_rm_loaded: bool = false # 是否已載入 RM 動畫
# REMOVED_BY_REFACTOR: var _climb_wall_point: Vector3 = Vector3.ZERO # 牆面碰撞點

# Shimmy (橫向移動) 參數
const SHIMMY_SPEED: float = 0.8 # Shimmy 移動速度 (米/秒)
const SHIMMY_LEDGE_CHECK_DIST: float = 0.5 # 側向邊緣檢測距離
# REMOVED_BY_REFACTOR: var _is_shimmying: bool = false # 是否正在 shimmy
# REMOVED_BY_REFACTOR: var _shimmy_direction: int = 0 # -1 = 左, 1 = 右
# REMOVED_BY_REFACTOR: var _shimmy_target_pos: Vector3 = Vector3.ZERO # shimmy 目標位置

# ★ Step-Up 樓梯攀爬 (Root Motion 版)
# ★ 使用帶有真正 Root Motion (Y+Z) 的 FBX 動畫
const STAIR_WALK_ASCEND_FBX := "res://Player/assets/characters/player/motion/mx/stairs/Walking Up The Stairs.fbx"
const STAIR_DESCEND_FBX := "res://Player/assets/characters/player/motion/mx/stairs/Descending Stairs (1).fbx"
const STAIR_RUN_ASCEND_FBX := "res://Player/assets/characters/player/motion/mx/stairs/Running Up Stairs.fbx"
const STAIR_ANIM_LIB := "stairs"
const STAIR_ASCEND_ANIM := "Walking_Up_Stairs" # 走路上樓 (Root Motion Y+Z)
const STAIR_DESCEND_ANIM := "Descending_Stairs" # 走路下樓 (Root Motion Y+Z)
const STAIR_RUN_ASCEND_ANIM := "Running_Up_Stairs" # 跑步上樓 (Root Motion Y+Z)
const STAIR_RUN_SPEED_THRESHOLD := 4.5 # 超過此速度切換到跑步上樓動畫 (m/s)
# ★ Root Motion 動畫內建速度（從 FBX 分析結果算出）
const STAIR_RM_WALK_H_SPEED := 0.409 # Walking Up The Stairs: Z=49cm/1.2s = 0.409 m/s
const STAIR_RM_RUN_H_SPEED := 0.843 # Running Up Stairs: Z=50.6cm/0.6s = 0.843 m/s
const STAIR_RM_DESCEND_H_SPEED := 0.479 # Descending Stairs (1): Z=44.7cm/0.933s = 0.479 m/s
const STAIR_MIN_IK_PHASE := 0.3 # ★ 樓梯上 swing 相位最低 IK 權重
# REMOVED_BY_REFACTOR: var _on_stairs: bool = false
# REMOVED_BY_REFACTOR: var _stairs_ascending: bool = true # true=上樓, false=下樓
# REMOVED_BY_REFACTOR: var _stair_grace_timer: float = 0.0 # ★ 寬限計時器：防止 _on_stairs 單幀閃爍
# REMOVED_BY_REFACTOR: var _stair_blend_weight: float = 0.0
# REMOVED_BY_REFACTOR: var _stair_anim_exit_timer: float = 0.0 # ★ 動畫退出寬限計時器
var _stair_anims_loaded: bool = false
var _stair_run_anim_loaded: bool = false # 跑步上樓動畫是否載入
var _stair_anim_prefix: String = "stairs" # 動態設定："movement" 或 "stairs"
# REMOVED_BY_REFACTOR: var _stair_root_motion_active: bool = false # ★ Root Motion 是否正在驅動移動
# REMOVED_BY_REFACTOR: var _stair_rm_velocity: Vector3 = Vector3.ZERO # ★ 從 root motion 提取的速度
# REMOVED_BY_REFACTOR: var _step_up_offset: float = 0.0
# REMOVED_BY_REFACTOR: var _post_step_up_cooldown: int = 0 # step-up 後禁用 floor_snap 的幀數
# REMOVED_BY_REFACTOR: var _step_up_visual_debt: float = 0.0 # ★ 視覺補優值（非樓梯用）
var _cam_follow_target: Marker3D = null # ★ 平滑相機跟隨目標
var _cam_smooth_y: float = 0.0 # ★ 平滑後的 Y 座標
var _smooth_visual_y: float = 0.0 # ★ 絕對平滑 Y（樓梯上用，不累積）
# REMOVED_BY_REFACTOR: var _was_on_stairs_ascending: bool = false # ★ 上一幀是否在上樓梯
# ★★★ 動畫方向 Commit：防止 ascending↔descending 快速切換（0.5秒 debounce）
# REMOVED_BY_REFACTOR: var _stair_dir_committed: bool = false # 是否已提交方向
# REMOVED_BY_REFACTOR: var _stair_committed_ascending: bool = true # 已提交的方向（true=上, false=下）
# REMOVED_BY_REFACTOR: var _stair_dir_commit_timer: float = 0.0 # 計時器（倒數到 0 才允許切換）
const STAIR_STEP_HEIGHT := 0.25 # 每階台階高度 (m)
const STAIR_ASCEND_Y_PER_SEC := 0.3437
const STAIR_DESCEND_Y_PER_SEC := 0.5282

# 平台偵測射線節點
@onready var platform_forward_ray: RayCast3D = $PlatformForwardRay
@onready var platform_up_ray: RayCast3D = $PlatformUpRay
@onready var platform_land_ray: RayCast3D = $PlatformLandRay

# Two Bone IK for foot placement (需要在場景中手動添加)
var right_leg_ik: Node = null # TwoBoneIK3D
var left_leg_ik: Node = null # TwoBoneIK3D
var right_foot_target: Marker3D = null
var left_foot_target: Marker3D = null
var _ik_blend_weight: float = 0.0
var _ankle_modifier: AnkleAlignModifier3D = null # ★ 腳踝對齊修正器
var _foot_ik_system: SimpleFootIK = null # ★ 外部 SimpleFootIK 節點

# ★ Hand IK for climbing (手部錨定到邊緣)
var right_arm_ik: Node = null # TwoBoneIK3D (如果存在)
var left_arm_ik: Node = null # TwoBoneIK3D (如果存在)
var right_hand_target: Marker3D = null
var left_hand_target: Marker3D = null
var right_elbow_pole: Marker3D = null # ★ Pole Node for elbow direction
var left_elbow_pole: Marker3D = null # ★ Pole Node for elbow direction
var _hand_ik_enabled: bool = false # 手部 IK 是否啟用
var _right_arm_ik_weight: float = 0.0 # ★ 右手 IK 權重（跟腳部 IK 同樣模式）
var _left_arm_ik_weight: float = 0.0 # ★ 左手 IK 權重
const ARM_IK_MAX_INFLUENCE: float = 1.0 # ★ 手部 IK 最大權重（全 IK，手必須到邊緣，自然感由 pole 控制）
const HAND_OFFSET_FROM_EDGE: float = 0.02 # ★ 手在邊緣下方的偏移（幾乎貼齊邊緣頂部）
const HAND_HORIZONTAL_SPREAD: float = 0.35 # 左右手水平間距
const ELBOW_POLE_DROP: float = 0.7 # ★ Pole 在手下方的偏移（讓手肘自然朝下）
const ELBOW_POLE_TOWARD_BODY: float = 0.2 # ★ Pole 往身體中心的偏移（讓手肘略微向內）
const ELBOW_POLE_OUTWARD: float = 0.15 # ★ Pole 往外側的偏移（讓手肘不會完全貼身）

# ★ Head Look-At（頭部追蹤攝影機方向）
var _head_look_at: Node = null # LookAtModifier3D
var _head_look_target: Marker3D = null # HeadLookAtTarget
var _head_influence: float = 0.0
const HEAD_LOOK_SPEED: float = 5.0 # influence 漸變速度
const HEAD_LOOK_DISTANCE: float = 3.0 # 目標在前方的距離

# ★ 腳部 ShapeCast3D（球形碰撞體，比 RayCast3D 更準確）
var _right_foot_ray: ShapeCast3D = null
var _left_foot_ray: ShapeCast3D = null

# Turn in place state
var _is_turning: bool = false # 是否正在轉身
var _turn_direction: int = 0 # -1 = 左轉, 1 = 右轉, 0 = 不轉
var _turn_target_angle: float = 0.0 # 目標轉向角度
var _turn_remaining: float = 0.0 # 剩餘轉向角度
var _accumulated_rotation: float = 0.0 # 累積相機旋轉角度
const TURN_THRESHOLD: float = 70.0 # 超過此角度觸發轉身動畫 (度)

# Run to Stop (減速停止動畫)
const RUN_TO_STOP_ANIM: String = "Run_To_Stop"
const RUN_TO_STOP_SPEED_THRESHOLD: float = 2.0 # 從多快開始算移動（走路~2m/s，跑步~8m/s）
var _prev_h_speed: float = 0.0 # 上一幀水平速度
# _is_stopping 已遷移到 state_anim.motion_state == MotionState.STOPPING
var _stopping_timer: float = 0.0 # 停止動畫計時器
var _stopping_hips_pos: Vector3 = Vector3.ZERO # 停止動畫開始時的 Hips 位置
var _stopping_anim_name: String = "" # 當前停止動畫名稱
var _stopping_grace_timer: float = 0.0 # 停止動畫保護期（防止立即被取消）
var _stopping_rotation: float = 0.0 # 停止動畫時的角色旋轉（防止動畫重置方向）

# 腳步追蹤（動畫事件觸發）
var _last_foot: String = "left" # 最後著地的腳 ("left" 或 "right")
var _foot_grounded_time: float = 0.0 # 上次腳著地的時間
var _waiting_for_foot: bool = false # 等待腳著地後停止

# ★ Foot Locking / Foot Planting（過渡動畫腳部穩定）
var _foot_lock_active: bool = false # 是否啟用腳部鎖定
var _foot_lock_blend: float = 0.0 # 鎖定混合權重 (0=最低 IK, 1=正常 IK)
var _foot_lock_tween: Tween = null # 儲存 Tween 引用，避免重複
var _foot_lock_duration: float = 0.5 # 鎖定淡出時間

# ★ 腳部位置鎖定（過渡時防止「跳躍」感）
var _locked_left_foot_pos: Vector3 = Vector3.ZERO # 鎖定的左腳世界位置
var _locked_right_foot_pos: Vector3 = Vector3.ZERO # 鎖定的右腳世界位置
var _left_foot_bone_idx: int = -1 # 左腳骨骼索引（快取）
var _right_foot_bone_idx: int = -1 # 右腳骨骼索引（快取）
var _transition_foot_lock_active: bool = false # 過渡腳部鎖定是否啟用
var _transition_foot_lock_time: float = 0.0 # 過渡腳部鎖定計時

# ★ 最小移動時間（確保看到至少一步）
const MIN_MOVE_TIME: float = 0.4 # 最小移動時間（秒）- 大約一步的時間
var _move_start_time: float = 0.0 # 開始移動的時間
var _is_moving_input: bool = false # 是否有移動輸入

# ★ 速度曲線狀態
var _curve_time: float = 0.0 # 曲線進度時間
var _curve_start_velocity: Vector3 = Vector3.ZERO # 曲線開始時的速度
var _curve_target_velocity: Vector3 = Vector3.ZERO # 曲線目標速度
var _is_accelerating: bool = false # 正在加速（用於選擇曲線）
var _curve_was_moving: bool = false # ★ 速度曲線專用的移動狀態追蹤
var _last_moving_state: bool = false # 上一幀是否移動中（停止動畫偵測用）

# ==================== 逼真移動系統 (Realistic Movement) ====================
# body_lean_enabled, body_lean_amount, body_lean_smooth, turn_momentum_enabled, turn_rate
# 已遷移到 MovementData resource

# 逼真移動內部狀態
var _current_body_lean: float = 0.0 # 當前身體傾斜角度
var _prev_h_velocity: Vector2 = Vector2.ZERO # 上一幀水平速度（用於計算加速度）
var _visual_facing_angle: float = 0.0 # 視覺模型當前朝向角度
var _target_facing_angle: float = 0.0 # 目標朝向角度
var _realistic_movement_initialized: bool = false # 是否已初始化

## ★ 初始化 PhantomCamera3D 引用
func _setup_phantom_camera() -> void:
	var scene_root = get_parent()
	_pcam = scene_root.get_node_or_null("%PlayerPhantomCamera3D")
	_main_camera = scene_root.get_node_or_null("%MainCamera")
	
	if _pcam and _main_camera:
		# ★ 重定向到 CameraFollowTarget（平滑 Y 避免 step-up 抖動）
		if _cam_follow_target and _pcam.has_method("set_follow_target"):
			_pcam.set_follow_target(_cam_follow_target)
			if verbose_debug: print(">>> [PhantomCamera] ✅ 已重定向到 CameraFollowTarget（平滑 Y）")
		else:
			# ★ 備用方式：直接設定 follow_target 屬性
			if _cam_follow_target:
				_pcam.follow_target = _cam_follow_target.get_path()
				if verbose_debug: print(">>> [PhantomCamera] ✅ follow_target 已設為 CameraFollowTarget")
		if verbose_debug: print(">>> [PhantomCamera] ✅ 已連接 PlayerPhantomCamera3D + MainCamera")
		# 設定初始旋轉（相機從角色背後開始）
		var initial_rot = _pcam.get_third_person_rotation_degrees()
		if verbose_debug: print(">>> [PhantomCamera] 初始旋轉: ", initial_rot)
	else:
		push_warning("[PhantomCamera] ⚠ 找不到 %PlayerPhantomCamera3D 或 %MainCamera")

## 遞迴搜尋任何 Skeleton3D 類型節點（不依賴名稱）
func _find_skeleton_by_type(root: Node) -> Skeleton3D:
	for child in root.get_children():
		if child is Skeleton3D:
			return child
		var found = _find_skeleton_by_type(child)
		if found:
			return found
	return null

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_ensure_movement_data()
	
	# 初始化狀態機 (Phase 3 & 4)
	_fsm.states = {
		"ground": StateGround.new(self),
		"climb": StateClimb.new(self)
	}
	_fsm.init_machine("ground")
	
	# ★ 動態查找 Skeleton3D（GLB 內部可能叫 GeneralSkeleton 或 Skeleton3D）
	if visuals_node:
		skeleton = visuals_node.find_child("GeneralSkeleton", true, false) as Skeleton3D
		if not skeleton:
			skeleton = visuals_node.find_child("Skeleton3D", true, false) as Skeleton3D
		if not skeleton:
			# 最後備援：遞迴搜尋任何 Skeleton3D 類型節點
			skeleton = _find_skeleton_by_type(visuals_node)
		if skeleton:
			if verbose_debug: print(">>> [Skeleton] ✅ 找到: ", skeleton.name, " 路徑: ", skeleton.get_path())
			# ★ 建立腳踝對齊修正器（排在 TwoBoneIK3D 之後自動執行）
			_ankle_modifier = skeleton.find_child("AnkleAlignModifier3D", false, false) as AnkleAlignModifier3D
			if not _ankle_modifier:
				_ankle_modifier = AnkleAlignModifier3D.new()
				_ankle_modifier.name = "AnkleAlignModifier3D"
				skeleton.add_child(_ankle_modifier)
				if verbose_debug: print(">>> [AnkleAlign] ✅ 已建立 AnkleAlignModifier3D")
			else:
				if verbose_debug: print(">>> [AnkleAlign] ✅ 找到既有 AnkleAlignModifier3D")
			# ★ 找到 SimpleFootIK 節點
			_foot_ik_system = find_child("SimpleFootIK", true, false) as SimpleFootIK
			if _foot_ik_system:
				if verbose_debug: print(">>> [FootIK] ✅ 找到 SimpleFootIK")
		else:
			push_warning("[Skeleton] ⚠ 在 Visuals/Human 下找不到任何 Skeleton3D")
	
	# ★ 連接 PhantomCamera3D（延遲至場景載入後）
	call_deferred("_setup_phantom_camera")
	
	# ★ 建立平滑相機跟隨目標（避免 step-up 瞬移造成鏡頭抖動）
	_cam_follow_target = get_node_or_null("CameraFollowTarget") as Marker3D
	if not _cam_follow_target:
		_cam_follow_target = Marker3D.new()
		_cam_follow_target.name = "CameraFollowTarget"
		add_child(_cam_follow_target)
	_cam_smooth_y = global_position.y
	
	# ★ 斷開 CameraMount 旋轉繼承 (如果在場景中)
	var mount = get_node_or_null("CameraMount")
	if mount:
		mount.top_level = true
	
	# ★ Head Look-At 初始化
	_head_look_target = get_node_or_null("HeadLookAtTarget") as Marker3D
	if _skeleton:
		for child in _skeleton.get_children():
			if child.name == "HeadLookAt" and child is SkeletonModifier3D:
				_head_look_at = child
				break
	if _head_look_at and _head_look_target:
		if verbose_debug: print(">>> [Head LookAt] 初始化完成: target=%s" % _head_look_target.name)
	else:
		if verbose_debug: print(">>> [Head LookAt] 未找到 (可選功能)")
	
	# ★★★ 雙層碰撞架構：增加 floor_snap_length 讓角色緊貼斜坡 ★★★
	floor_snap_length = 0.5 # 預設 0.1，增加讓縮短膠囊能貼地
	
	# ★★★ 先載入所有 FBX 動畫，再啟用 AnimationTree（避免 cache 警告）★★★
	_load_root_motion_mantle_anim()
	_load_stair_animations()
	
	# ★ 階梯投影 Debug 可視化 — ImmediateMesh 初始化
	_stair_debug_imm = ImmediateMesh.new()
	_stair_debug_mat = StandardMaterial3D.new()
	_stair_debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stair_debug_mat.vertex_color_use_as_albedo = true
	_stair_debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stair_debug_mat.no_depth_test = true # 始終可見（透過牆壁）
	_stair_debug_mesh = MeshInstance3D.new()
	_stair_debug_mesh.mesh = _stair_debug_imm
	_stair_debug_mesh.material_override = _stair_debug_mat
	_stair_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.call_deferred("add_child", _stair_debug_mesh) # 加到根節點（世界座標）
	
	# 確保 AnimationTree 活躍
	if anim_tree:
		anim_tree.active = true
		print("=== AnimationTree 啟動 ===")
		print("Active: ", anim_tree.active)
		print("Root: ", anim_tree.tree_root)
		
		# 獲取 playback 並印出
		var playback = anim_tree.get("parameters/playback")
		if playback:
			print("Playback: ", playback)
			print("Current node: ", playback.get_current_node())
		
		# 診斷狀態機結構
		var root_sm = anim_tree.tree_root as AnimationNodeStateMachine
		if root_sm:
			print("\n=== 狀態機診斷 ===")
			# 檢查特定狀態是否存在
			print("has jump_backward: ", root_sm.has_node("jump_backward"))
			print("has jump_oneshot: ", root_sm.has_node("jump_oneshot"))
			print("has movement: ", root_sm.has_node("movement"))
			
			# 關鍵：檢查過渡是否存在
			print("\n=== 過渡檢查 ===")
			print("movement->jump_backward: ", root_sm.has_transition("movement", "jump_backward"))
			print("movement->jump_oneshot: ", root_sm.has_transition("movement", "jump_oneshot"))
			print("movement->jump_oneshot_alt: ", root_sm.has_transition("movement", "jump_oneshot_alt"))
			print("Start->movement: ", root_sm.has_transition("Start", "movement"))
		
		# 列出 AnimationPlayer 中的跳躍動畫（僅首次啟動時輸出）
		if anim_player:
			print("\n=== 可用跳躍動畫 ===")
			for anim in anim_player.get_animation_list():
				if "jump" in anim.to_lower() or "Jump" in anim:
					print("  ", anim)
	else:
		push_error("找不到 AnimationTree！")
	
	# 初始化腳部 IK (可選功能)
	_setup_foot_ik_nodes()
	

## ★ 確保 MovementData 存在（如果沒有在 Inspector 指定則用預設值）
func _ensure_movement_data() -> void:
	if movement_data == null:
		movement_data = MovementData.new()
		if verbose_debug: print(">>> [MovementData] ⚠ 未指定 Resource，使用預設值")

## ★ 狀態轉換函數（集中管理，含 debug 日誌）
func _set_motion_state(new_state: MovementEnums.MotionState) -> void:
	if state_anim.motion_state == new_state:
		return
	var old_name = MovementEnums.MotionState.keys()[state_anim.motion_state]
	var new_name = MovementEnums.MotionState.keys()[new_state]
	if Engine.get_frames_drawn() % 10 == 0 or new_state != MovementEnums.MotionState.IDLE:
		if verbose_debug: print(">>> [MotionState] %s → %s" % [old_name, new_name])
	state_anim.motion_state = new_state

## ★ Gait 切換函數
func _set_gait(new_gait: MovementEnums.Gait) -> void:
	if state_anim.gait == new_gait:
		return
	var old_name = MovementEnums.Gait.keys()[state_anim.gait]
	var new_name = MovementEnums.Gait.keys()[new_gait]
	if verbose_debug: print(">>> [Gait] %s → %s" % [old_name, new_name])
	state_anim.gait = new_gait

## ★ 便利屬性（讓後續程式碼更簡潔）
var _is_landing: bool:
	get: return state_anim.motion_state == MovementEnums.MotionState.LANDING
var _is_jumping: bool:
	get: return state_anim.motion_state == MovementEnums.MotionState.JUMPING
var _is_falling: bool:
	get: return state_anim.motion_state == MovementEnums.MotionState.FALLING
var _is_stopping: bool:
	get: return state_anim.motion_state == MovementEnums.MotionState.STOPPING
var _is_crouching: bool:
	get: return state_anim.gait == MovementEnums.Gait.CROUCH

## ★ 從原始 FBX 載入包含 Root Motion 的攀爬動畫
func _load_root_motion_mantle_anim() -> void:
	if not anim_player:
		if verbose_debug: print(">>> [Root Motion] 沒有 AnimationPlayer")
		return
	
	if verbose_debug: print(">>> [Root Motion] 正在載入 FBX: %s" % MANTLE_RM_FBX_PATH)
	
	# 載入 FBX 場景
	var fbx_scene = load(MANTLE_RM_FBX_PATH) as PackedScene
	if not fbx_scene:
		if verbose_debug: print(">>> [Root Motion] ❗ 無法載入 FBX: %s" % MANTLE_RM_FBX_PATH)
		return
	
	# 實例化場景以提取動畫
	var fbx_instance = fbx_scene.instantiate()
	
	# 在 FBX 場景中找 AnimationPlayer
	var fbx_anim_player: AnimationPlayer = null
	for child in fbx_instance.get_children():
		if child is AnimationPlayer:
			fbx_anim_player = child
			break
	
	if not fbx_anim_player:
		# 嘗試遞迴搜尋
		for child in fbx_instance.get_children():
			for grandchild in child.get_children():
				if grandchild is AnimationPlayer:
					fbx_anim_player = grandchild
					break
			if fbx_anim_player:
				break
	
	if not fbx_anim_player:
		if verbose_debug: print(">>> [Root Motion] ❗ FBX 中找不到 AnimationPlayer")
		# 列出所有子節點幫助 debug
		for child in fbx_instance.get_children():
			if verbose_debug: print(">>>   FBX 子節點: %s (%s)" % [child.name, child.get_class()])
			for grandchild in child.get_children():
				if verbose_debug: print(">>>     子子節點: %s (%s)" % [grandchild.name, grandchild.get_class()])
		fbx_instance.queue_free()
		return
	
	if verbose_debug: print(">>> [Root Motion] 找到 FBX AnimationPlayer: %s" % fbx_anim_player.name)
	
	# 提取動畫
	var found_anim: Animation = null
	var _found_anim_name: String = ""
	for lib_name in fbx_anim_player.get_animation_library_list():
		var lib = fbx_anim_player.get_animation_library(lib_name)
		if verbose_debug: print(">>> [Root Motion] 動畫庫 '%s' 有 %d 個動畫" % [lib_name, lib.get_animation_list().size()])
		for anim_name in lib.get_animation_list():
			var anim = lib.get_animation(anim_name)
			if anim:
				found_anim = anim
				_found_anim_name = anim_name
				if verbose_debug: print(">>> [Root Motion] 找到 FBX 動畫: %s (軌道數=%d, 時長=%.2fs)" % [anim_name, anim.get_track_count(), anim.length])
				break
		if found_anim:
			break
	
	if not found_anim:
		if verbose_debug: print(">>> [Root Motion] ❗ FBX 中沒有動畫")
		fbx_instance.queue_free()
		return
	
	# ★ 重新映射動畫軌道路徑（FBX → 我們的場景結構）
	# FBX 軌道路徑類似 "Skeleton3D:Hips"，需要映射到 "GeneralSkeleton:Hips"
	# ★ AnimationPlayer.root_node = "../Visuals/Human"，路徑相對於 Visuals/Human
	var our_skeleton_path = "%GeneralSkeleton" # ★ Godot unique name 語法
	var remapped_count = 0
	var has_hips_pos = false
	
	for i in range(found_anim.get_track_count()):
		var orig_path = found_anim.track_get_path(i)
		var path_str = str(orig_path)
		var track_type = found_anim.track_get_type(i)
		
		# 軌道路徑格式: "NodePath:BoneName" 或 "NodePath:BoneName/SubPath"
		var colon_pos = path_str.find(":")
		if colon_pos >= 0:
			var bone_part = path_str.substr(colon_pos + 1) # ":Hips" → "Hips"
			var _old_node_path = path_str.substr(0, colon_pos) # "Skeleton3D"
			var new_path = NodePath(our_skeleton_path +":"+ bone_part)
			found_anim.track_set_path(i, new_path)
			remapped_count += 1
			
			# 印出前 5 個 + 所有 Hips 軌道
			if i < 5 or "Hips" in bone_part:
				if verbose_debug: print(">>> [Root Motion] 軌道[%d]: %s → %s (類型=%d)" % [i, orig_path, new_path, track_type])
			
			# 檢查 Hips 位置軌道
			if "Hips" in bone_part and track_type == Animation.TYPE_POSITION_3D:
				has_hips_pos = true
				var key_count = found_anim.track_get_key_count(i)
				if key_count > 0:
					var first_pos = found_anim.track_get_key_value(i, 0)
					var last_pos = found_anim.track_get_key_value(i, key_count - 1)
					var displacement = last_pos - first_pos
					if verbose_debug: print(">>> [Root Motion] ✅ Hips 位移: 第一幀=%s, 最後幀=%s, 差值=%s" % [first_pos, last_pos, displacement])
					if verbose_debug: print(">>> [Root Motion] ✅ Y 軸位移=%.3f（用於 MANTLE_ANIM_CLIMB_HEIGHT）" % displacement.y)
	
	if verbose_debug: print(">>> [Root Motion] 已重新映射 %d 個軌道路徑" % remapped_count)
	
	if not has_hips_pos:
		if verbose_debug: print(">>> [Root Motion] ❗ FBX 動畫沒有 Hips 位置軌道！")
	
	# 創建新的 AnimationLibrary 並加入我們的 AnimationPlayer
	var rm_lib = AnimationLibrary.new()
	rm_lib.add_animation(MANTLE_RM_ANIM_NAME, found_anim)
	
	# 如果已存在就移除舊的
	if anim_player.has_animation_library(MANTLE_RM_ANIM_LIB):
		anim_player.remove_animation_library(MANTLE_RM_ANIM_LIB)
	
	anim_player.add_animation_library(MANTLE_RM_ANIM_LIB, rm_lib)
	climb.mantle_rm_loaded = true
	if verbose_debug: print(">>> [Root Motion] ✅ 已載入 Root Motion 攀爬動畫: %s/%s" % [MANTLE_RM_ANIM_LIB, MANTLE_RM_ANIM_NAME])
	
	# 清理 FBX 實例
	fbx_instance.queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# ★ Souls-like：滑鼠控制相機旋轉
		if _pcam:
			var pcam_rot: Vector3 = _pcam.get_third_person_rotation_degrees()
			pcam_rot.x -= event.relative.y * cam_mouse_sensitivity
			pcam_rot.x = clampf(pcam_rot.x, cam_min_pitch, cam_max_pitch)
			pcam_rot.y -= event.relative.x * cam_mouse_sensitivity
			pcam_rot.y = wrapf(pcam_rot.y, 0.0, 360.0)
			_pcam.set_third_person_rotation_degrees(pcam_rot)
		elif has_node("CameraMount"):
			# ★ Fallback for standard CameraMount
			var mount = get_node("CameraMount")
			mount.rotation.y -= event.relative.x * cam_mouse_sensitivity * PI / 180.0
			var spring_arm = mount.get_node_or_null("SpringArm3D")
			if spring_arm:
				spring_arm.rotation.x -= event.relative.y * cam_mouse_sensitivity * PI / 180.0
				spring_arm.rotation.x = clampf(spring_arm.rotation.x, deg_to_rad(cam_min_pitch), deg_to_rad(cam_max_pitch))
	
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# ★ Debug: 按 T 切換慢動作（0.25x ↔ 1.0x）
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		if Engine.time_scale < 1.0:
			Engine.time_scale = 1.0
			if verbose_debug: print(">>> [Debug] 慢動作 OFF → 1.0x")
		else:
			Engine.time_scale = 0.25
			if verbose_debug: print(">>> [Debug] 慢動作 ON → 0.25x")
	
	# ★ 移動鍵放開事件：觸發停止動畫
	if event is InputEventKey and not event.pressed:
		if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
			_on_movement_key_released()
	
var _frame_count: int = 0
var _last_node: String = ""
var _crouch_cooldown: float = 0.0 # 蹲下切換冷却時間
var _stance_value: float = 0.0 # 0.0 = 站立, 1.0 = 蹲下
var _blend_position: Vector2 = Vector2.ZERO # BlendSpace 位置 (平滑過渡)

# ★ 以下變數從 _physics_process 本地提升為成員，供子函數共用
var _input_dir: Vector2 = Vector2.ZERO # 本幀原始輸入
var _is_moving_frame: bool = false # 本幀是否有移動輸入
var _is_sprinting_frame: bool = false # 本幀是否衝刺
var _want_jump_frame: bool = false # 本幀是否按了跳
var _move_dir: Vector3 = Vector3.ZERO # 相機空間移動方向
var _current_speed: float = 0.0 # 本幀目標速度

# Stance 過渡速度 (值越大越快)
const STANCE_TRANSITION_SPEED: float = 4.0
const BLEND_SMOOTH_SPEED: float = 10.0 # BlendSpace 過渡速度 (動畫方向切換)

## ==================== 水面滑行測試模式 ====================
## 按 F5 切換：WASD 平滑滑行，無重力/動畫，純觀察漣漪效果
var _water_slide_mode: bool = false
var _water_slide_speed: float = 5.0 # 滑行速度 (m/s)
var _water_slide_y: float = 0.0 # 固定 Y 高度
var _water_slide_toggled: bool = false # 防止重複切換

func _process_water_slide(delta: float) -> void:
	# WASD 輸入
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y += 1
	if Input.is_key_pressed(KEY_S): input_dir.y -= 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()
	
	# Shift = 加速
	var speed = _water_slide_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 2.5
	
	# 取得相機（PhantomCamera 或 viewport 相機）
	var cam = _main_camera if _main_camera else get_viewport().get_camera_3d()
	
	# 基於相機方向移動
	var move_dir = Vector3.ZERO
	if cam and input_dir.length() > 0.01:
		var cam_basis = cam.global_transform.basis
		var cam_forward = - cam_basis.z
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		var cam_right = cam_basis.x
		cam_right.y = 0
		cam_right = cam_right.normalized()
		move_dir = (cam_forward * input_dir.y + cam_right * input_dir.x).normalized()
	
	# 平滑移動（無加速度，直接設速度）
	velocity = move_dir * speed
	velocity.y = 0 # 無重力
	
	# 保持 Y 高度
	global_position.y = _water_slide_y
	
	# 面向移動方向
	if move_dir.length() > 0.1:
		var target_angle = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)
	
	move_and_slide()

func _physics_process(delta: float) -> void:
	_frame_count += 1
	
	# ★ 首幀初始化
	if _frame_count == 1:
		floor_max_angle = deg_to_rad(slope_max_angle_deg)
		floor_snap_length = slope_snap_length
		if verbose_debug: print(">>> [Slope] floor_max_angle=%.1f° floor_snap_length=%.2f" % [slope_max_angle_deg, slope_snap_length])
	
	# ★ 地面狀態
	ground.was_on_floor = is_on_floor() or ground.step_down_snapped or ground.snapped_to_stairs_last_frame
	ground.step_down_snapped = false
	ground.snapped_to_stairs_last_frame = false
	if _process_water_slide_toggle(delta):
		return
	
	# ★ 交由 HSM 狀態機處理 (Phase 3)
	_fsm.physics_update(delta)

## ★ 每幀更新 (解耦物理頻率，解決掉幀微卡頓)
func _process(delta: float) -> void:
	if not is_inside_tree(): return
	
	_update_camera_mount(delta)
	_process_visual_smoothing(delta)
	_update_foot_ik_targets()
	_update_ground_locomotion_ik(delta)
	_update_head_look_at(delta)


# ═══════════════════════════════════════════════════════════════
# ★ 從 _physics_process 提取的子函數
# ═══════════════════════════════════════════════════════════════

## 水面滑行切換（F5）— 回傳 true = 已處理
func _process_water_slide_toggle(delta: float) -> bool:
	if Input.is_key_pressed(KEY_F5) and not _water_slide_toggled:
		_water_slide_toggled = true
		_water_slide_mode = not _water_slide_mode
		if _water_slide_mode:
			_water_slide_y = global_position.y
			if verbose_debug: print(">>> 🌊 水面滑行模式 ON")
		else:
			if verbose_debug: print(">>> 🌊 水面滑行模式 OFF")
	elif not Input.is_key_pressed(KEY_F5):
		_water_slide_toggled = false
	if _water_slide_mode:
		_process_water_slide(delta)
		return true
	return false

## 相機掛載
func _update_camera_mount(delta: float) -> void:
	var mount = get_node_or_null("CameraMount")
	if mount and mount.top_level:
		mount.global_position = mount.global_position.lerp(global_position + Vector3(0, 1.5, 0), 20.0 * delta)

## 第一幀動畫初始化
func _process_first_frame_init() -> void:
	if _frame_count == 1:
		var init_pb = anim_tree.get("parameters/playback") if anim_tree else null
		if init_pb:
			init_pb.travel("movement")
			if verbose_debug: print(">>> 強制 travel('movement')")

## 前 20 幀 debug
func _print_frame_debug() -> void:
	var pb = anim_tree.get("parameters/playback") if anim_tree else null
	var cur = pb.get_current_node() if pb else "N/A"
	if _frame_count <= 20 or cur != _last_node:
		var grounded = anim_tree.get("parameters/conditions/grounded") if anim_tree else false
		var jc = anim_tree.get("parameters/conditions/jump") if anim_tree else false
		var pos = pb.get_current_play_position() if pb else 0.0
		var ln = pb.get_current_length() if pb else 0.0
		print("Frame ", _frame_count, ": node=", cur, " pos=", "%.2f" % pos, "/", "%.2f" % ln, " grounded=", grounded, " jump=", jc, " _is_jumping=", _is_jumping)
		_last_node = cur

## 輸入收集
func _gather_input() -> void:
	_input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): _input_dir.y += 1
	if Input.is_key_pressed(KEY_S): _input_dir.y -= 1
	if Input.is_key_pressed(KEY_A): _input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): _input_dir.x += 1
	_input_dir = _input_dir.normalized()
	if Input.is_key_pressed(KEY_SHIFT) and not _is_crouching:
		_set_gait(MovementEnums.Gait.SPRINT)
	elif not _is_crouching and state_anim.gait == MovementEnums.Gait.SPRINT:
		_set_gait(MovementEnums.Gait.WALK)
	_is_sprinting_frame = state_anim.gait == MovementEnums.Gait.SPRINT
	_want_jump_frame = Input.is_action_just_pressed("ui_accept")
	_is_moving_frame = _input_dir.length() > 0.1
	if _is_moving_frame and not _is_moving_input:
		_move_start_time = Time.get_ticks_msec() / 1000.0
		_is_moving_input = true
		if verbose_debug: print(">>> Movement started at %.2f" % _move_start_time)
	elif not _is_moving_frame:
		_is_moving_input = false

## 測試按鍵（H/G）
func _process_test_keys() -> void:
	if Input.is_physical_key_pressed(KEY_H) and not _test_h_pressed:
		_test_h_pressed = true
		if verbose_debug: print(">>> 測試 Hanging_Idle 動畫")
		if anim_tree: anim_tree.active = false
		anim_player.speed_scale = 1.0
		var anim = anim_player.get_animation("movement/" + HANG_IDLE_ANIM)
		if anim: anim.loop_mode = Animation.LOOP_LINEAR
		anim_player.play("movement/" + HANG_IDLE_ANIM)
	elif not Input.is_physical_key_pressed(KEY_H):
		_test_h_pressed = false
	if Input.is_physical_key_pressed(KEY_G) and not _test_g_pressed:
		_test_g_pressed = true
		if verbose_debug: print(">>> 測試 Hang_To_Crouch 動畫")
		if anim_tree: anim_tree.active = false
		anim_player.speed_scale = 1.0
		anim_player.play("movement/" + HANG_TO_CROUCH_ANIM)
	elif not Input.is_physical_key_pressed(KEY_G):
		_test_g_pressed = false
	if anim_player.current_animation == "movement/" + HANG_TO_CROUCH_ANIM:
		if skeleton:
			var hips_idx = skeleton.find_bone("Hips")
			if hips_idx >= 0:
				var cp = skeleton.get_bone_pose(hips_idx)
				cp.origin = Vector3.ZERO
				skeleton.set_bone_pose(hips_idx, cp)

## 計時器 & 空中/落地
func _process_timers_and_fall(delta: float) -> void:
	if is_on_floor(): air.coyote_timer = movement_data.coyote_time
	else: air.coyote_timer -= delta
	if _crouch_cooldown > 0: _crouch_cooldown -= delta
	var crouch_pressed = Input.is_action_just_pressed("crouch") and _crouch_cooldown <= 0
	if crouch_pressed and is_on_floor():
		if state_anim.gait == MovementEnums.Gait.CROUCH: _set_gait(MovementEnums.Gait.WALK)
		else: _set_gait(MovementEnums.Gait.CROUCH)
		_crouch_cooldown = 0.5
		if verbose_debug: print(">>> Crouch toggled! crouching = %s" % _is_crouching)
	if air.jump_grace_timer > 0: air.jump_grace_timer -= delta
	if not is_on_floor():
		if stair.step_up_offset > 0.0 or stair.post_step_up_cooldown > 0 or ground.was_on_floor: air.air_time = 0.0
		else: air.air_time += delta
		if velocity.y < 0: air.fall_velocity_peak = maxf(air.fall_velocity_peak, absf(velocity.y))
		if not _is_falling and not _is_jumping and air.air_time > FALL_TRIGGER_TIME and velocity.y < 0:
			if air.jump_to_type != JumpToType.TO_STAGE and stair.step_up_offset <= 0.0 and stair.post_step_up_cooldown <= 0:
				_set_motion_state(MovementEnums.MotionState.FALLING)
				_trigger_jump_loop_animation()
	# ★ 落地偵測已移到 StateGround pipeline Step 6（在 move_and_slide 之後）
	# 不在這裡做，因為 is_on_floor() 在 move_and_slide() 之前是過時的
	if _is_landing:
		air.landing_timer -= delta
		var has_input = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
		if air.landing_timer <= 0 or (has_input and air.landing_timer < LAND_ANIMATION_DURATION * 0.5):
			_set_motion_state(MovementEnums.MotionState.IDLE)
			air.jump_phase = JumpPhase.NONE
			anim_player.speed_scale = 1.0
			air.post_landing_blend_timer = POST_LANDING_BLEND_DURATION
			_activate_foot_lock()
			if anim_tree and not anim_tree.active:
				anim_tree.active = true
				var land_pb = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
				if land_pb:
					anim_tree.set("parameters/conditions/jump", false)
					land_pb.travel("movement")
			if anim_player.animation_finished.is_connected(_on_jump_phase_finished):
				anim_player.animation_finished.disconnect(_on_jump_phase_finished)
			_curve_time = 0.0
			_curve_start_velocity = Vector3.ZERO
			_curve_target_velocity = Vector3.ZERO
			_is_accelerating = true
			_curve_was_moving = false
			if verbose_debug: print(">>> LAND timer expired: restored")

## 跳躍系統
func _process_jump_system(delta: float) -> void:
	if _want_jump_frame: air.jump_buffer_timer = movement_data.jump_buffer_time
	var can_jump = air.coyote_timer > 0.0 and not _is_crouching and not _is_landing and not _is_jumping
	if air.jump_buffer_timer > 0 and can_jump:
		var moving_fwd = _input_dir.y > 0.1
		if moving_fwd and _detect_platform_ahead():
			_set_motion_state(MovementEnums.MotionState.JUMPING)
			air.jump_buffer_timer = 0.0
			air.coyote_timer = 0.0
			_trigger_jump_to_stage()
		else:
			velocity.y = movement_data.jump_velocity
			air.coyote_timer = 0.0
			air.jump_buffer_timer = 0.0
			air.is_ascending = true
			air.jump_hold_timer = 0.0
			_set_motion_state(MovementEnums.MotionState.JUMPING)
			air.jump_grace_timer = 0.15
			_trigger_jump_animation()
	if air.is_ascending and velocity.y > 0:
		if Input.is_action_pressed("ui_accept"):
			if air.jump_hold_timer < movement_data.jump_hold_max_time:
				velocity.y += movement_data.jump_hold_force * delta
				air.jump_hold_timer += delta
		else:
			if movement_data.variable_jump_height: air.is_ascending = false
	if velocity.y <= 0: air.is_ascending = false
	air.jump_buffer_timer = max(0, air.jump_buffer_timer - delta)

## 邊緣抓握
func _process_ledge_grab() -> void:
	if not is_on_floor() and climb.state == ClimbState.NONE and not _is_landing:
		if velocity.y < 0:
			var ld = _detect_grabbable_ledge()
			if ld.found: _enter_hanging_state(ld)

## 水平移動
func _process_horizontal_movement(delta: float) -> void:
	_current_speed = movement_data.walk_speed
	if _is_sprinting_frame: _current_speed = movement_data.sprint_speed
	elif _is_crouching: _current_speed = movement_data.crouch_speed
	var target_velocity = Vector3.ZERO
	_move_dir = Vector3.ZERO
	var cam = _main_camera if _main_camera else get_viewport().get_camera_3d()
	if cam and _input_dir.length() > 0.01:
		var cb = cam.global_transform.basis
		var cf = - cb.z; cf.y = 0; cf = cf.normalized()
		var cr = cb.x; cr.y = 0; cr = cr.normalized()
		_move_dir = (cf * _input_dir.y + cr * _input_dir.x).normalized()
	if _is_moving_frame and _waiting_for_foot: _waiting_for_foot = false
	if _is_moving_frame and not _is_moving_input:
		_is_moving_input = true
		_move_start_time = Time.get_ticks_msec() / 1000.0
	elif not _is_moving_frame:
		_is_moving_input = false
	if Engine.get_frames_drawn() % 30 == 0 and _is_moving_frame:
		var hs = Vector2(velocity.x, velocity.z).length()
		if verbose_debug: print(">>> [Move Guard] landing=%s stopping=%s cam=%s move_dir=%s speed=%.2f vel_h=%.2f" % [_is_landing, _is_stopping, _main_camera != null, _move_dir, _current_speed, hs])
	if _is_moving_frame and not _is_landing and not _is_stopping:
		var ssl: float = _current_speed
		if stair.root_motion_active:
			var rsc: float
			if stair.ascending: rsc = STAIR_RM_WALK_H_SPEED * 1.5
			else: rsc = STAIR_RM_DESCEND_H_SPEED * 1.5
			ssl = minf(_current_speed, rsc)
		target_velocity = _move_dir * ssl
		if _move_dir.length() > 0.1:
			var ta = atan2(-_move_dir.x, -_move_dir.z)
			var ss = movement_data.turn_rate / 45.0
			var sf = 1.0 - exp(-ss * delta)
			rotation.y = lerp_angle(rotation.y, ta, sf)
	var accel: float; var decel_v: float
	if is_on_floor():
		accel = movement_data.ground_acceleration; decel_v = movement_data.ground_deceleration
	else:
		accel = movement_data.air_acceleration; decel_v = movement_data.air_deceleration
	var chv = Vector2(velocity.x, velocity.z)
	var thv = Vector2(target_velocity.x, target_velocity.z)
	var chs = chv.length(); var ths = thv.length()
	var rate: float
	if ths < 0.1: rate = decel_v
	elif chs < 0.1: rate = accel
	else:
		var dd = chv.normalized().dot(thv.normalized())
		if dd < 0.0: rate = decel_v * 1.5
		elif dd < 0.7: rate = accel * 1.2
		else: rate = accel if ths > chs else decel_v
	if movement_data.use_velocity_curves and (movement_data.acceleration_curve or movement_data.deceleration_curve):
		_apply_velocity_curve(target_velocity, delta)
	elif movement_data.use_exponential_curve:
		var f = 1.0 - exp(-rate * delta)
		velocity.x = lerp(velocity.x, target_velocity.x, f)
		velocity.z = lerp(velocity.z, target_velocity.z, f)
	else:
		velocity.x = move_toward(velocity.x, target_velocity.x, rate * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, rate * delta)

## [DEPRECATED] 已內聯到 StateGround.physics_update pipeline
func _process_stair_physics(_delta: float) -> void:
	push_warning("_process_stair_physics is deprecated - logic moved to StateGround pipeline")
	pass

## 視覺平滑
func _process_visual_smoothing(delta: float) -> void:
	var cur_asc = stair.on_stairs and stair.ascending
	if cur_asc:
		if not stair.was_ascending:
			stair.step_up_visual_debt = 0.0
			_smooth_visual_y = global_position.y
		var slope = is_on_floor() and get_floor_normal().dot(Vector3.UP) < 0.95
		var spd := 50.0 if slope else 15.0
		_smooth_visual_y = lerpf(_smooth_visual_y, global_position.y, 1.0 - exp(-spd * delta))
		if _visuals_node:
			var vp = _pelvis_offset if _predict_ik_active else 0.0
			_visuals_node.global_position.y = _smooth_visual_y + vp
			_visuals_node.position.x = 0.0
			_visuals_node.position.z = 0.0
		if Engine.get_frames_drawn() % 5 == 0:
			if verbose_debug: print(">>> [StairDbg] phys_y=%.3f vis_y=%.3f pred=%s" % [global_position.y, _visuals_node.global_position.y if _visuals_node else 0.0, _predict_ik_active])
		if _cam_follow_target:
			_cam_smooth_y = lerpf(_cam_smooth_y, global_position.y, delta * 6.0)
			_cam_follow_target.global_position = Vector3(global_position.x, _cam_smooth_y, global_position.z)
	else:
		if stair.was_ascending: stair.step_up_visual_debt = 0.0
		if abs(stair.step_up_visual_debt) > 0.001:
			stair.step_up_visual_debt = lerpf(stair.step_up_visual_debt, 0.0, delta * 15.0)
			if abs(stair.step_up_visual_debt) < 0.002: stair.step_up_visual_debt = 0.0
		if _visuals_node:
			var vp2 = _pelvis_offset if _predict_ik_active else 0.0
			_visuals_node.position.y = stair.step_up_visual_debt + vp2
			_visuals_node.position.x = 0.0
			_visuals_node.position.z = 0.0
		_smooth_visual_y = global_position.y + stair.step_up_visual_debt
		if _cam_follow_target:
			_cam_smooth_y = lerpf(_cam_smooth_y, global_position.y, delta * 20.0)
			_cam_follow_target.global_position = Vector3(global_position.x, _cam_smooth_y, global_position.z)
	stair.was_ascending = cur_asc

## 停止動畫計時器
func _process_stop_animation(delta: float) -> void:
	if _is_stopping:
		_stopping_timer -= delta
		if _stopping_timer <= 0:
			if verbose_debug: print(">>> [Timer Fallback] 停止動畫計時器到期")
			_set_motion_state(MovementEnums.MotionState.IDLE)
			_stopping_anim_name = ""
			anim_player.speed_scale = 1.0
			if anim_player.animation_finished.is_connected(_on_run_to_stop_finished):
				anim_player.animation_finished.disconnect(_on_run_to_stop_finished)
			_restore_animation_tree()

## Physics fallback 停止
func _process_physics_fallback_stop() -> void:
	var pms = Vector2(velocity.x, velocity.z).length()
	if _last_moving_state and not _is_moving_frame and not _is_stopping and not _is_jumping and not _is_landing and not stair.on_stairs and stair.blend_weight < 0.01 and is_on_floor():
		if pms > 0.3 and not _stop_anim_triggered:
			if verbose_debug: print(">>> [Physics Fallback] speed=%.2f" % pms)
			_stop_anim_triggered = true
			_trigger_run_to_stop_animation()
	_last_moving_state = _is_moving_frame
	_prev_h_speed = pms

## BlendSpace + Stance
func _process_blendspace(delta: float) -> void:
	if not anim_tree: return
	var ts = 1.0 if _is_crouching else 0.0
	_stance_value = lerp(_stance_value, ts, STANCE_TRANSITION_SPEED * delta)
	anim_tree.set("parameters/movement/Blend2/blend_amount", _stance_value)
	var bm = 1.0 if (_is_sprinting_frame and not _is_crouching) else 0.5
	var sr = Vector2(velocity.x, velocity.z).length() / maxf(_current_speed, 0.1)
	var tbp = Vector2(0, clampf(sr, 0, 1)) * bm
	if _is_moving_frame and _is_sprinting_frame and not _is_crouching:
		tbp = Vector2(0, clampf(sr, 0, 1))
	_blend_position = _blend_position.lerp(tbp, BLEND_SMOOTH_SPEED * delta)
	anim_tree.set("parameters/movement/stand_movement/blend_position", _blend_position)
	anim_tree.set("parameters/movement/crouch_movement/blend_position", _blend_position)

## 停止動畫輸入打斷
func _process_stopping_interrupt() -> void:
	if not _is_stopping: return
	_stopping_grace_timer -= get_physics_process_delta_time()
	if _input_dir != Vector2.ZERO and _stopping_grace_timer <= 0:
		_cancel_stop_animation()
	elif _stopping_anim_name == "Run_To_Stop":
		call_deferred("_lock_hips_position")
	rotation.y = _stopping_rotation

## 頭部 LookAt 系統：追蹤攝影機注視方向
func _update_head_look_at(delta: float) -> void:
	if not _head_look_at or not _head_look_target:
		return
	
	# 決定目標 influence（根據角色狀態）
	var target_influence: float = 0.0
	if climb.state != ClimbState.NONE or _is_jumping or not is_on_floor():
		target_influence = 0.0 # 空中/攀爬不追蹤
	elif state_anim.gait == MovementEnums.Gait.SPRINT:
		target_influence = 0.3 # 衝刺時微弱追蹤
	elif _is_crouching:
		target_influence = 0.8 # 蹲下時追蹤
	else:
		target_influence = 1.0 # 正常站立/走路
	
	# 平滑過渡 influence
	_head_influence = lerp(_head_influence, target_influence, HEAD_LOOK_SPEED * delta)
	_head_look_at.influence = _head_influence
	
	# 更新目標位置：頭部前方，跟隨攝影機方向
	if _skeleton:
		var head_idx = _skeleton.find_bone("Head")
		if head_idx >= 0:
			var head_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(head_idx)
			var head_pos = head_global.origin
			
			# 取得攝影機前方方向
			var cam = get_viewport().get_camera_3d()
			if cam:
				var cam_forward = - cam.global_basis.z
				# 目標在頭部位置 + 攝影機方向 * 距離
				_head_look_target.global_position = head_pos + cam_forward * HEAD_LOOK_DISTANCE

func _update_animation_conditions(is_moving: bool, on_floor: bool) -> void:
	if not anim_tree:
		return
	
	# ★ 停止動畫播放中，不更新任何 AnimationTree 參數
	if _is_stopping:
		return
	
	var in_air = not on_floor
	
	# 基本狀態條件（★ 使用 ground.was_on_floor 或 on_floor 避免樓梯間隙觸發 FALLING）
	var effective_floor = on_floor or ground.was_on_floor
	anim_tree.set("parameters/conditions/idle", not is_moving and effective_floor and not _is_crouching and not _is_landing)
	anim_tree.set("parameters/conditions/walk", is_moving and effective_floor and not _is_crouching and not _is_landing)
	
	# 跳躍/空中條件
	# 使用 air.jump_grace_timer 確保跳躍條件在起跳時保持 true 足夠長時間
	# ★ 修正：移除 `or is_on_floor()` — 落地後 _is_jumping 尚未清除時
	# is_on_floor()=true 會讓 jump_condition 卡在 true，阻止 AnimTree 過渡到 landing
	var jump_condition = _is_jumping and air.jump_grace_timer > 0
	anim_tree.set("parameters/conditions/jump", jump_condition)
	if jump_condition:
		if verbose_debug: print(">>> Frame ", _frame_count, " jump_condition=TRUE! _is_jumping=", _is_jumping, " grace=", air.jump_grace_timer, " on_floor=", is_on_floor())
	# ★ 加入 air.air_time 門檻：離地不足 0.15s 不觸發掉落動畫（樓梯間隙保護）
	anim_tree.set("parameters/conditions/falling", velocity.y <= 0 and in_air and air.air_time > 0.15) # 下降中
	anim_tree.set("parameters/conditions/landed", _is_landing) # 剛落地
	anim_tree.set("parameters/conditions/grounded", effective_floor and not _is_landing and not _is_jumping) # 正常站立
	
	# 蹲下條件
	anim_tree.set("parameters/conditions/crouch_idle", _is_crouching and not is_moving and on_floor)
	anim_tree.set("parameters/conditions/crouch_walk", _is_crouching and is_moving and on_floor)
	anim_tree.set("parameters/conditions/stand_up", not _is_crouching and on_floor)
	
	# 轉身條件
	anim_tree.set("parameters/conditions/turn_left", _is_turning and _turn_direction < 0)
	anim_tree.set("parameters/conditions/turn_right", _is_turning and _turn_direction > 0)

## 轉身系統：偵測斜向輸入 (WA, WD, SA, SD) 並播放轉身動畫
func _process_turn_in_place(p_move_dir: Vector3, delta: float) -> void:
	# 只在蹲下且在地面時觸發轉身
	if not _is_crouching or not is_on_floor():
		_is_turning = false
		_turn_direction = 0
		return
	
	# 如果正在轉身，執行轉身邏輯
	if _is_turning:
		_execute_turn(delta)
		return
	
	# 偵測斜向輸入 (同時按下前/後 + 左/右)
	var has_forward = Input.is_key_pressed(KEY_W)
	var has_backward = Input.is_key_pressed(KEY_S)
	var has_left = Input.is_key_pressed(KEY_A)
	var has_right = Input.is_key_pressed(KEY_D)
	
	var is_diagonal = (has_forward or has_backward) and (has_left or has_right)
	
	if not is_diagonal:
		return
	
	# 決定轉向方向：A = 右轉, D = 左轉
	if has_left:
		_start_turn(45.0) # 右轉 45 度
	elif has_right:
		_start_turn(-45.0) # 左轉 45 度

func _start_turn(angle_diff: float) -> void:
	_is_turning = true
	_turn_direction = -1 if angle_diff < 0 else 1
	_turn_remaining = abs(angle_diff)
	_turn_target_angle = rotation.y + deg_to_rad(angle_diff)
	if verbose_debug: print(">>> 開始轉身: 方向=", "左" if _turn_direction < 0 else "右", " 角度=", abs(angle_diff))

func _execute_turn(delta: float) -> void:
	# 每幀轉動的角度
	var turn_amount = movement_data.turn_speed * delta
	
	if _turn_remaining <= turn_amount:
		# 轉身完成
		rotation.y = _turn_target_angle
		_is_turning = false
		_turn_direction = 0
		_turn_remaining = 0.0
		if verbose_debug: print(">>> 轉身完成")
	else:
		# 繼續轉身
		rotation.y += deg_to_rad(turn_amount) * _turn_direction
		_turn_remaining -= turn_amount

## 觸發跳躍動畫（繞過 BlendTree 狀態機限制，直接使用 AnimationPlayer）
## 跳躍動畫名稱映射 (狀態邏輯名稱 -> AnimationPlayer 動畫名稱)
const JUMP_ANIM_MAP: Dictionary = {
	"backward": "Jump_Backward",
	"standing": "Jump_Standing",
	"standing_alt": "Jump_Standing_Alt",
	"running": "Jump_Running",
}

## 觸發跳躍動畫
## 使用分段動畫系統：START → LOOP → LAND
func _trigger_jump_animation() -> void:
	# 使用分段動畫系統
	_trigger_jump_start_animation()


## 觸發起跳動畫 (Phase 1: START)
func _trigger_jump_start_animation() -> void:
	if not anim_player:
		return
	
	air.jump_phase = JumpPhase.START
	air.jump_start_timer = 0.0
	
	# 禁用 AnimationTree
	if anim_tree:
		anim_tree.active = false
	
	# 加速播放起跳動畫（讓它在 JUMP_START_DURATION 內完成）
	anim_player.play("movement/" + JUMP_START_ANIM)
	var anim_length = anim_player.current_animation_length
	if anim_length > 0:
		anim_player.speed_scale = anim_length / JUMP_START_DURATION
	
	# 連接完成信號
	if not anim_player.animation_finished.is_connected(_on_jump_phase_finished):
		anim_player.animation_finished.connect(_on_jump_phase_finished)

## 觸發空中循環動畫 (Phase 2: LOOP)
func _trigger_jump_loop_animation() -> void:
	if not anim_player:
		return
	
	air.jump_phase = JumpPhase.LOOP
	anim_player.speed_scale = 1.0 # 恢復正常速度
	anim_player.play("movement/" + JUMP_LOOP_ANIM)
	# 空中循環不需要連接完成信號，由 _physics_process 檢測落地

## 觸發落地動畫 (Phase 3: LAND)
const LAND_ANIM_SPEED: float = 2.5 # 落地動畫播放速度

func _trigger_land_animation() -> void:
	if not anim_player:
		return
	
	air.jump_phase = JumpPhase.LAND
	_set_motion_state(MovementEnums.MotionState.LANDING) # 鎖定移動
	anim_player.speed_scale = LAND_ANIM_SPEED # 加快播放
	anim_player.play("movement/" + JUMP_LAND_ANIM)
	if verbose_debug: print(">>> LAND: _is_landing = true, playing ", JUMP_LAND_ANIM, " at speed ", LAND_ANIM_SPEED)
	
	# 連接完成信號
	if not anim_player.animation_finished.is_connected(_on_jump_phase_finished):
		anim_player.animation_finished.connect(_on_jump_phase_finished)

## 觸發跑步停止動畫 (Run To Stop)
## 當玩家放開移動鍵時，播放停止動畫取代 AnimationTree 自然混合
func _trigger_run_to_stop_animation() -> void:
	# ★ 停止動畫已啟用 (Phase 3)
	if not anim_player:
		return
	
	_set_motion_state(MovementEnums.MotionState.STOPPING)
	
	# 記錄觸發時的速度
	var trigger_speed = _prev_h_speed
	
	# 記錄當前 Hips 位置（動畫開始前的位置）
	if _skeleton:
		var hips_idx = _skeleton.find_bone("Hips")
		if hips_idx >= 0:
			_stopping_hips_pos = _skeleton.get_bone_pose_position(hips_idx)
			if verbose_debug: print(">>> Captured Hips pos: ", _stopping_hips_pos)
	
	# 立即停止移動（防止 Root Motion 滑動）
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 # 也鎖定垂直速度
	
	# 記錄當前旋轉（防止停止動畫重置方向）
	_stopping_rotation = rotation.y
	
	# 不禁用 AnimationTree - 讓它參與混合過渡
	# 直接用 AnimationPlayer 播放，使用 cross-fade
	
	# === 根據速度選擇動畫和參數 ===
	var blend_time: float = 0.15
	var speed_scale: float = 1.0
	var anim_name: String = ""
	
	# 根據移動方向選擇對應的停止動畫
	var direction_suffix = _get_stop_direction_suffix()
	
	if trigger_speed >= 8.0:
		# 衝刺：Run_To_Stop 慢放
		anim_name = "Run_To_Stop" + direction_suffix
		speed_scale = 0.9
		blend_time = 0.1
	elif trigger_speed >= 5.0:
		# 跑步：Run_To_Stop 正常
		anim_name = "Run_To_Stop" + direction_suffix
		speed_scale = 1.0
		blend_time = 0.15
	else:
		# 走路：使用 Run_To_Stop 加快播放（移除 Stop_Walking）
		anim_name = "Run_To_Stop" + direction_suffix
		speed_scale = 1.5 # 加快播放讓停止更快
		blend_time = 0.1
	
	# ★ 不禁用 AnimationTree — 禁用會造成 T-Pose
	# AnimationPlayer.play() 的 cross-fade 會自然覆蓋 AnimationTree 的輸出
	# if anim_tree:
	#	anim_tree.active = false
	
	# 記錄當前播放的動畫名稱
	_stopping_anim_name = anim_name
	
	# ★ 強制動畫不循環（Mixamo FBX 可能預設 loop，導致 animation_finished 永遠不觸發）
	var anim_path = "movement/" + anim_name
	var anim = anim_player.get_animation(anim_path)
	if anim:
		anim.loop_mode = Animation.LOOP_NONE
	
	# 播放停止動畫 (帶有 cross-fade 混合)
	anim_player.speed_scale = speed_scale
	anim_player.play(anim_path, blend_time)
	
	var anim_length = anim_player.current_animation_length
	
	# 設置計時器（加小緩衝保證動畫完成）
	_stopping_timer = (anim_length / speed_scale) + 0.1
	
	_stopping_grace_timer = 0.05 # ★ 縮短到 50ms，幾乎立即可取消
	
	if verbose_debug: print(">>> Stop Anim: %s, speed=%.1f, blend=%.2fs, duration=%.2fs (one_step)" % [anim_name, trigger_speed, blend_time, _stopping_timer])
	
	# 連接完成信號
	if not anim_player.animation_finished.is_connected(_on_run_to_stop_finished):
		anim_player.animation_finished.connect(_on_run_to_stop_finished)

## Run To Stop 動畫完成回調
func _on_run_to_stop_finished(finished_anim: String) -> void:
	if not finished_anim.contains("Run_To_Stop"):
		return
	
	if verbose_debug: print(">>> Stop anim finished: %s" % finished_anim)
	
	_set_motion_state(MovementEnums.MotionState.IDLE)
	_stopping_anim_name = ""
	anim_player.speed_scale = 1.0
	
	# 斷開信號
	if anim_player.animation_finished.is_connected(_on_run_to_stop_finished):
		anim_player.animation_finished.disconnect(_on_run_to_stop_finished)
	
	# 直接恢復 AnimationTree（不使用 Recovery 動畫）
	_restore_animation_tree()

## 恢復 AnimationTree
func _restore_animation_tree() -> void:
	anim_player.stop()
	
	if anim_tree:
		_blend_position = Vector2.ZERO
		anim_tree.set("parameters/movement/stand_movement/blend_position", Vector2.ZERO)
		anim_tree.set("parameters/movement/crouch_movement/blend_position", Vector2.ZERO)
		anim_tree.active = true
		
		var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel("movement")
	
	# 重置停止動畫觸發標誌
	_stop_anim_triggered = false
	air.air_time = 0.0 # ★ 重置離地時間，避免停止動畫後立即觸發 FALLING
	
	# ★ 重置速度曲線狀態（防止減速模式卡住）
	_curve_time = 0.0
	_curve_start_velocity = Vector3.ZERO
	_curve_target_velocity = Vector3.ZERO
	_is_accelerating = true
	_curve_was_moving = false
	
	if verbose_debug: print(">>> AnimationTree restored, active=%s" % anim_tree.active)

## 根據停止動畫方向決定 Recovery 動畫
func _get_recovery_animation(stop_anim: String) -> String:
	if "Left" in stop_anim:
		return "Turn_Left" # 左走停止 → 反向播放 Turn_Left (側面→正面)
	elif "Right" in stop_anim:
		return "Turn_Right" # 右走停止 → 反向播放 Turn_Right (側面→正面)
	# Forward/Backward 不需要 Recovery
	return ""

## 反向播放 Recovery 動畫
func _play_recovery_reversed(anim_name: String) -> void:
	var full_path = "movement/" + anim_name
	var anim = anim_player.get_animation(full_path)
	if not anim:
		_restore_animation_tree()
		return
	
	# 從動畫結尾開始，反向播放（速度較慢以自然過渡）
	var speed = 1.5 # 播放速度（加快）
	anim_player.speed_scale = - speed # 負數 = 反向播放
	anim_player.play(full_path, 0.15)
	anim_player.seek(anim.length) # 跳到結尾開始反向播
	
	# ★ 使用計時器確保完成（animation_finished 對反向播放不可靠）
	var duration = anim.length / speed
	await get_tree().create_timer(duration).timeout
	_on_recovery_finished(anim_name)

## Recovery 動畫完成回調
func _on_recovery_finished(_anim: String) -> void:
	if anim_player.animation_finished.is_connected(_on_recovery_finished):
		anim_player.animation_finished.disconnect(_on_recovery_finished)
	
	anim_player.speed_scale = 1.0 # 恢復正常速度
	if verbose_debug: print(">>> Recovery finished, restoring AnimationTree")
	_restore_animation_tree()

## ★ 站立轉身動畫：當相機旋轉超過閾值時觸發
func _trigger_standing_turn(direction: String) -> void:
	if not anim_player:
		return
	
	var turn_anim = "Turn_Left" if direction == "left" else "Turn_Right"
	
	# 檢查動畫是否存在
	if not anim_player.has_animation("movement/" + turn_anim):
		if verbose_debug: print(">>> Turn animation not found: %s" % turn_anim)
		_accumulated_rotation = 0.0
		return
	
	if verbose_debug: print(">>> Standing turn: %s (accumulated: %.1f deg)" % [direction, _accumulated_rotation])
	
	_is_turning = true
	_turn_direction = -1 if direction == "left" else 1
	_accumulated_rotation = 0.0
	
	# 禁用 AnimationTree，由 AnimationPlayer 直接播放
	if anim_tree:
		anim_tree.active = false
	
	anim_player.speed_scale = 1.2 # 稍微加快
	anim_player.play("movement/" + turn_anim, 0.15)
	
	# 連接完成信號
	if not anim_player.animation_finished.is_connected(_on_standing_turn_finished):
		anim_player.animation_finished.connect(_on_standing_turn_finished)

## 站立轉身動畫完成回調
func _on_standing_turn_finished(_anim: String) -> void:
	if anim_player.animation_finished.is_connected(_on_standing_turn_finished):
		anim_player.animation_finished.disconnect(_on_standing_turn_finished)
	
	_is_turning = false
	_turn_direction = 0
	anim_player.speed_scale = 1.0
	
	if verbose_debug: print(">>> Standing turn finished")
	_restore_animation_tree()

## 取消停止動畫（被輸入打斷）
func _cancel_stop_animation() -> void:
	if not _is_stopping:
		return
	
	_set_motion_state(MovementEnums.MotionState.IDLE)
	_stopping_anim_name = ""
	anim_player.speed_scale = 1.0
	anim_player.stop()
	
	# 恢復 AnimationTree
	if anim_tree:
		anim_tree.active = true
		var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel("movement")
	
	# 斷開信號
	if anim_player.animation_finished.is_connected(_on_run_to_stop_finished):
		anim_player.animation_finished.disconnect(_on_run_to_stop_finished)
	
	# ★ 重置速度曲線狀態（防止減速模式卡住）
	_curve_time = 0.0
	_curve_start_velocity = Vector3.ZERO
	_curve_target_velocity = Vector3.ZERO
	_is_accelerating = true
	_curve_was_moving = false
	
	if verbose_debug: print(">>> Stop Anim interrupted! velocity curve reset")

## 鎖定 Hips 位置（延遲執行，在動畫更新後）
func _lock_hips_position() -> void:
	if not _is_stopping or not _skeleton:
		return
	var hips_idx = _skeleton.find_bone("Hips")
	if hips_idx >= 0:
		_skeleton.set_bone_pose_position(hips_idx, _stopping_hips_pos)

## 腳步事件回調（由動畫 Method Track 調用）
## 腳步檢測（使用骨骼 Y 位置）
var _left_foot_was_down: bool = false
var _right_foot_was_down: bool = false
const FOOT_GROUND_THRESHOLD: float = 0.08 # 低於此高度視為著地

func _check_footsteps() -> void:
	if not _skeleton or not _waiting_for_foot:
		return
	
	var left_idx = _skeleton.find_bone("LeftFoot")
	var right_idx = _skeleton.find_bone("RightFoot")
	
	var elapsed = Time.get_ticks_msec() / 1000.0 - _foot_grounded_time
	
	if left_idx < 0 or right_idx < 0:
		# 找不到骨骼，使用備用邏輯：MIN_MOVE_TIME 後強制停止
		if elapsed > MIN_MOVE_TIME:
			if verbose_debug: print(">>> Footstep fallback: elapsed=%.2f, triggering stop" % elapsed)
			_trigger_footstep_stop()
		return
	
	# 獲取腳部世界位置
	var left_pos = _skeleton.get_bone_global_pose(left_idx).origin
	var right_pos = _skeleton.get_bone_global_pose(right_idx).origin
	
	# 檢測腳是否著地（Y 低於閾值）
	var left_down = left_pos.y < FOOT_GROUND_THRESHOLD
	var right_down = right_pos.y < FOOT_GROUND_THRESHOLD
	
	# 檢測腳剛著地（從高變低）
	if left_down and not _left_foot_was_down:
		_last_foot = "left"
		if verbose_debug: print(">>> Left foot landed! elapsed=%.2f" % elapsed)
		_trigger_footstep_stop()
	elif right_down and not _right_foot_was_down:
		_last_foot = "right"
		if verbose_debug: print(">>> Right foot landed! elapsed=%.2f" % elapsed)
		_trigger_footstep_stop()
	elif elapsed > MIN_MOVE_TIME:
		# ★ 安全機制：超過最小移動時間後強制觸發停止
		# 這確保左右移動也能完成一步
		if verbose_debug: print(">>> Footstep timeout: elapsed=%.2f > MIN_MOVE_TIME, forcing stop" % elapsed)
		_trigger_footstep_stop()
	
	_left_foot_was_down = left_down
	_right_foot_was_down = right_down

## 腳步同步停止：播放停止動畫
## 根據當前移動方向返回停止動畫的方向後綴
## 使用 _blend_position 判斷：
##   - Forward: y > 0.3
##   - Backward: y < -0.3
##   - Left: x < -0.3
##   - Right: x > 0.3
##   - 其他情況：Forward（預設）
func _get_stop_direction_suffix() -> String:
	# ★ Souls-like：角色已面向移動方向，使用基本停止動畫
	# 注意：如果有方向性動畫 (Run_To_Stop_Forward 等)，改回 "_Forward"
	if verbose_debug: print(">>> Direction: (base) Run_To_Stop")
	return ""

func _trigger_footstep_stop() -> void:
	_waiting_for_foot = false
	_stop_anim_triggered = false # 重置，允許下次正常停止
	if verbose_debug: print(">>> Footstep complete! (%s foot) - triggering stop animation" % _last_foot)
	
	# ★ 腳步同步完成後播放停止動畫
	_trigger_run_to_stop_animation()

## 保留這些函數以防動畫事件修好後使用
func on_foot_left() -> void:
	_last_foot = "left"
	_foot_grounded_time = Time.get_ticks_msec() / 1000.0
	if _waiting_for_foot:
		_trigger_footstep_stop()

func on_foot_right() -> void:
	_last_foot = "right"
	_foot_grounded_time = Time.get_ticks_msec() / 1000.0
	if _waiting_for_foot:
		_trigger_footstep_stop()

## ★ 移動鍵放開事件處理
var _stop_anim_triggered: bool = false # 防止重複觸發

func _on_movement_key_released() -> void:
	# 確保沒有其他移動鍵還在按下
	var still_moving = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or \
					   Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
	
	if still_moving:
		_stop_anim_triggered = false # 重置，下次放開時可以觸發
		return
	
	# 防止重複觸發
	if _stop_anim_triggered:
		return
	
	# 檢查是否可以觸發停止動畫
	if _is_stopping or _is_jumping or _is_landing or not is_on_floor() or stair.on_stairs or stair.blend_weight > 0.01:
		return
	
	# ★ 使用當前速度（按鍵放開時速度還沒降到 0）
	var current_speed = Vector2(velocity.x, velocity.z).length()
	var current_time = Time.get_ticks_msec() / 1000.0
	var move_duration = current_time - _move_start_time
	
	if verbose_debug: print(">>> Key released! speed=%.2f, duration=%.2fs" % [current_speed, move_duration])
	
	# 只有有速度才觸發停止動畫
	if current_speed > 0.3:
		_stop_anim_triggered = true
		
		# ★ 直接觸發停止動畫（不再等待腳步同步）
		if verbose_debug: print(">>> Stop triggered! speed=%.2f" % current_speed)
		_trigger_run_to_stop_animation()

## 檢查是否剛著地（用於腳步同步停止）
func is_foot_just_grounded(max_delay: float = 0.1) -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	return (current_time - _foot_grounded_time) < max_delay

## 跳躍階段動畫完成回調
func _on_jump_phase_finished(anim_name: String) -> void:
	# START 動畫完成 → 切換到 LOOP
	if air.jump_phase == JumpPhase.START:
		_trigger_jump_loop_animation()
		return
	
	# LAND 動畫完成 → 恢復 AnimationTree
	if air.jump_phase == JumpPhase.LAND or anim_name.contains("Land"):
		if verbose_debug: print(">>> LAND FINISHED: _is_landing = false")
		air.jump_phase = JumpPhase.NONE
		_set_motion_state(MovementEnums.MotionState.IDLE)
		anim_player.speed_scale = 1.0 # 恢復正常速度
		
		# ★★★ 關鍵修復：設定落地後快速淡入計時器 ★★★
		air.post_landing_blend_timer = POST_LANDING_BLEND_DURATION
		if verbose_debug: print(">>> 落地後快速淡入期開始: timer=%.2f" % air.post_landing_blend_timer)
		
		# ★★★ 重置平滑位置（避免腳拖曳）★★★
		if _skeleton:
			var right_foot_idx = _skeleton.find_bone("RightFoot")
			var left_foot_idx = _skeleton.find_bone("LeftFoot")
			if right_foot_idx >= 0 and left_foot_idx >= 0:
				var right_bone = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
				var left_bone = _skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)
				# 重置 XZ 位置
				_smoothed_right_ray_xz = Vector2(right_bone.origin.x, right_bone.origin.z)
				_smoothed_left_ray_xz = Vector2(left_bone.origin.x, left_bone.origin.z)
				# ★ 重置 IK smooth 目標（消除剩餘拖曳）
				_smoothed_right_target = right_bone.origin
				_smoothed_left_target = left_bone.origin
				if verbose_debug: print(">>> 落地重置: XZ + IK smooth 目標已同步到當前腳骨位置")
		
		# 恢復 AnimationTree
		if anim_tree:
			anim_tree.active = true
			var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
			if playback:
				anim_tree.set("parameters/conditions/jump", false)
				playback.travel("movement")
		
		# 斷開信號
		if anim_player.animation_finished.is_connected(_on_jump_phase_finished):
			anim_player.animation_finished.disconnect(_on_jump_phase_finished)

## 根據移動狀態選擇跳躍類型
func _select_jump_type() -> String:
	# 直接獲取輸入
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y += 1 # 前進
	if Input.is_key_pressed(KEY_S): input_dir.y -= 1 # 後退
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	
	var is_sprinting = Input.is_key_pressed(KEY_SHIFT) and not _is_crouching
	var speed = velocity.length()
	
	# 1. 向後跳（按S鍵）
	if input_dir.y < -0.1:
		return "backward"
	
	# 2. 衝刺跳 / 跑步跳
	if (is_sprinting or speed > movement_data.walk_speed) and input_dir.y > 0.1:
		return "running"
	
	# 3. 站立/走路跳（隨機選擇變體）
	return ["standing", "standing_alt"].pick_random()

## 更新地面檢測資訊
func _update_ground_info() -> void:
	if not ground_ray:
		return
	
	# 更新射線長度
	ground_ray.target_position = Vector3(0, -ground_check_distance, 0)
	ground_ray.force_raycast_update()
	
	if ground_ray.is_colliding():
		ground.info["is_grounded"] = true
		ground.info["surface_normal"] = ground_ray.get_collision_normal()
		ground.info["collision_point"] = ground_ray.get_collision_point()
		ground.info["distance"] = global_position.y - ground_ray.get_collision_point().y
		ground.info["collider"] = ground_ray.get_collider()
	else:
		ground.info["is_grounded"] = false
		ground.info["surface_normal"] = Vector3.UP
		ground.info["collision_point"] = global_position + Vector3(0, -ground_check_distance, 0)
		ground.info["distance"] = ground_check_distance
		ground.info["collider"] = null

## 獲取地面資訊
func get_ground_info() -> Dictionary:
	return ground.info

## 是否在斜坡上
func is_on_slope() -> bool:
	return ground.info["is_grounded"] and ground.info["surface_normal"].dot(Vector3.UP) < 0.95

## 獲取斜坡角度 (度)
func get_slope_angle() -> float:
	if not ground.info["is_grounded"]:
		return 0.0
	return rad_to_deg(acos(ground.info["surface_normal"].dot(Vector3.UP)))


#region ========== Jump To Stage 跳上平台系統 ==========

## 偵測前方是否有可跳上的平台
## 返回：是否偵測到可跳上的平台
func _detect_platform_ahead() -> bool:
	if not platform_forward_ray or not platform_land_ray:
		if verbose_debug: print(">>> 平台偵測: 射線節點不存在!")
		return false
	
	# 更新射線方向（跟隨角色面向）
	_update_platform_rays_direction()
	
	# 強制更新射線
	platform_forward_ray.force_raycast_update()
	platform_land_ray.force_raycast_update()
	
	# 1. 檢查前方是否有障礙物（平台的側面）
	var forward_hit = platform_forward_ray.is_colliding()
	if verbose_debug: print(">>> 平台偵測 Step1: 前方射線碰撞 = ", forward_hit)
	if not forward_hit:
		return false
	
	# 2. 檢查落點射線是否偵測到平台表面
	var land_hit = platform_land_ray.is_colliding()
	if verbose_debug: print(">>> 平台偵測 Step2: 落點射線碰撞 = ", land_hit, " 落點射線位置: ", platform_land_ray.global_position)
	if not land_hit:
		return false
	
	# 3. 計算平台高度
	var land_point = platform_land_ray.get_collision_point()
	var height_diff = land_point.y - global_position.y
	if verbose_debug: print(">>> 平台偵測 Step3: 高度差 = %.2f m (範圍: %.1f - %.1f)" % [height_diff, MIN_PLATFORM_HEIGHT, MAX_PLATFORM_HEIGHT])
	
	# 4. 檢查高度是否在有效範圍內
	if height_diff < MIN_PLATFORM_HEIGHT or height_diff > MAX_PLATFORM_HEIGHT:
		if verbose_debug: print(">>> 平台偵測: 高度超出範圍!")
		return false
	
	# 5. 儲存偵測到的平台位置
	_detected_platform_pos = land_point
	if verbose_debug: print(">>> 偵測到平台! 高度差: %.2f m, 位置: %s" % [height_diff, land_point])
	
	return true

## 更新平台偵測射線的方向（跟隨角色面向）
func _update_platform_rays_direction() -> void:
	if not platform_forward_ray or not platform_land_ray:
		return
	
	# 確保射線啟用
	platform_forward_ray.enabled = true
	platform_land_ray.enabled = true
	
	# 前方射線使用局部座標 (local -Z 是角色前方)
	# target_position 是相對於射線節點的局部座標
	platform_forward_ray.target_position = Vector3(0, 0, -FORWARD_DETECT_RANGE)
	
	# 落點射線需要放在角色前方上方，使用世界座標設置位置
	var forward_world = - global_transform.basis.z.normalized()
	platform_land_ray.global_position = global_position + forward_world * 1.0 + Vector3.UP * 3.0
	# 落點射線向下偵測
	platform_land_ray.target_position = Vector3(0, -3.5, 0)

## 觸發跳上平台動畫
func _trigger_jump_to_stage() -> void:
	if not anim_player:
		return
	
	if verbose_debug: print(">>> 觸發 Jump_ToStage!")
	
	air.jump_phase = JumpPhase.START # 使用 START 階段
	air.jump_to_type = JumpToType.TO_STAGE
	
	# 禁用 AnimationTree
	if anim_tree:
		anim_tree.active = false
	
	# 播放跳上平台動畫（加快播放）
	var anim_path = "movement/" + JUMP_TO_STAGE_ANIM
	anim_player.speed_scale = 1.5 # ★ 加快動畫
	anim_player.play(anim_path)
	
	# 從 Animation 資源獲取正確的動畫長度（考慮加速）
	var anim = anim_player.get_animation(anim_path)
	var anim_length = (anim.length if anim else 1.5) / 1.5 # 實際播放時間
	if verbose_debug: print(">>> Jump_ToStage 動畫長度: ", anim_length, " 秒 (1.5x speed)")
	
	# 使用 Tween 將角色移動到平台位置（延遲開始，配合動畫）
	_tween_to_platform(_detected_platform_pos, anim_length)
	
	# 連接完成信號
	if not anim_player.animation_finished.is_connected(_on_jump_to_stage_finished):
		anim_player.animation_finished.connect(_on_jump_to_stage_finished)

## Tween 移動到平台（調整曲線匹配動畫）
## ★ 核心問題：動畫腳踩下的時機要對準角色實際到達平台高度的時機
func _tween_to_platform(target_pos: Vector3, duration: float) -> void:
	var tween = create_tween()
	
	# 計算起點
	var start_pos = global_position
	
	# ★ 延長初始延遲，讓動畫先跑（動畫會先抬腳）
	# 物理移動要「跟隨」動畫，而不是「領先」動畫
	
	# 階段 1：較長延遲（等動畫抬腳完成）- 35% 時間
	tween.tween_interval(duration * 0.35)
	
	# 階段 2：緩慢上升到平台高度 - 30% 時間
	# 動畫在 60-70% 時腳開始落下，物理要稍晚到達避免腳陷入
	var mid_pos = Vector3(
		lerp(start_pos.x, target_pos.x, 0.4),
		target_pos.y + 0.1, # 稍微高於平台，避免腳陷入
		lerp(start_pos.z, target_pos.z, 0.4)
	)
	tween.tween_property(self , "global_position", mid_pos, duration * 0.30) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# 階段 3：滑動到目標位置並微降 - 35% 時間
	tween.tween_property(self , "global_position", target_pos, duration * 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	# 啟動腳部 IK 混合 (如果有設置 IK 節點)
	_start_foot_ik_blend(target_pos, duration)

## Jump_ToStage 動畫完成回調
func _on_jump_to_stage_finished(anim_name: String) -> void:
	if not anim_name.contains("ToStage"):
		return
	
	if verbose_debug: print(">>> Jump_ToStage 完成!")
	
	air.jump_phase = JumpPhase.NONE
	air.jump_to_type = JumpToType.NORMAL
	_set_motion_state(MovementEnums.MotionState.IDLE)
	
	# ★ 啟用 Foot Locking（過渡期間穩定腳部）
	_activate_foot_lock()
	
	# 恢復 AnimationTree
	if anim_tree:
		anim_tree.active = true
		var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel("movement")
	
	# 斷開信號
	if anim_player.animation_finished.is_connected(_on_jump_to_stage_finished):
		anim_player.animation_finished.disconnect(_on_jump_to_stage_finished)
	
	# 重置腳部 IK (延遲到 foot lock 結束後)
	# _reset_foot_ik()  # 由 foot lock 系統處理

#region ========== Jump From Stage 跳下平台系統 ==========

## 偵測前方是否有可跳下的邊緣
## 返回：是否偵測到可跳下的邊緣
func _detect_ledge_ahead() -> bool:
	# 使用前向射線偵測前方是否沒有地面（懸崖邊緣）
	var forward_dir = - transform.basis.z.normalized()
	var check_pos = global_position + forward_dir * 0.8 + Vector3.UP * 0.1
	
	# 向下射線偵測
	var space_state = get_world_3d().direct_space_state
	var ray_params = PhysicsRayQueryParameters3D.create(
		check_pos,
		check_pos + Vector3.DOWN * 3.0 # 最大偵測 3 米落差
	)
	ray_params.exclude = [ self ]
	
	var result = space_state.intersect_ray(ray_params)
	if not result:
		if verbose_debug: print(">>> 邊緣偵測: 前方沒有地面（太深或無地面）")
		return false
	
	var ground_point = result.position
	var height_diff = global_position.y - ground_point.y
	
	# 檢查高度是否在可跳下範圍內
	if height_diff < MIN_PLATFORM_HEIGHT or height_diff > MAX_PLATFORM_HEIGHT:
		if verbose_debug: print(">>> 邊緣偵測: 高度差超出範圍 (%.2f m)" % height_diff)
		return false
	
	# 儲存落點位置
	_detected_drop_pos = ground_point + forward_dir * 0.3 # 稍微往前一點
	if verbose_debug: print(">>> 偵測到邊緣! 高度差: %.2f m, 落點: %s" % [height_diff, _detected_drop_pos])
	
	return true

## 觸發跳下平台動畫
func _trigger_jump_from_stage() -> void:
	if not anim_player:
		return
	
	if verbose_debug: print(">>> 觸發 Jump_FromStage!")
	
	air.jump_phase = JumpPhase.START
	air.jump_to_type = JumpToType.FROM_STAGE
	_set_motion_state(MovementEnums.MotionState.JUMPING)
	
	# 禁用 AnimationTree
	if anim_tree:
		anim_tree.active = false
	
	# ★ 禁用 IK 以防止干擾
	_reset_foot_ik()
	
	# 播放跳下平台動畫
	var anim_path = "movement/" + JUMP_FROM_STAGE_ANIM
	
	# 使用 seek(0, true) 從頭開始並更新，避免閃爍
	anim_player.speed_scale = 1.8
	anim_player.play(anim_path)
	anim_player.seek(0, true) # ★ 立即更新到第一幀
	
	# 從 Animation 資源獲取正確的動畫長度（考慮加速）
	var anim = anim_player.get_animation(anim_path)
	var anim_length = (anim.length if anim else 1.0) / 1.8 # 實際播放時間
	if verbose_debug: print(">>> Jump_FromStage 動畫長度: ", anim_length, " 秒 (1.8x speed)")
	
	# 使用 Tween 將角色移動到落點位置
	_tween_down_from_platform(_detected_drop_pos, anim_length)
	
	# 連接完成信號
	if not anim_player.animation_finished.is_connected(_on_jump_from_stage_finished):
		anim_player.animation_finished.connect(_on_jump_from_stage_finished)

## Tween 下降到平台（更真實的重力感）
## ★ 動畫加速後，物理也要更快更自然
func _tween_down_from_platform(target_pos: Vector3, duration: float) -> void:
	var tween = create_tween()
	
	# ★ 縮短延遲，快速下落，符合重力加速
	
	# 階段 1：短延遲（動畫抬腳）- 15% 時間
	tween.tween_interval(duration * 0.15)
	
	# 階段 2：快速下落（重力加速）- 60% 時間
	# 使用 EASE_IN（加速）讓下落越來越快，符合重力
	tween.tween_property(self , "global_position", target_pos, duration * 0.60) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# 階段 3：落地緩衝 - 25% 時間
	tween.tween_property(self , "global_position", target_pos, duration * 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

## Jump_FromStage 動畫完成回調
func _on_jump_from_stage_finished(anim_name: String) -> void:
	# 檢查是否是跳下平台相關的動畫
	if not (anim_name.contains("Landing") or anim_name.contains("Down_Platform") or anim_name.contains("FromStage")):
		return
	
	if verbose_debug: print(">>> Jump_FromStage 完成! 動畫: ", anim_name)
	
	air.jump_phase = JumpPhase.NONE
	air.jump_to_type = JumpToType.NORMAL
	_set_motion_state(MovementEnums.MotionState.IDLE)
	
	# ★ 確保角色貼地（修復陷入地面問題）
	if is_on_floor():
		# 使用 floor_snap 確保正確貼地
		apply_floor_snap()
	
	# ★ 重置 IK
	_reset_foot_ik()
	
	# 恢復 AnimationTree
	if anim_tree:
		anim_tree.active = true
		var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if playback:
			playback.travel("movement")
	
	# 斷開信號
	if anim_player.animation_finished.is_connected(_on_jump_from_stage_finished):
		anim_player.animation_finished.disconnect(_on_jump_from_stage_finished)
	
	# 重置腳部 IK
	_reset_foot_ik()

#endregion

#region Smart Foot IK (Ground Locomotion)

var _skeleton: Skeleton3D = null
var _ik_active: bool = false
var _right_ik_weight: float = 0.0
var _left_ik_weight: float = 0.0
var _ik_target_platform_y: float = 0.0

# 智能 IK 擴展變量
var _ground_ik_enabled: bool = true # 地面行走 IK 開關
var _smoothed_left_target: Vector3 = Vector3.ZERO
var _smoothed_right_target: Vector3 = Vector3.ZERO
var _pelvis_offset: float = 0.0
var _target_pelvis_offset: float = 0.0
var _visuals_node: Node3D = null # ★ 用於偏移整體模型（代替 Hips 骨頭）
var _right_ground_normal: Vector3 = Vector3.UP # ★ 右腳地面法線
var _left_ground_normal: Vector3 = Vector3.UP # ★ 左腳地面法線
var _right_spring_arm: SpringArm3D = null # ★ (已棄用)
var _left_spring_arm: SpringArm3D = null # ★ (已棄用)
var _ik_needs_reset: bool = false # ★ 落地後需要重置腳部目標

# ★ 支撐腳自適應下降（當骨盆達極限時讓膝蓋彎曲）
var _support_leg_drop: float = 0.0
var _target_support_leg_drop: float = 0.0

# ★ RayCast3D 位置平滑（防止停止動畫時跳動）
var _smoothed_right_ray_xz: Vector2 = Vector2.ZERO
var _smoothed_left_ray_xz: Vector2 = Vector2.ZERO
const RAYCAST_XZ_SMOOTH_SPEED: float = 8.0 # XZ 位置平滑速度

# IK 設定常量
const IK_MAX_WEIGHT_STAND: float = 1.0 # 站立時最大權重
const IK_MAX_WEIGHT_WALK: float = 0.3 # ★ 走路時只做微調（原 0.8 太高）
const IK_MAX_WEIGHT_RUN: float = 0.15 # ★ 跑步時更少調整（原 0.5 太高）
const IK_SMOOTH_SPEED: float = 6.0 # 目標平滑速度（降低減少抖動）
const FOOT_TARGET_SMOOTH: float = 4.0 # 腳部目標位置平滑速度（再降低）
const PELVIS_SMOOTH_SPEED: float = 3.0 # 骨盆平滑速度（再降低）
const MAX_PELVIS_DROP: float = 0.45 # ★ 最大骨盆下降（增加讓腳能到達更深階梯）
const MAX_FOOT_DROP: float = 1.2 # ★ 最大腳部下降（增加檢測範圍）
const MAX_FOOT_RAISE: float = 0.5 # ★ 最大腳部上升（增加以適應更高階梯，原 0.25）
const FOOT_HEIGHT_OFFSET: float = 0.06 # 腳底偏移（稍微抬高讓腳掌平貼地面）
const IK_SLOPE_BOOST: float = 0.5 # 斜坡時額外增加的 IK 權重
const SLOPE_THRESHOLD: float = 0.1 # 斜坡角度閾值（sin 值，約 6 度）
const IK_DEADZONE: float = 0.01 # ★ 死區：忽略小於此值的變化（防止抖動）
const MAX_SUPPORT_LEG_DROP: float = 0.25 # ★ 支撐腳最大下移（增加讓另一腳能到達更遠）

## 計算基於速度和斜坡的 IK 權重
func _calculate_ground_ik_weight() -> float:
	# ★ 樓梯上時調整 IK 權重：上樓降低讓動畫控制更多（膝蓋抬足高），下樓保持高權重讓腳貼台階
	if stair.on_stairs and not _is_jumping and not _is_landing:
		return 0.85 if stair.ascending else 0.7
	
	if not is_on_floor() or _is_jumping or _is_landing:
		return 0.0
	
	# ★ 停止動畫期間保持 IK（讓腳貼地面）
	if _is_stopping:
		return 1.0
	
	# ★ 卡住檢測：有移動輸入但速度接近零（撞牆）
	# 這時動畫在播放跑步，但角色實際上沒有移動，造成 IK 異常
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y += 1
	if Input.is_key_pressed(KEY_S): input_dir.y -= 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	
	var has_input = input_dir.length() > 0.1
	var speed = Vector2(velocity.x, velocity.z).length()
	
	# 有輸入但速度很低 = 卡住了
	if has_input and speed < 0.5:
		return 0.0 # 禁用 IK
	
	# 基礎權重（根據速度）
	var base_weight: float
	if speed < 0.5:
		# 幾乎站立
		base_weight = IK_MAX_WEIGHT_STAND
	elif speed < 3.0:
		# 走路
		base_weight = lerp(IK_MAX_WEIGHT_STAND, IK_MAX_WEIGHT_WALK, (speed - 0.5) / 2.5)
	elif speed < 7.0:
		# 快走/慢跑
		base_weight = lerp(IK_MAX_WEIGHT_WALK, IK_MAX_WEIGHT_RUN, (speed - 3.0) / 4.0)
	else:
		# 衝刺
		base_weight = IK_MAX_WEIGHT_RUN
	
	# ★ 斜坡檢測：根據地面法線計算斜率
	var floor_normal = get_floor_normal()
	var slope_factor = 1.0 - floor_normal.y # 0 = 平地, 1 = 垂直牆
	
	# 如果在斜坡上，增加 IK 權重
	if slope_factor > SLOPE_THRESHOLD:
		# 斜坡越陡，加的權重越多（最多加 IK_SLOPE_BOOST）
		var slope_boost = clamp(slope_factor / 0.5, 0.0, 1.0) * IK_SLOPE_BOOST
		base_weight = clamp(base_weight + slope_boost, 0.0, 1.0)
		# Debug: 斜坡 IK 提升
		if Engine.get_frames_drawn() % 60 == 0:
			if verbose_debug: print(">>> Slope IK boost: slope=%.2f, boost=%.2f, final_weight=%.2f" % [slope_factor, slope_boost, base_weight])
	
	return base_weight

## ★★★ 配置單側 TwoBoneIK3D 骨骼鏈（Runtime Configuration）★★★
## 使用 Mixamo 標準命名：{Side}UpperLeg → {Side}LowerLeg → {Side}Foot
func _configure_leg_ik(ik_node: Node, side: String, foot_target: Marker3D, knee_pole: Marker3D) -> void:
	if not ik_node or not _skeleton:
		return
	
	var upper_name = side + "UpperLeg"
	var lower_name = side + "LowerLeg"
	var foot_name = side + "Foot"
	
	var upper_idx = _skeleton.find_bone(upper_name)
	var lower_idx = _skeleton.find_bone(lower_name)
	var foot_idx = _skeleton.find_bone(foot_name)
	
	if upper_idx < 0 or lower_idx < 0 or foot_idx < 0:
		push_warning("[Foot IK] ⚠ %s 腿骨骼未找到: upper=%d, lower=%d, foot=%d" % [side, upper_idx, lower_idx, foot_idx])
		return
	
	if verbose_debug: print(">>> [IK] %s 骨骼索引: %s=%d, %s=%d, %s=%d" % [side, upper_name, upper_idx, lower_name, lower_idx, foot_name, foot_idx])
	
	# ★ 嘗試使用 add_chain()（Godot 4.6+ 推薦方式）
	var chain_configured = false
	if ik_node.has_method("add_chain"):
		# 清除現有配置
		while ik_node.has_method("get_chain_count") and ik_node.get_chain_count() > 0:
			ik_node.remove_chain(0)
		ik_node.add_chain(
			upper_name, upper_idx, # root bone
			lower_name, lower_idx, # middle bone
			0, # pole direction (default)
			foot_name, foot_idx, # end bone
			false, # use_virtual_end
			false # extend_end_bone
		)
		chain_configured = true
		if verbose_debug: print(">>> [IK] %s: add_chain() 成功" % side)
	
	# ★ 備援：使用 set_indexed()（Pattern C — 適用於所有 Godot 版本）
	if not chain_configured:
		ik_node.set_indexed("settings/0/root_bone_name", upper_name)
		ik_node.set_indexed("settings/0/root_bone", upper_idx)
		ik_node.set_indexed("settings/0/middle_bone_name", lower_name)
		ik_node.set_indexed("settings/0/middle_bone", lower_idx)
		ik_node.set_indexed("settings/0/end_bone_name", foot_name)
		ik_node.set_indexed("settings/0/end_bone", foot_idx)
		ik_node.set_indexed("settings/0/pole_direction", 0)
		if verbose_debug: print(">>> [IK] %s: set_indexed() 備援配置完成" % side)
	
	# ★ 設定 Target Node（使用 get_path_to 動態路徑解析）
	if foot_target:
		ik_node.target_node = ik_node.get_path_to(foot_target)
		if verbose_debug: print(">>> [IK] %s target_node = %s" % [side, ik_node.target_node])
	
	# ★ 設定 Pole Target（控制膝蓋彎曲方向）
	if knee_pole and ik_node.has_method("set"):
		# TwoBoneIK3D 的 pole 設定（如果有 pole_node 屬性）
		if "pole_node" in ik_node:
			ik_node.pole_node = ik_node.get_path_to(knee_pole)
			if verbose_debug: print(">>> [IK] %s pole_node = %s" % [side, ik_node.pole_node])

## ★ 查找 IK 節點（處理 Godot instanced scene 名稱混淆）
## Godot 會把 instanced scene 的子節點名稱加上前綴，如 "Parent#RightLegIK"
## find_child("RightLegIK") 無法匹配，需手動遍歷
func _find_ik_node(skel: Skeleton3D, suffix: String) -> Node:
	# 先嘗試直接查找（無前綴的情況）
	var direct = skel.find_child(suffix, true, false)
	if direct:
		return direct
	# 遍歷所有子節點，匹配 "#suffix" 或完全匹配
	for child in skel.get_children():
		var child_name = child.name as String
		if child_name.ends_with("#" + suffix) or child_name == suffix:
			return child
	return null

## 初始化 IK 節點引用
func _setup_foot_ik_nodes() -> void:
	# ★ 使用 _ready() 中已找到的 skeleton 變數（動態查找，支持 GLB 實例）
	_skeleton = skeleton
	_visuals_node = get_node_or_null("Visuals") as Node3D # ★ 用於骨盆偏移
	
	# ★ 動態查找 IK 節點（GLB 內部路徑可能不同）
	if _skeleton:
		# ★ Godot 的 instanced scene 會把子節點名稱加上前綴（如 "Parent#RightLegIK"）
		# 所以用 find_child() 可能找不到，需遍歷子節點匹配含 "#RightLegIK" 的名稱
		right_leg_ik = _find_ik_node(_skeleton, "RightLegIK")
		left_leg_ik = _find_ik_node(_skeleton, "LeftLegIK")
	else:
		right_leg_ik = null
		left_leg_ik = null
		push_warning("[Foot IK] ⚠ Skeleton3D 未找到，IK 功能禁用")
	
	# ★ 使用 ShapeCast3D（球形碰撞體，更準確）
	_right_foot_ray = get_node_or_null("RightFootShape") as ShapeCast3D
	_left_foot_ray = get_node_or_null("LeftFootShape") as ShapeCast3D
	
	# ★ FootTarget 直接在 Player 下
	right_foot_target = get_node_or_null("RightFootTarget") as Marker3D
	left_foot_target = get_node_or_null("LeftFootTarget") as Marker3D
	
	# ★ KneePole（IK 彎曲方向控制 — 場景文件已配置 pole_node 路徑）
	var _right_knee_pole = get_node_or_null("RightKneePole") as Marker3D
	var _left_knee_pole = get_node_or_null("LeftKneePole") as Marker3D
	
	if _right_foot_ray and _left_foot_ray:
		if verbose_debug: print(">>> ShapeCast3D 腳部節點已找到!")
	
	if right_leg_ik and left_leg_ik and _skeleton:
		if verbose_debug: print(">>> Foot IK 節點已找到!")
		
		# ★ 場景文件已配置完整骨骼鏈（bone indices, target_node, pole_node）
		# 不需要 runtime 重新配置，直接驗證並啟用
		var r_setting = right_leg_ik.get("setting_count")
		var l_setting = left_leg_ik.get("setting_count")
		if verbose_debug: print(">>> [IK] RightLegIK settings: %s, LeftLegIK settings: %s" % [r_setting, l_setting])
		
		# ★ 初始化：influence=0, active=false
		# TwoBoneIK3D active=true 即使 influence=0 也會干擾 AnimationPlayer
		# 只在需要時才啟用（由 _update_ground_locomotion_ik 動態控制）
		if not disable_ik_code:
			right_leg_ik.influence = 0.0
			left_leg_ik.influence = 0.0
			right_leg_ik.active = false
			left_leg_ik.active = false
			if verbose_debug: print(">>> TwoBoneIK3D READY (active=false, controlled by code)")
		else:
			if verbose_debug: print(">>> TwoBoneIK3D IK code DISABLED, skipping initialization override")
		
		# ★ Debug: 驗證 target_node 路徑
		if right_foot_target:
			if verbose_debug: print(">>> RightLegIK target_node → %s" % right_leg_ik.target_node)
		if left_foot_target:
			if verbose_debug: print(">>> LeftLegIK target_node → %s" % left_leg_ik.target_node)
	else:
		if verbose_debug: print(">>> Foot IK 節點未設置 (可選功能)")
		if not right_leg_ik: print(">>>   - RightLegIK: 未找到")
		if not left_leg_ik: print(">>>   - LeftLegIK: 未找到")
		if not _skeleton: print(">>>   - Skeleton3D: 未找到")
	
	if _skeleton:
		if verbose_debug: print(">>> Skeleton3D 已找到!")
		# ★ 注意：不再強制覆蓋 modifier_callback_mode_process，避免 T-Pose
		# IK 系統透過 _physics_process 設定目標位置，modifier 可用預設 IDLE 模式
		if verbose_debug: print(">>> Skeleton modifier_callback_mode_process = %s" % _skeleton.modifier_callback_mode_process)
		
		# ★ Debug: 列出所有 Skeleton Modifier 子節點
		var modifiers = []
		for child in _skeleton.get_children():
			if child is SkeletonModifier3D:
				modifiers.append(child.name)
		if verbose_debug: print(">>> Skeleton modifiers: %s" % [modifiers])
		
		# ★ Debug: 驗證 TwoBoneIK3D 骨骼索引
		if right_leg_ik:
			var root_idx = right_leg_ik.get("settings/0/root_bone")
			var mid_idx = right_leg_ik.get("settings/0/middle_bone")
			var end_idx = right_leg_ik.get("settings/0/end_bone")
			var root_name = _skeleton.get_bone_name(root_idx) if root_idx >= 0 else "INVALID"
			var mid_name = _skeleton.get_bone_name(mid_idx) if mid_idx >= 0 else "INVALID"
			var end_name = _skeleton.get_bone_name(end_idx) if end_idx >= 0 else "INVALID"
			if verbose_debug: print(">>> IK bones: root=%d(%s), mid=%d(%s), end=%d(%s)" % [
				root_idx, root_name, mid_idx, mid_name, end_idx, end_name
			])
	
	# ★ 確保 AnimationTree 也使用 IDLE 回調模式
	if anim_tree:
		# AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE = 1
		anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		if verbose_debug: print(">>> AnimationTree callback_mode_process = IDLE")
	
	# ★ 初始化手部 IK（跟腳部 IK 同樣模式：influence=0, active=true）
	_setup_arm_ik_nodes()

## 開始腳部 IK 混合 (分開控制左右腳時序)
func _start_foot_ik_blend(target_pos: Vector3, duration: float) -> void:
	if not right_leg_ik or not left_leg_ik:
		return
	
	_ik_active = true
	_ik_target_platform_y = target_pos.y
	
	# 設置初始目標位置
	var foot_height = 0.05
	if right_foot_target:
		right_foot_target.global_position = target_pos + Vector3(0.12, foot_height, 0)
	if left_foot_target:
		left_foot_target.global_position = target_pos + Vector3(-0.12, foot_height, 0)
	
	# 右腳先落地 (60% 開始)
	var right_start = duration * 0.60
	var right_blend = duration * 0.25
	
	# 左腳延遲 (75% 開始)
	var left_start = duration * 0.75
	var left_blend = duration * 0.20
	
	# 右腳 Tween
	var right_tween = create_tween()
	right_tween.tween_interval(right_start)
	right_tween.tween_method(_set_right_ik_weight, 0.0, 1.0, right_blend)
	
	# 左腳 Tween (延遲)
	var left_tween = create_tween()
	left_tween.tween_interval(left_start)
	left_tween.tween_method(_set_left_ik_weight, 0.0, 1.0, left_blend)
	
	if verbose_debug: print(">>> Foot IK: 右腳 %.2fs 開始, 左腳 %.2fs 開始" % [right_start, left_start])

## 設置右腳 IK 權重
func _set_right_ik_weight(weight: float) -> void:
	_right_ik_weight = weight
	if right_leg_ik:
		right_leg_ik.set("influence", weight)

## 設置左腳 IK 權重
func _set_left_ik_weight(weight: float) -> void:
	_left_ik_weight = weight
	if left_leg_ik:
		left_leg_ik.set("influence", weight)

## 每幀更新腳部 IK 目標 (在 _physics_process 中調用)
func _update_foot_ik_targets() -> void:
	if not _ik_active or not _skeleton:
		return
	
	# 獲取腳骨全局位置
	var right_foot_idx = _skeleton.find_bone("RightFoot")
	var left_foot_idx = _skeleton.find_bone("LeftFoot")
	

	# ★ 使用 SpringArm3D 模式（更穩定）
	if _right_spring_arm and _left_spring_arm:
		_update_foot_ik_with_springarm(right_foot_idx, left_foot_idx)
	else:
		# 備用：傳統射線模式
		_update_foot_ik_with_raycast(right_foot_idx, left_foot_idx)
	
	# ★ 處理完兩腳後重置標誌
	if _ik_needs_reset:
		_ik_needs_reset = false

## ★ 使用 SpringArm3D 更新腳部 IK（更穩定，無抖動）
func _update_foot_ik_with_springarm(right_foot_idx: int, left_foot_idx: int) -> void:
	# 更新 SpringArm3D 位置（跟隨腳部骨骼的 X/Z，從高處向下）
	if right_foot_idx >= 0:
		var bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
		# SpringArm 放在腳的 XZ 位置，高度固定在膝蓋附近
		_right_spring_arm.global_position = Vector3(bone_global.origin.x, global_position.y + 0.5, bone_global.origin.z)
		
		# 設置 IK 權重
		if right_leg_ik and _right_ik_weight > 0:
			right_leg_ik.set("influence", _right_ik_weight)
	
	if left_foot_idx >= 0:
		var bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)
		_left_spring_arm.global_position = Vector3(bone_global.origin.x, global_position.y + 0.5, bone_global.origin.z)
		
		if left_leg_ik and _left_ik_weight > 0:
			left_leg_ik.set("influence", _left_ik_weight)

## ★ 備用：傳統射線檢測模式（向後兼容）
func _update_foot_ik_with_raycast(right_foot_idx: int, left_foot_idx: int) -> void:
	# 右腳：檢查腳骨高度，只有當腳接近平台時才應用 IK
	if right_foot_idx >= 0 and right_foot_target:
		var bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
		var foot_above_platform = bone_global.origin.y - _ik_target_platform_y
		
		if foot_above_platform < 0.15 and _right_ik_weight > 0:
			if right_leg_ik:
				right_leg_ik.set("influence", _right_ik_weight)
			var ray_result = _raycast_ground_full(bone_global.origin)
			if ray_result.has("position"):
				var normal = ray_result.get("normal", Vector3.UP)
				var target_pos = ray_result.position + normal * FOOT_HEIGHT_OFFSET
				if _ik_needs_reset:
					right_foot_target.global_position = target_pos
				else:
					var dt = get_physics_process_delta_time()
					right_foot_target.global_position = right_foot_target.global_position.lerp(target_pos, dt * FOOT_TARGET_SMOOTH)
		else:
			if right_leg_ik:
				right_leg_ik.set("influence", 0.0)
	
	# 左腳：同樣邏輯
	if left_foot_idx >= 0 and left_foot_target:
		var bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)
		var foot_above_platform = bone_global.origin.y - _ik_target_platform_y
		
		if foot_above_platform < 0.15 and _left_ik_weight > 0:
			if left_leg_ik:
				left_leg_ik.set("influence", _left_ik_weight)
			var ray_result = _raycast_ground_full(bone_global.origin)
			if ray_result.has("position"):
				var normal = ray_result.get("normal", Vector3.UP)
				var target_pos = ray_result.position + normal * FOOT_HEIGHT_OFFSET
				if _ik_needs_reset:
					left_foot_target.global_position = target_pos
				else:
					var dt = get_physics_process_delta_time()
					left_foot_target.global_position = left_foot_target.global_position.lerp(target_pos, dt * FOOT_TARGET_SMOOTH)
		else:
			if left_leg_ik:
				left_leg_ik.set("influence", 0.0)

## 從位置向下射線檢測地面（返回位置和法線）
func _raycast_ground_full(from_pos: Vector3) -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	# ★ 加大射線範圍讓腳能到達更低的地面
	var ray_start = from_pos + Vector3.UP * 0.5
	var ray_end = from_pos + Vector3.DOWN * 1.0
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [ self ]
	query.collision_mask = 1 # 只檢測地面層
	
	var result = space_state.intersect_ray(query)
	if result:
		return {"position": result.position, "normal": result.normal}
	return {}

## 從位置向下射線檢測地面（只返回位置，向後兼容）
func _raycast_ground(from_pos: Vector3) -> Vector3:
	var result = _raycast_ground_full(from_pos)
	if result.has("position"):
		return result.position
	return Vector3.ZERO

## 重置腳部 IK
func _reset_foot_ik() -> void:
	_ik_active = false
	_right_ik_weight = 0.0
	_left_ik_weight = 0.0
	_ik_blend_weight = 0.0
	_pelvis_offset = 0.0
	_target_pelvis_offset = 0.0
	_support_leg_drop = 0.0
	_target_support_leg_drop = 0.0
	
	if right_leg_ik:
		right_leg_ik.set("influence", 0.0)
	if left_leg_ik:
		left_leg_ik.set("influence", 0.0)
	
	# ★★★ 重置平滑目標到當前腳骨位置（防止落地時腳拖曳）★★★
	if _skeleton:
		var right_foot_idx = _skeleton.find_bone("RightFoot")
		var left_foot_idx = _skeleton.find_bone("LeftFoot")
		
		if right_foot_idx >= 0:
			var pos = (_skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)).origin
			_smoothed_right_target = pos
			_smoothed_right_ray_xz = Vector2(pos.x, pos.z)
		
		if left_foot_idx >= 0:
			var pos = (_skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)).origin
			_smoothed_left_target = pos
			_smoothed_left_ray_xz = Vector2(pos.x, pos.z)
	
	if verbose_debug: print(">>> Foot IK 已重置（含平滑目標）")

## ★★★ 雙層碰撞架構：根據腳的地面檢測調整角色 Y 位置 ★★★
## 注意：膠囊已恢復原尺寸，此功能暫時禁用
func _snap_to_foot_ground(_delta: float) -> void:
	return # 膠囊已貼地，不需要額外調整
	# 只在地面上且不跳躍時執行
	if not is_on_floor() or _is_jumping or _is_landing:
		return
	
	# 獲取兩腳地面高度
	var right_ground_y: float = - INF
	var left_ground_y: float = - INF
	
	if _right_foot_ray and _right_foot_ray.is_colliding():
		right_ground_y = _right_foot_ray.get_collision_point(0).y
	if _left_foot_ray and _left_foot_ray.is_colliding():
		left_ground_y = _left_foot_ray.get_collision_point(0).y
	
	# 如果都沒檢測到地面，跳過
	if right_ground_y == -INF and left_ground_y == -INF:
		return
	
	# 以較高的腳為準（支撐腳）
	var target_ground_y = max(right_ground_y, left_ground_y)
	
	# 計算目標角色 Y 位置（腳底 + 腳踝高度）
	var foot_ankle_height: float = 0.08 # 腳踝到地面高度
	var target_y = target_ground_y + foot_ankle_height
	var current_y = global_position.y
	
	# 只向下調整（防止穿地）
	if target_y < current_y - 0.02: # 2cm 容差
		# 平滑調整
		global_position.y = lerp(current_y, target_y, _delta * 15.0)
	
	# Debug 輸出
	if Engine.get_frames_drawn() % 120 == 0:
		if verbose_debug: print(">>> GroundSnapper: right_y=%.2f, left_y=%.2f, target_y=%.2f, current_y=%.2f" % [
			right_ground_y, left_ground_y, target_y, current_y
		])


## ★ Phase 2：偵測腳骨動畫相位 + Foot Locking（高度比較法）
## 樓梯模式：比較左右腳骨骼本地 Y 高度，較低的腳 = 支撐腳 → 鎖定
## 平地模式：使用 Y 軸速度判斷擺動相/著地相
func _update_foot_phase_weights(delta: float) -> void:
	var right_foot_idx = _skeleton.find_bone("RightFoot")
	var left_foot_idx = _skeleton.find_bone("LeftFoot")
	if right_foot_idx < 0 or left_foot_idx < 0:
		return
	
	# 取得腳骨相對骨架本地 Y 位置（不含角色整體移動）
	var right_y = _skeleton.get_bone_global_pose(right_foot_idx).origin.y
	var left_y = _skeleton.get_bone_global_pose(left_foot_idx).origin.y
	
	# 計算 Y 軸速度（平地相位用）
	var right_vel_y = (right_y - _prev_right_foot_y) / max(delta, 0.001)
	var left_vel_y = (left_y - _prev_left_foot_y) / max(delta, 0.001)
	
	# 更新前幀位置
	_prev_right_foot_y = right_y
	_prev_left_foot_y = left_y
	
	# ★ 樓梯 Foot Locking (Mode B) 已移除
	# 始終用速度判斷相位，保證 foot lock 解除
	_right_foot_locked = false
	_left_foot_locked = false
	_foot_lock_timer = 0.0
	var swing_threshold = 0.02
	var right_target = 0.0 if abs(right_vel_y) > swing_threshold else 1.0
	var left_target = 0.0 if abs(left_vel_y) > swing_threshold else 1.0
	_right_foot_phase_weight = lerp(_right_foot_phase_weight, right_target, delta * 12.0)
	_left_foot_phase_weight = lerp(_left_foot_phase_weight, left_target, delta * 12.0)
	
	# 更新速度歷史
	_prev_right_foot_vel_y = right_vel_y
	_prev_left_foot_vel_y = left_vel_y
	
	# Debug：每 30 幀印出（更頻繁以觀察鎖定行為）
	if Engine.get_frames_drawn() % 30 == 0:
		if verbose_debug: print(">>> [FootPhase] R: y=%.3f phase=%.2f lock=%s | L: y=%.3f phase=%.2f lock=%s | diff=%.3f timer=%.2f" % [
			right_y, _right_foot_phase_weight, _right_foot_locked,
			left_y, _left_foot_phase_weight, _left_foot_locked,
			right_y - left_y, _foot_lock_timer
		])

## ★ 階梯投影：解析式腳步 Y 計算（純數學，零 Raycast）
## 將腳的 XZ 投影到階梯方向，用 floor 除法得到 step_index，再算 Y
func _get_step_y_at(foot_xz: Vector2) -> float:
	if not stair.params_valid or stair.step_depth < 0.01:
		return stair.base_pos.y
	
	var base_xz = Vector2(stair.base_pos.x, stair.base_pos.z)
	var offset = foot_xz - base_xz
	var dist_along_stair = offset.dot(stair.dir_xz)
	
	# step_index：沿階梯方向的距離 / 單階深度
	var step_index: int
	if stair.ascending:
		step_index = floori(dist_along_stair / stair.step_depth)
	else:
		step_index = ceili(dist_along_stair / stair.step_depth)
	
	# 限制 step_index 在合理範圍（±10 階）
	step_index = clampi(step_index, -10, 10)
	
	var result_y = stair.base_pos.y + step_index * stair.step_height_measured
	
	if Engine.get_frames_drawn() % 120 == 0:
		if verbose_debug: print(">>> [StairProj] foot_xz=(%.2f,%.2f) dist=%.3f idx=%d → y=%.3f" % [
			foot_xz.x, foot_xz.y, dist_along_stair, step_index, result_y
		])
	
	return result_y

# ═══════════ PredictIK 預測式樓梯 IK — 核心函數 ═══════════

## ★ 每步一次的地形預測：3 次物理查詢建構高度曲線
## is_left: true=左腳, false=右腳
## ★ StepPerdict() — 精確移植自 PredictIK.cs 行 130-196
func _predict_step_for_foot(is_left: bool) -> void:
	if not _skeleton:
		return
	
	var foot_name = "LeftFoot" if is_left else "RightFoot"
	var foot_idx = _skeleton.find_bone(foot_name)
	if foot_idx < 0:
		return
	
	var foot_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(foot_idx)
	var foot_pos = foot_global.origin
	
	# ★ 原始碼用 transform.forward（角色朝向），不是速度方向
	var forward = - global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var space_state = get_world_3d().direct_space_state
	var exclude_rid = get_rid()
	
	# ── 查詢 1（C# line 136）：從腳上方向下 Raycast 找 StartHit ──
	var start_query = PhysicsRayQueryParameters3D.create(
		foot_pos + Vector3.UP * 0.1,
		foot_pos + Vector3.DOWN * 0.5
	)
	start_query.exclude = [exclude_rid]
	var start_result = space_state.intersect_ray(start_query)
	
	var start_point: Vector3
	if start_result.is_empty():
		start_point = Vector3(foot_pos.x, global_position.y, foot_pos.z)
	else:
		start_point = start_result.position
	
	# ── 查詢 2（C# line 144）：SphereCast → 用 Raycast 代替 ──
	# 從 StartHit + forward * StepLength + UP * (StepHeight + 0.1) 向下
	var end_origin = start_point + forward * PREDICT_STEP_LENGTH + Vector3.UP * (PREDICT_STEP_HEIGHT + 0.1)
	var end_query = PhysicsRayQueryParameters3D.create(
		end_origin,
		end_origin + Vector3.DOWN * (PREDICT_STEP_HEIGHT * 4.0)
	)
	end_query.exclude = [exclude_rid]
	var end_result = space_state.intersect_ray(end_query)
	
	var end_point: Vector3
	if end_result.is_empty():
		end_point = start_point + forward * PREDICT_STEP_LENGTH
	else:
		end_point = end_result.position
	
	# ── 查詢 3（C# line 152）：CapsuleCast → 用中點 Raycast 代替 ──
	var mid_pos = (start_point + end_point) * 0.5
	var mid_origin = mid_pos + Vector3.UP * PREDICT_STEP_HEIGHT
	var mid_query = PhysicsRayQueryParameters3D.create(
		mid_origin,
		mid_origin + Vector3.DOWN * (PREDICT_STEP_HEIGHT * 2.0)
	)
	mid_query.exclude = [exclude_rid]
	var mid_result = space_state.intersect_ray(mid_query)
	var has_center_hit = not mid_result.is_empty()
	var center_hit_point = mid_result.position if has_center_hit else Vector3.ZERO
	
	# ── 建構曲線（C# line 157-158）──
	# ★ 原始碼: curvestartheight = curve[curve.length-1].value - curve[0].value
	var old_curve = _predict_left_curve if is_left else _predict_right_curve
	var curvestartheight: float = 0.0
	if not old_curve.is_empty():
		curvestartheight = old_curve[-1]["h"] - old_curve[0]["h"]
	
	var delta_y = end_point.y - start_point.y
	# curve = Linear(0, curvestartheight, StepLength, curvestartheight + deltaY)
	var curve: Array = []
	curve.append({"d": 0.0, "h": curvestartheight})
	curve.append({"d": PREDICT_STEP_LENGTH, "h": curvestartheight + delta_y})
	
	# ★ 計算 tangent（坡度）（C# line 159-166）
	var tangent: float = 0.0
	if PREDICT_STEP_LENGTH > 0.001:
		tangent = delta_y / PREDICT_STEP_LENGTH
	
	# 路徑上有障礙物（C# line 169-183）
	if has_center_hit:
		var center_h = (center_hit_point - start_point).y
		var linear_mid_h = delta_y * 0.5
		if center_h > linear_mid_h + 0.02:
			var centerpos = (center_hit_point - start_point).dot(forward)
			centerpos = clampf(centerpos, 0.05, PREDICT_STEP_LENGTH - 0.05)
			var key_h = curvestartheight + center_h
			curve.insert(1, {"d": centerpos, "h": key_h})
	
	# ★ 儲存（C# line 194, 202, 207）
	# return StartHit.point → LastPosition = StepPerdict(...)
	if is_left:
		_predict_left_curve = curve
		_predict_last_left_pos = start_point # LastLeftPosition = StartHit.point
		_predict_left_tangent = tangent
	else:
		_predict_right_curve = curve
		_predict_last_right_pos = start_point # LastRightPosition = StartHit.point
		_predict_right_tangent = tangent
	
	if verbose_debug: print(">>> [PredictIK] %s: start_y=%.2f end_y=%.2f Δy=%.3f curvestart=%.3f" % [
		foot_name, start_point.y, end_point.y, delta_y, curvestartheight
	])

## ★ 分段線性插值取值
func _evaluate_predict_curve(curve: Array, distance: float) -> float:
	if curve.is_empty():
		return 0.0
	
	# 限制距離範圍
	var d = clampf(distance, 0.0, PREDICT_STEP_LENGTH)
	
	# 找到 d 所在的區段
	for i in range(curve.size() - 1):
		var p0 = curve[i]
		var p1 = curve[i + 1]
		if d >= p0["d"] and d <= p1["d"]:
			var seg_len = p1["d"] - p0["d"]
			if seg_len < 0.001:
				return p0["h"]
			var t = (d - p0["d"]) / seg_len
			return lerpf(p0["h"], p1["h"], t)
	
	# 超出範圍：返回最後一個點的高度
	return curve[curve.size() - 1]["h"]

## ★ 偵測步態切換並觸發預測
func _check_predict_triggers() -> void:
	# ★ Root Motion 樓梯動畫已有完整膝蓋姿勢，PredictIK 會衝突
	# 只在沒有 root motion 時才啟用 PredictIK
	var should_predict = stair.on_stairs and not stair.root_motion_active
	
	# 進入樓梯時：初始化（對應 C# Start()）
	if should_predict and not _predict_ik_active:
		_predict_ik_active = true
		_predict_initialized = false
		
		# ★ C# Start(): LastLeftPosition.y = transform.position.y
		if _skeleton:
			var r_idx = _skeleton.find_bone("RightFoot")
			var l_idx = _skeleton.find_bone("LeftFoot")
			if r_idx >= 0:
				var rg = _skeleton.global_transform * _skeleton.get_bone_global_pose(r_idx)
				_predict_last_right_pos = rg.origin
				_predict_last_right_pos.y = global_position.y # ★ root Y
			if l_idx >= 0:
				var lg = _skeleton.global_transform * _skeleton.get_bone_global_pose(l_idx)
				_predict_last_left_pos = lg.origin
				_predict_last_left_pos.y = global_position.y # ★ root Y
		
		# 初始化曲線為平坦
		_predict_left_curve = [ {"d": 0.0, "h": 0.0}, {"d": PREDICT_STEP_LENGTH, "h": 0.0}]
		_predict_right_curve = [ {"d": 0.0, "h": 0.0}, {"d": PREDICT_STEP_LENGTH, "h": 0.0}]
		_predict_left_tangent = 0.0
		_predict_right_tangent = 0.0
		_predict_bip_vel = 0.0
		
		# ★ C# Start(): LastBipHeight = Bip.position.y
		if _skeleton:
			var hips_idx = _skeleton.find_bone("Hips")
			if hips_idx >= 0:
				var hips_g = _skeleton.global_transform * _skeleton.get_bone_global_pose(hips_idx)
				_predict_last_bip_height = hips_g.origin.y
		
		# ★ Godot 特有：記錄 root Y 用於每幀補償
		_predict_prev_root_y = global_position.y
		
		# 做首次預測
		_predict_step_for_foot(false) # right
		_predict_step_for_foot(true) # left
		_predict_initialized = true
		if verbose_debug: print(">>> [PredictIK] ★ 啟用（進入樓梯）")
	
	# 離開樓梯或 root motion 啟動時：停用
	if not should_predict and _predict_ik_active:
		_predict_ik_active = false
		_predict_initialized = false
		# ★ 清除 pelvis 偏移，回到正常狀態
		if _visuals_node:
			_visuals_node.position.y = stair.step_up_visual_debt
		if verbose_debug: print(">>> [PredictIK] ★ 停用（%s）" % ("root motion 接管" if stair.root_motion_active else "離開樓梯"))
	
	if not _predict_ik_active:
		return
	
	# 右腳從鎖定→解鎖 = 右腳開始擺動 → 觸發右腳預測
	if _predict_prev_right_locked and not _right_foot_locked:
		_predict_step_for_foot(false)
		if verbose_debug: print(">>> [PredictIK] 右腳 swing → 觸發預測")
	
	# 左腳同理
	if _predict_prev_left_locked and not _left_foot_locked:
		_predict_step_for_foot(true)
		if verbose_debug: print(">>> [PredictIK] 左腳 swing → 觸發預測")
	
	_predict_prev_right_locked = _right_foot_locked
	_predict_prev_left_locked = _left_foot_locked

## ★ PredictIK LateUpdate — 精確移植自 PredictIK.cs LateUpdate (行 75-127)
## 核心：CoG 跟隨較低腳 → 骨盆下沉 → 擺動腳 IK 抬高 → 膝蓋可見
func _update_predict_ik(delta: float) -> void:
	if not _predict_initialized or not _skeleton:
		return
	if not right_leg_ik or not left_leg_ik:
		return
	if not right_foot_target or not left_foot_target:
		return
	
	var right_foot_idx = _skeleton.find_bone("RightFoot")
	var left_foot_idx = _skeleton.find_bone("LeftFoot")
	var hips_idx = _skeleton.find_bone("Hips")
	if right_foot_idx < 0 or left_foot_idx < 0 or hips_idx < 0:
		return
	
	# 讀取動畫骨骼位置
	var right_bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
	var left_bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)
	var hips_bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(hips_idx)
	
	# ★★★ 反饋迴路修復：骨骼位置包含上幀的 _visuals_node.position.y 偏移 ★★★
	# 必須扣除才能得到「純動畫」位置，否則偏移會自我疊加 → 抖動
	var prev_pelvis_adj: float = 0.0
	if _visuals_node:
		prev_pelvis_adj = _visuals_node.position.y - stair.step_up_visual_debt
	
	# 純動畫骨骼位置（不含我們的 pelvis 偏移）
	var right_foot_pos = right_bone_global.origin
	var left_foot_pos = left_bone_global.origin
	var pure_right_foot_y = right_foot_pos.y - prev_pelvis_adj
	var pure_left_foot_y = left_foot_pos.y - prev_pelvis_adj
	var pure_hips_y = hips_bone_global.origin.y - prev_pelvis_adj
	
	# ══════ Godot 特有：補償 CharacterBody3D 爬樓的 root Y 偏移 ══════
	var root_y_delta = global_position.y - _predict_prev_root_y
	_predict_last_left_pos.y += root_y_delta
	_predict_last_right_pos.y += root_y_delta
	_predict_last_bip_height += root_y_delta # ★ CoG 也要跟著補償
	_predict_prev_root_y = global_position.y
	
	# ★ 使用 transform.forward（角色朝向）
	var forward_dir = - global_transform.basis.z
	forward_dir.y = 0
	forward_dir = forward_dir.normalized()
	
	# ══════ C# line 82-94: 計算每隻腳沿曲線的前進距離與虛擬表面高度 ══════
	var left_dir = left_foot_pos - _predict_last_left_pos
	var left_dis = clampf(left_dir.dot(forward_dir), 0.0, PREDICT_STEP_LENGTH)
	var left_h = _evaluate_predict_curve(_predict_left_curve, left_dis)
	var left_base = _predict_left_curve[0]["h"] if not _predict_left_curve.is_empty() else 0.0
	var virtual_left_height = _predict_last_left_pos.y + (left_h - left_base)
	
	var right_dir = right_foot_pos - _predict_last_right_pos
	var right_dis = clampf(right_dir.dot(forward_dir), 0.0, PREDICT_STEP_LENGTH)
	var right_h = _evaluate_predict_curve(_predict_right_curve, right_dis)
	var right_base = _predict_right_curve[0]["h"] if not _predict_right_curve.is_empty() else 0.0
	var virtual_right_height = _predict_last_right_pos.y + (right_h - right_base)
	
	# ══════ C# line 97: 重心跟隨較低的腳 ══════
	var virtual_cog_height = minf(virtual_left_height, virtual_right_height)
	
	# ══════ C# line 99-103: 計算骨盆目標位置 ══════
	# ★ 使用純動畫 Hips Y（不含上幀偏移），避免反饋迴路
	var anim_bip_y = pure_hips_y - global_position.y
	# 目標骨盆世界 Y = 虛擬重心 + 動畫骨盆高度
	var target_bip_y = virtual_cog_height + anim_bip_y
	
	# ══════ C# line 119: 骨盆 SmoothDamp ══════
	var damp_result = _smooth_damp(
		_predict_last_bip_height, target_bip_y,
		_predict_bip_vel, PREDICT_DAMP_TIME, delta
	)
	var smoothed_bip_y: float = damp_result[0]
	_predict_bip_vel = damp_result[1]
	_predict_last_bip_height = smoothed_bip_y
	
	# ══════ 骨盆偏移 → 通過 _visuals_node.position.y 實現 ══════
	# ★ 偏移量 = 平滑後骨盆 Y - 純動畫骨盆 Y（不含上幀偏移）
	var pelvis_world_offset = smoothed_bip_y - pure_hips_y
	_pelvis_offset = pelvis_world_offset
	if _visuals_node:
		_visuals_node.position.y = stair.step_up_visual_debt + pelvis_world_offset
	
	# ══════ C# line 107-112: IK 目標 = 動畫腳高 + (虛擬腳高 - 虛擬重心) ══════
	# 支撐腳（低階）: VirtualFoot ≈ VirtualCoG → 偏移 ≈ 0 → 不動
	# 擺動腳（高階）: VirtualFoot > VirtualCoG → 偏移 = Δh → 抬高一階
	var ik_smooth = 1.0 - exp(-10.0 * delta)
	
	# ★ IK 目標用純動畫腳高 + CoG 差值 + 新的 pelvis 偏移
	var right_ik_offset_y = virtual_right_height - virtual_cog_height
	var r_target_pos = right_foot_pos # XZ 跟隨動畫
	r_target_pos.y = pure_right_foot_y + right_ik_offset_y + pelvis_world_offset
	right_foot_target.global_position = right_foot_target.global_position.lerp(r_target_pos, ik_smooth)
	right_leg_ik.set("influence", _right_ik_weight)
	
	var left_ik_offset_y = virtual_left_height - virtual_cog_height
	var l_target_pos = left_foot_pos # XZ 跟隨動畫
	l_target_pos.y = pure_left_foot_y + left_ik_offset_y + pelvis_world_offset
	left_foot_target.global_position = left_foot_target.global_position.lerp(l_target_pos, ik_smooth)
	left_leg_ik.set("influence", _left_ik_weight)
	
	# 確保 modifier 活躍
	if not right_leg_ik.active:
		right_leg_ik.active = true
		left_leg_ik.active = true
	
	# Debug
	if Engine.get_frames_drawn() % 30 == 0:
		if verbose_debug: print(">>> [PredictIK] Ldis=%.2f Rdis=%.2f VL=%.2f VR=%.2f CoG=%.2f pelvis=%.3f rOff=%.3f lOff=%.3f" % [
			left_dis, right_dis, virtual_left_height, virtual_right_height,
			virtual_cog_height, pelvis_world_offset, right_ik_offset_y, left_ik_offset_y
		])

## [REMOVED] _adjust_foot_rotation / _align_foot_to_normal
## 腳踝對齊已移除：set_bone_pose_rotation() 與 TwoBoneIK3D 衝突造成抖動
## 如需腳踝對齊，需實作自訂 SkeletonModifier3D 放在 TwoBoneIK3D 之後

## ★ Godot 版 SmoothDamp（等效 Unity Mathf.SmoothDamp）
func _smooth_damp(current: float, target: float, current_vel: float, smooth_time: float, dt: float) -> Array:
	var st = maxf(smooth_time, 0.0001)
	var omega = 2.0 / st
	var x = omega * dt
	var exp_factor = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change = current - target
	var temp = (current_vel + omega * change) * dt
	var new_vel = (current_vel - omega * temp) * exp_factor
	var new_val = target + (change + temp) * exp_factor
	# 防止超調
	if (target - current > 0.0) == (new_val > target):
		new_val = target
		new_vel = (new_val - target) / dt if dt > 0 else 0.0
	return [new_val, new_vel]

## 地面行走 IK 更新（每幀調用）
func _update_ground_locomotion_ik(delta: float) -> void:
	# ★ 調試開關：禁用內部代碼更新，將其交給 SimpleFootIK
	if disable_ik_code:
		return
		
	if not _ground_ik_enabled or not _skeleton or not right_leg_ik or not left_leg_ik:
		# Debug: 檢查哪個條件失敗
		if Engine.get_frames_drawn() % 120 == 0: # 每2秒輸出一次
			if verbose_debug: print(">>> Ground IK blocked: enabled=%s skeleton=%s rightIK=%s leftIK=%s" % [
				_ground_ik_enabled, _skeleton != null, right_leg_ik != null, left_leg_ik != null
			])
		return
	
	# 跳躍/落地/平台跳躍時使用原有 IK 邏輯
	if _ik_active:
		return
	
	# ★★★ 落地/跳躍期間完全跳過 IK 更新（避免平滑目標被動畫腳覆蓋）★★★
	if _is_landing or _is_jumping:
		return
	
	# 計算基於速度的 IK 權重
	var target_weight = _calculate_ground_ik_weight()
	
	# Debug: 每秒輸出一次權重
	if Engine.get_frames_drawn() % 60 == 0:
		if verbose_debug: print(">>> Ground IK: target_weight=%.2f, floor=%s, speed=%.1f" % [
			target_weight, is_on_floor(), Vector2(velocity.x, velocity.z).length()
		])
	
	# 平滑權重變化（調整速度平衡響應與平滑）
	_right_ik_weight = lerp(_right_ik_weight, target_weight, delta * 5.0)
	_left_ik_weight = lerp(_left_ik_weight, target_weight, delta * 5.0)
	
	# ★ Phase 2：腳骨相位權重更新 + Foot Lock 解除（不在樓梯上時）
	_update_foot_phase_weights(delta)
	
	# ★★★ 樓梯狀態（Mode B 已移除），完全跳過 reactive IK ★★★
	# 樓梯動畫（不論是否純 Root Motion）都有自己的腳步姿勢
	# 只要在樓梯上，就淡出 IK 讓動畫完全接管
	if stair.on_stairs:
		# 進入樓梯 → 解除所有 foot lock，讓動畫掌控腳部位置
		_right_foot_locked = false
		_left_foot_locked = false
		_foot_lock_timer = 0.0
		
		# 快速淡出 IK influence → 0
		_right_ik_weight = lerpf(_right_ik_weight, 0.0, delta * 10.0)
		_left_ik_weight = lerpf(_left_ik_weight, 0.0, delta * 10.0)
		right_leg_ik.set("influence", _right_ik_weight)
		left_leg_ik.set("influence", _left_ik_weight)
		if _right_ik_weight < 0.01:
			right_leg_ik.active = false
			left_leg_ik.active = false
		# 清除殘留 pelvis offset
		_pelvis_offset = lerpf(_pelvis_offset, 0.0, delta * 10.0)
		return
	
	# 權重太低時跳過
	if target_weight < 0.01:
		right_leg_ik.set("influence", 0.0)
		left_leg_ik.set("influence", 0.0)
		# ★ 完全停用 modifier（避免 active=true 干擾 AnimationPlayer）
		if right_leg_ik.active:
			right_leg_ik.active = false
			left_leg_ik.active = false
		_target_pelvis_offset = 0.0
		_pelvis_offset = lerp(_pelvis_offset, 0.0, delta * PELVIS_SMOOTH_SPEED)
		# ★ 確保 visuals 高度歸零（保留 step-up 視覺補償）
		if _visuals_node and abs(_pelvis_offset) < IK_DEADZONE:
			_visuals_node.position.y = stair.step_up_visual_debt
		return
	
	# disable_ik_code check moved to top
	
	# ★ 權重 > 0：確保 modifier 已啟用
	if not right_leg_ik.active:
		right_leg_ik.active = true
		left_leg_ik.active = true
	
	# 獲取腳骨索引
	var right_foot_idx = _skeleton.find_bone("RightFoot")
	var left_foot_idx = _skeleton.find_bone("LeftFoot")
	
	if right_foot_idx < 0 or left_foot_idx < 0:
		return
	
	# 獲取腳骨世界位置
	var right_bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
	var left_bone_global = _skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)
	
	var right_offset: float = 0.0
	var left_offset: float = 0.0
	
	# ★ 使用 RayCast3D 模式（有 exclude_parent，不會碰撞到 Player 自己）
	if _right_foot_ray and _left_foot_ray:
	# ★ 目標 XZ 位置（跟隨腳骨）
		var right_target_xz = Vector2(right_bone_global.origin.x, right_bone_global.origin.z)
		var left_target_xz = Vector2(left_bone_global.origin.x, left_bone_global.origin.z)
		
		# ★★★ 基於速度的動態平滑速度 ★★★
		# 移動速度越快，平滑速度越快，避免腳被「拖」在後面
		var h_speed = Vector2(velocity.x, velocity.z).length()
		var speed_factor = clamp(h_speed / 5.0, 0.0, 1.0) # 5 m/s 時達到 100%
		var dynamic_xz_smooth = lerp(RAYCAST_XZ_SMOOTH_SPEED, 50.0, speed_factor) # 8 → 50
		var dynamic_ik_smooth = lerp(IK_SMOOTH_SPEED, 30.0, speed_factor) # 6 → 30
		
		# ★★★ 落地後快速淡入期：使用較高平滑速度（但不是瞬間）★★★
		if air.post_landing_blend_timer > 0:
			air.post_landing_blend_timer -= delta
			dynamic_xz_smooth = 50.0 # 較快平滑（但仍有過渡）
			dynamic_ik_smooth = 50.0 # 較快平滑（但仍有過渡）
			# Debug: 註解下面這行可關閉大量輸出
			# print(">>> 落地快速淡入: timer=%.3f" % air.post_landing_blend_timer)
		
		# ★ 平滑 XZ 位置（防止停止動畫時跳動）
		if _smoothed_right_ray_xz == Vector2.ZERO:
			_smoothed_right_ray_xz = right_target_xz # 初始化
		if _smoothed_left_ray_xz == Vector2.ZERO:
			_smoothed_left_ray_xz = left_target_xz # 初始化
		
		_smoothed_right_ray_xz = _smoothed_right_ray_xz.lerp(right_target_xz, delta * dynamic_xz_smooth)
		_smoothed_left_ray_xz = _smoothed_left_ray_xz.lerp(left_target_xz, delta * dynamic_xz_smooth)
		
		# 更新 RayCast3D 位置：使用平滑的 XZ，從膝蓋高度向下
		var ray_base_y = global_position.y
		if stair.on_stairs and stair.ascending and _visuals_node:
			ray_base_y = global_position.y + _visuals_node.position.y - _pelvis_offset
		
		# ★ 統一模式：永遠使用 RayCast（樓梯 + 平地皆用），foot lock 只用來微調 Y
		_right_foot_ray.global_position = Vector3(
			_smoothed_right_ray_xz.x,
			ray_base_y + 0.5,
			_smoothed_right_ray_xz.y
		)
		_left_foot_ray.global_position = Vector3(
			_smoothed_left_ray_xz.x,
			ray_base_y + 0.5,
			_smoothed_left_ray_xz.y
		)
		
		# 強制更新射線（確保即時檢測）
		_right_foot_ray.force_shapecast_update()
		_left_foot_ray.force_shapecast_update()
		
		# ★★★ PredictIK 分支已在 line 3190 提前 return，不會到這裡 ★★★
		# （移除重複呼叫，避免雙重 IK 更新）
		if false: # _predict_ik_active — 已由上方統一處理
			pass
		# 右腳 IK（非 PredictIK 模式）
		# ★ 鎖定模式：直接使用儲存的世界座標，跳過 raycast 和 lerp
		elif stair.on_stairs and _right_foot_locked and right_foot_target:
			right_foot_target.global_position = _locked_right_world_pos
			_smoothed_right_target = _locked_right_world_pos # 同步平滑目標
			# ★ 鎖定腳必須 influence=1.0（完全釘在世界座標）— 否則動畫洩漏會讓腳被膠囊體帶動
			right_leg_ik.set("influence", 1.0)
			right_offset = _locked_right_world_pos.y - FOOT_HEIGHT_OFFSET - right_bone_global.origin.y
		elif _right_foot_ray.is_colliding() and right_foot_target:
			var right_hit = _right_foot_ray.get_collision_point(0)
			var right_normal = _right_foot_ray.get_collision_normal(0)
			
			# ★ 邊緣抗抖動：如果碰撞法線太傾斜（撞到階梯側面），跳過此幀
			var right_normal_angle = right_normal.angle_to(Vector3.UP)
			if right_normal_angle > deg_to_rad(60.0):
				# 側面碰撞 → 保持上一幀平滑目標，降低影響力
				right_leg_ik.set("influence", _right_ik_weight * 0.3)
				# 法線回歸 UP（不使用側面法線旋轉腳踝）
				_right_ground_normal = _right_ground_normal.lerp(Vector3.UP, delta * 5.0)
			else:
				# ★ 儲存有效地面法線供腳踝旋轉使用
				_right_ground_normal = _right_ground_normal.lerp(right_normal, delta * 8.0)
				right_offset = right_hit.y - right_bone_global.origin.y
				
				if Engine.get_frames_drawn() % 60 == 0:
					if verbose_debug: print(">>> RIGHT: offset=%.3f, limit=[%.2f, %.2f], weight=%.2f, hit.y=%.2f, bone.y=%.2f" % [
						right_offset, -MAX_FOOT_DROP, MAX_FOOT_RAISE, _right_ik_weight,
						right_hit.y, right_bone_global.origin.y
					])
				
				if right_offset < -MAX_FOOT_DROP or right_offset > MAX_FOOT_RAISE:
					# ★ 樓梯上保留最低 IK 防穿透，平地才完全關閉
					right_leg_ik.set("influence", STAIR_MIN_IK_PHASE * _right_ik_weight if stair.on_stairs else 0.0)
				else:
					var target_pos = right_hit + Vector3(0, FOOT_HEIGHT_OFFSET, 0)
					_smoothed_right_target = _smoothed_right_target.lerp(target_pos, delta * dynamic_ik_smooth)
					right_foot_target.global_position = _smoothed_right_target
					# ★ 樓梯上套用相位權重（非鎖定腳），保留最低 IK 防穿透
					var r_phase = _right_foot_phase_weight if stair.on_stairs else 1.0
					if stair.on_stairs:
						r_phase = maxf(r_phase, STAIR_MIN_IK_PHASE)
					right_leg_ik.set("influence", _right_ik_weight * r_phase)
		else:
			right_leg_ik.set("influence", 0.0)
		
		# 左腳 IK（非 PredictIK 模式）
		# ★ 鎖定模式：直接使用儲存的世界座標，跳過 raycast 和 lerp
		if _predict_ik_active:
			pass # PredictIK 已在上面處理
		elif stair.on_stairs and _left_foot_locked and left_foot_target:
			left_foot_target.global_position = _locked_left_world_pos
			_smoothed_left_target = _locked_left_world_pos # 同步平滑目標
			# ★ 鎖定腳必須 influence=1.0（完全釘在世界座標）— 否則動畫洩漏會讓腳被膠囊體帶動
			left_leg_ik.set("influence", 1.0)
			left_offset = _locked_left_world_pos.y - FOOT_HEIGHT_OFFSET - left_bone_global.origin.y
		elif _left_foot_ray.is_colliding() and left_foot_target:
			var left_hit = _left_foot_ray.get_collision_point(0)
			var left_normal = _left_foot_ray.get_collision_normal(0)
			
			# ★ 邊緣抗抖動：如果碰撞法線太傾斜（撞到階梯側面），跳過此幀
			var left_normal_angle = left_normal.angle_to(Vector3.UP)
			if left_normal_angle > deg_to_rad(60.0):
				# 側面碰撞 → 保持上一幀平滑目標，降低影響力
				left_leg_ik.set("influence", _left_ik_weight * 0.3)
				# 法線回歸 UP（不使用側面法線旋轉腳踝）
				_left_ground_normal = _left_ground_normal.lerp(Vector3.UP, delta * 5.0)
			else:
				# ★ 儲存有效地面法線供腳踝旋轉使用
				_left_ground_normal = _left_ground_normal.lerp(left_normal, delta * 8.0)
				left_offset = left_hit.y - left_bone_global.origin.y
				
				if Engine.get_frames_drawn() % 60 == 0:
					if verbose_debug: print(">>> LEFT: offset=%.3f, limit=[%.2f, %.2f], weight=%.2f, hit.y=%.2f, bone.y=%.2f" % [
						left_offset, -MAX_FOOT_DROP, MAX_FOOT_RAISE, _left_ik_weight,
						left_hit.y, left_bone_global.origin.y
					])
				
				if left_offset < -MAX_FOOT_DROP or left_offset > MAX_FOOT_RAISE:
					# ★ 樓梯上保留最低 IK 防穿透，平地才完全關閉
					left_leg_ik.set("influence", STAIR_MIN_IK_PHASE * _left_ik_weight if stair.on_stairs else 0.0)
				else:
					var target_pos = left_hit + Vector3(0, FOOT_HEIGHT_OFFSET, 0)
					_smoothed_left_target = _smoothed_left_target.lerp(target_pos, delta * dynamic_ik_smooth)
					left_foot_target.global_position = _smoothed_left_target
					# ★ 樓梯上套用相位權重（非鎖定腳），保留最低 IK 防穿透
					var l_phase = _left_foot_phase_weight if stair.on_stairs else 1.0
					if stair.on_stairs:
						l_phase = maxf(l_phase, STAIR_MIN_IK_PHASE)
					left_leg_ik.set("influence", _left_ik_weight * l_phase)
		else:
			left_leg_ik.set("influence", 0.0)
	else:
		# 備用：傳統射線檢測模式（無 RayCast3D 節點時）
		var right_ray = _raycast_ground_full(right_bone_global.origin)
		var left_ray = _raycast_ground_full(left_bone_global.origin)
		
		var right_hit = right_ray.get("position", Vector3.ZERO)
		var left_hit = left_ray.get("position", Vector3.ZERO)
		
		# 右腳 IK
		if right_hit != Vector3.ZERO and right_foot_target:
			right_offset = right_hit.y - right_bone_global.origin.y
			if right_offset < -MAX_FOOT_DROP or right_offset > MAX_FOOT_RAISE:
				right_leg_ik.set("influence", 0.0)
			else:
				var target_pos = right_hit + Vector3(0, FOOT_HEIGHT_OFFSET, 0)
				_smoothed_right_target = _smoothed_right_target.lerp(target_pos, delta * IK_SMOOTH_SPEED)
				right_foot_target.global_position = _smoothed_right_target
				right_leg_ik.set("influence", _right_ik_weight)
		else:
			right_leg_ik.set("influence", 0.0)
		
		# 左腳 IK
		if left_hit != Vector3.ZERO and left_foot_target:
			left_offset = left_hit.y - left_bone_global.origin.y
			if left_offset < -MAX_FOOT_DROP or left_offset > MAX_FOOT_RAISE:
				left_leg_ik.set("influence", 0.0)
			else:
				var target_pos = left_hit + Vector3(0, FOOT_HEIGHT_OFFSET, 0)
				_smoothed_left_target = _smoothed_left_target.lerp(target_pos, delta * IK_SMOOTH_SPEED)
				left_foot_target.global_position = _smoothed_left_target
				left_leg_ik.set("influence", _left_ik_weight)
		else:
			left_leg_ik.set("influence", 0.0)
	
	# Debug: 每秒輸出實際 IK influence 和目標位置
	if Engine.get_frames_drawn() % 60 == 0:
		var actual_r = right_leg_ik.get("influence") if right_leg_ik else 0.0
		var ik_active = right_leg_ik.get("active") if right_leg_ik else false
		var target_path = right_leg_ik.get("settings/0/target_node") if right_leg_ik else "null"
		var using_raycast = _right_foot_ray != null and _left_foot_ray != null
		if verbose_debug: print(">>> IK: inf=%.2f | active=%s | RayCast=%s | RTarget=%.2f RBone=%.2f" % [
			actual_r,
			ik_active,
			using_raycast,
			right_foot_target.global_position.y if right_foot_target else -999.0,
			right_bone_global.origin.y
		])
		if verbose_debug: print(">>> IK target_node: %s" % target_path)
	
	# 骨盆調整（讓腳能到達更低的地面）
	# ★ PredictIK 已在 _update_predict_ik() 中處理骨盆，跳過舊邏輯
	if _predict_ik_active:
		return
	
	# ★ 使用較低腳的偏移（更負的值 = 需要更多下降）
	var lower_offset = min(right_offset, left_offset)
	
	# ★ 判斷是否站在不平地面（兩腳高度差超過閾值）
	var height_diff = abs(right_offset - left_offset)
	var is_uneven_ground = height_diff > 0.05 # 5cm 高度差
	
	# ★ 樓梯 foot lock 模式：更積極的骨盆下降
	var pelvis_multiplier = 1.0
	var pelvis_speed = PELVIS_SMOOTH_SPEED # 預設 3.0
	if stair.on_stairs and (_right_foot_locked or _left_foot_locked):
		# 鎖定腳在較低台階 → 骨盆需要大幅下降
		pelvis_multiplier = 2.0 # 更強的下降倍率
		pelvis_speed = 8.0 # 更快的響應速度
	elif is_uneven_ground:
		pelvis_multiplier = 1.5
	
	# 計算新的目標骨盆偏移
	var new_target: float = 0.0
	# ★ 只要有腳需要向下伸展，就啟用骨盆下降
	if target_weight >= IK_MAX_WEIGHT_STAND * 0.5 and lower_offset < -0.03:
		new_target = clamp(lower_offset * pelvis_multiplier, -MAX_PELVIS_DROP, 0.0)
	
	# ★ 死區過濾：只有變化超過死區才更新目標
	if abs(new_target - _target_pelvis_offset) > IK_DEADZONE:
		_target_pelvis_offset = new_target
	
	# ★ 樓梯上使用更快的平滑速度
	_pelvis_offset = lerp(_pelvis_offset, _target_pelvis_offset, delta * pelvis_speed)
	
	# ★ 應用到 Visuals 節點（而非 Hips 骨頭）- 這樣不會被 AnimationTree 覆蓋
	if _visuals_node:
		# ★ 也對最終值應用死區
		if abs(_pelvis_offset) > IK_DEADZONE:
			_visuals_node.position.y = _pelvis_offset + stair.step_up_visual_debt
		else:
			_visuals_node.position.y = stair.step_up_visual_debt
	
	# ★★★ 自適應支撐腳彎曲（Adaptive Support Leg Bend）★★★
	# 當骨盆已達極限但腳仍到不了時，讓支撐腳（較高的腳）的 IK 目標下移
	# 這會讓膝蓋自然彎曲，讓身體能更低
	var pelvis_at_limit = abs(_pelvis_offset - (-MAX_PELVIS_DROP)) < 0.02
	var remaining_gap = abs(lower_offset) - MAX_PELVIS_DROP
	
	# 判斷哪隻腳是支撐腳（較高的那隻）
	var right_is_support = right_offset > left_offset
	
	# 只在站立且骨盆達極限時啟用
	if pelvis_at_limit and remaining_gap > 0.02 and target_weight >= IK_MAX_WEIGHT_STAND * 0.9:
		_target_support_leg_drop = clamp(remaining_gap * 0.8, 0.0, MAX_SUPPORT_LEG_DROP)
	else:
		_target_support_leg_drop = 0.0
	
	# 平滑過渡
	_support_leg_drop = lerp(_support_leg_drop, _target_support_leg_drop, delta * PELVIS_SMOOTH_SPEED)
	
	# 應用到支撐腳的 IK 目標
	if _support_leg_drop > 0.01:
		if right_is_support and right_foot_target:
			# 右腳是支撐腳，讓它的目標往下移
			right_foot_target.global_position.y -= _support_leg_drop
		elif not right_is_support and left_foot_target:
			# 左腳是支撐腳
			left_foot_target.global_position.y -= _support_leg_drop

## ★ 延遲 debug + 腳踝對齊修正器更新
func _debug_bone_after_ik() -> void:
	if not _skeleton:
		return
	
	# ★ 每幀同步地面法線和 IK 權重到 AnkleAlignModifier3D
	if _ankle_modifier:
		_ankle_modifier.left_ground_normal = _left_ground_normal
		_ankle_modifier.right_ground_normal = _right_ground_normal
		_ankle_modifier.left_ik_weight = _left_ik_weight
		_ankle_modifier.right_ik_weight = _right_ik_weight
	
	# ★ 樓梯上持續禁用腳部 IK（ShapeCast 在階梯邊緣不穩定）
	if _foot_ik_system:
		# 任何樓梯相關狀態都關 IK：on_stairs / 寬限期 / 樓梯動畫中
		var on_stairs_any = stair.on_stairs or stair.grace_timer > 0 or (anim_tree and not anim_tree.active)
		var should_ik = not on_stairs_any
		if _foot_ik_system.ik_enabled != should_ik:
			_foot_ik_system.ik_enabled = should_ik
			if verbose_debug:
				print(">>> [FootIK] %s (stairs=%s grace=%.2f animTree=%s)" % [
					"ON" if should_ik else "OFF",
					stair.on_stairs, stair.grace_timer,
					str(anim_tree.active) if anim_tree else "null"
				])
	
	var right_foot_idx = _skeleton.find_bone("RightFoot")
	if right_foot_idx >= 0:
		var bone_pose = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
		if verbose_debug: print(">>> [AFTER IK] RBone=%.2f | Target=%.2f | active=%s" % [
			bone_pose.origin.y,
			right_foot_target.global_position.y if right_foot_target else -999.0,
			right_leg_ik.get("active") if right_leg_ik else false
		])

#region ==================== Foot Locking 過渡穩定系統 ====================

## 啟用 Foot Locking（動畫過渡期間穩定腳部）
func _activate_foot_lock() -> void:
	# 如果已經有 Tween 運行，先取消它
	if _foot_lock_tween and _foot_lock_tween.is_valid():
		_foot_lock_tween.kill()
	
	if verbose_debug: print(">>> [Foot Lock] 啟用！開始過渡")
	
	_foot_lock_active = true
	_foot_lock_blend = 1.0
	
	# 使用 Tween 延遲重置 IK 狀態（0.5秒後）
	_foot_lock_tween = create_tween()
	_foot_lock_tween.tween_property(self , "_foot_lock_blend", 0.0, _foot_lock_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_foot_lock_tween.tween_callback(_deactivate_foot_lock)

## 停用 Foot Locking
func _deactivate_foot_lock() -> void:
	if verbose_debug: print(">>> [Foot Lock] 停用，切換到地面 IK")
	_foot_lock_active = false
	_foot_lock_blend = 0.0
	_foot_lock_tween = null
	
	# ★ 切換 IK 模式
	_ik_active = false
	
	# ★★★ 從當前腳骨位置初始化平滑目標（避免從舊位置 lerp 過來）★★★
	if _skeleton:
		var right_foot_idx = _skeleton.find_bone("RightFoot")
		var left_foot_idx = _skeleton.find_bone("LeftFoot")
		
		if right_foot_idx >= 0 and left_foot_idx >= 0:
			var right_bone = _skeleton.global_transform * _skeleton.get_bone_global_pose(right_foot_idx)
			var left_bone = _skeleton.global_transform * _skeleton.get_bone_global_pose(left_foot_idx)
			
			# 將平滑目標瞬間 snap 到當前腳骨位置
			_smoothed_right_ray_xz = Vector2(right_bone.origin.x, right_bone.origin.z)
			_smoothed_left_ray_xz = Vector2(left_bone.origin.x, left_bone.origin.z)
			_smoothed_right_target = right_bone.origin
			_smoothed_left_target = left_bone.origin
			
			if verbose_debug: print(">>> [Foot Lock] IK 目標已 snap 到當前腳骨位置")

#endregion

#region ==================== 攀爬系統 ====================

## 偵測可抓取的邊緣
## 返回 Dictionary: {found: bool, grab_point: Vector3, wall_point: Vector3, surface_normal: Vector3, ledge_height: float}
func _detect_grabbable_ledge() -> Dictionary:
	var result = {"found": false, "grab_point": Vector3.ZERO, "wall_point": Vector3.ZERO, "surface_normal": Vector3.FORWARD, "ledge_height": 0.0}
	
	var space_state = get_world_3d().direct_space_state
	var forward_dir = - global_transform.basis.z.normalized()
	
	# 1. 胸部高度向前偵測牆面
	var chest_height = global_position + Vector3.UP * 1.2
	var wall_query = PhysicsRayQueryParameters3D.create(
		chest_height,
		chest_height + forward_dir * CLIMB_WALL_DETECT_DIST
	)
	wall_query.exclude = [get_rid()]
	
	var wall_hit = space_state.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return result
	
	# 2. 頭頂高度向前偵測（確認有邊緣空間）
	for height_offset in [CLIMB_GRAB_HEIGHT_MIN, (CLIMB_GRAB_HEIGHT_MIN + CLIMB_GRAB_HEIGHT_MAX) / 2, CLIMB_GRAB_HEIGHT_MAX]:
		var head_pos = global_position + Vector3.UP * height_offset
		var head_query = PhysicsRayQueryParameters3D.create(
			head_pos,
			head_pos + forward_dir * (CLIMB_WALL_DETECT_DIST + 0.3)
		)
		head_query.exclude = [get_rid()]
		
		var head_hit = space_state.intersect_ray(head_query)
		if head_hit.is_empty():
			# 有空隙！向下偵測找邊緣
			var down_start = head_pos + forward_dir * CLIMB_WALL_DETECT_DIST
			var down_query = PhysicsRayQueryParameters3D.create(
				down_start,
				down_start - Vector3.UP * 1.0
			)
			down_query.exclude = [get_rid()]
			
			var down_hit = space_state.intersect_ray(down_query)
			if not down_hit.is_empty():
				# 確認是水平表面（邊緣）
				var surface_normal = down_hit.normal
				if surface_normal.dot(Vector3.UP) > 0.7:
					result.found = true
					result.grab_point = down_hit.position
					result.wall_point = wall_hit.position # ★ 牆面碰撞點
					result.surface_normal = wall_hit.normal
					result.ledge_height = down_hit.position.y - global_position.y
					if verbose_debug: print(">>> 偵測到邊緣! 高度: %.2f, 牆面: %s" % [result.ledge_height, result.wall_point])
					return result
	
	return result

## 進入懸掛狀態
func _enter_hanging_state(grab_data: Dictionary) -> void:
	if climb.state != ClimbState.NONE:
		return
	
	if verbose_debug: print(">>> 進入懸掛狀態!")
	climb.state = ClimbState.GRABBING
	climb.grab_point = grab_data.grab_point
	climb.surface_normal = grab_data.surface_normal
	climb.ledge_height = grab_data.ledge_height
	
	# 停止所有移動
	velocity = Vector3.ZERO
	
	# 禁用 AnimationTree，直接播放
	if anim_tree:
		anim_tree.active = false
	
	# 設置循環
	var anim = anim_player.get_animation("movement/" + HANG_IDLE_ANIM)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	
	# 播放懸掛動畫
	anim_player.speed_scale = 1.0
	anim_player.play("movement/" + HANG_IDLE_ANIM)
	
	# ★ 使用牆面碰撞點計算懸掛位置（角色在牆外）
	var wall_point = grab_data.get("wall_point", climb.grab_point)
	var wall_offset = 0.5 # ★ 減少：讓角色更靠近牆面
	
	# ★ 確保法線指向「遠離牆面」的方向（從牆面向外）
	# wall_hit.normal 應該指向角色（即法線方向 = 角色方向）
	var offset_dir = climb.surface_normal.normalized()
	
	var target_pos = Vector3(
		wall_point.x + offset_dir.x * wall_offset,
		climb.grab_point.y - 1.95, # ★ 調高角色位置，讓手臂有彎曲空間（原 2.18 太低導致手臂伸直）
		wall_point.z + offset_dir.z * wall_offset
	)
	
	if verbose_debug: print(">>> [HANG DEBUG] wall_point=%s, normal=%s, offset_dir=%s" % [wall_point, climb.surface_normal, offset_dir])
	if verbose_debug: print(">>> [HANG DEBUG] grab_point=%s, target_pos=%s, current_pos=%s" % [climb.grab_point, target_pos, global_position])
	
	# 平滑移動到懸掛位置
	var tween = create_tween()
	tween.tween_property(self , "global_position", target_pos, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		climb.state = ClimbState.HANGING
		_setup_hand_ik_for_hang() # ★ 設置手部 IK
	)
	
	# 面向牆壁（surface_normal 指向角色，所以用負值面向牆壁方向）
	# 注意：wall_hit.normal 指向「遠離牆壁」= 指向角色
	# 所以 look_dir 應該是負的法線（朝向牆壁）
	var look_dir = climb.surface_normal # 不加負號，因為我們要角色面向法線指向的方向
	look_dir.y = 0
	if look_dir.length() > 0.1:
		var target_rotation = atan2(look_dir.x, look_dir.z)
		# ★ 使用最短路徑旋轉（避免 360° 旋轉）
		var current_rotation = rotation.y
		var rot_tween = create_tween()
		rot_tween.tween_method(
			func(t: float): rotation.y = lerp_angle(current_rotation, target_rotation, t),
			0.0, 1.0, 0.15
		)

## 退出懸掛狀態
func _exit_hanging_state(drop: bool = true) -> void:
	if verbose_debug: print(">>> 退出懸掛狀態 (drop=%s)" % drop)
	
	if drop:
		climb.state = ClimbState.DROPPING
		# 播放放手動畫
		anim_player.play("movement/" + HANG_DROP_ANIM)
		
		# 等動畫開始後恢復物理
		await get_tree().create_timer(0.1).timeout
		velocity.y = -2.0 # 輕微向下速度
	
	climb.state = ClimbState.NONE
	_set_motion_state(MovementEnums.MotionState.FALLING)
	
	# ★ 禁用手部 IK
	_disable_hand_ik()
	
	# 重新啟用 AnimationTree
	if anim_tree:
		anim_tree.active = true

## 觸發從懸掛攀上（Root Motion 驅動）
func _trigger_mantle_from_hang() -> void:
	if climb.state != ClimbState.HANGING:
		return
	
	if verbose_debug: print(">>> 觸發攀上 (Root Motion Mantle)!")
	climb.state = ClimbState.CLIMBING_UP
	
	# ★ 立即禁用手部 IK（讓攀上動畫完全由動畫驅動）
	_disable_hand_ik()
	
	# ★ 記錄 Root Motion 狀態
	climb.mantle_start_pos = global_position
	climb.mantle_target_y = climb.grab_point.y + 0.1 # 邊緣上方 10cm
	climb.mantle_wall_point = climb.grab_point # 用於距離約束
	climb.mantle_elapsed = 0.0
	
	# ★ 計算高度補償
	var actual_climb_height = climb.mantle_target_y - global_position.y
	climb.mantle_height_compensation = actual_climb_height - MANTLE_ANIM_CLIMB_HEIGHT
	if verbose_debug: print(">>> [Root Motion] 實際攀爬高度=%.2f, 動畫高度=%.2f, 補償=%.2f" % [
		actual_climb_height, MANTLE_ANIM_CLIMB_HEIGHT, climb.mantle_height_compensation
	])
	
	# ★ 啟用 Root Motion 軌道
	anim_player.root_motion_track = NodePath("Visuals/Human/GeneralSkeleton:Hips")
	
	# ★ 播放攀上動畫（優先用原始 FBX 版本，包含 Hips 位移）
	anim_player.speed_scale = 1.2
	if climb.mantle_rm_loaded:
		anim_player.play(MANTLE_RM_ANIM_LIB + "/" + MANTLE_RM_ANIM_NAME)
		if verbose_debug: print(">>> [Root Motion] 使用原始 FBX 動畫 (包含 Hips 位移)")
	else:
		anim_player.play("movement/" + HANG_TO_CROUCH_ANIM)
		if verbose_debug: print(">>> [Root Motion] ❗ 回退到無 Root Motion 的 Library 動畫")
	
	# 取得實際播放動畫的時長
	var anim_path = MANTLE_RM_ANIM_LIB + "/" + MANTLE_RM_ANIM_NAME if climb.mantle_rm_loaded else "movement/" + HANG_TO_CROUCH_ANIM
	var anim = anim_player.get_animation(anim_path)
	climb.mantle_duration = (anim.length if anim else 1.5) / 1.2
	climb.mantle_root_motion_active = true
	
	# 連接動畫結束信號
	if not anim_player.animation_finished.is_connected(_on_mantle_finished):
		anim_player.animation_finished.connect(_on_mantle_finished)
	
	if verbose_debug: print(">>> [Root Motion] 開始! 時長=%.2fs" % climb.mantle_duration)

## ★ 每幀處理 Root Motion Mantle
func _process_root_motion_mantle(delta: float) -> void:
	if not climb.mantle_root_motion_active:
		return
	
	climb.mantle_elapsed += delta
	
	# ★ 提取 Root Motion 位移（由 AnimationPlayer 從 Hips 骨骼軌道提取）
	var root_motion = anim_player.get_root_motion_position()
	
	# 將骨骼局部空間的位移轉換為世界空間
	# root_motion 是相對於角色的局部座標
	var world_motion = global_transform.basis * root_motion
	
	# ★ 加上高度補償（分散在整個動畫時長內）
	if climb.mantle_duration > 0:
		world_motion.y += (climb.mantle_height_compensation / climb.mantle_duration) * delta
	
	# 應用位移
	global_position += world_motion
	
	# ★ 牆面距離約束（防止穿牆）
	var to_wall = global_position - climb.mantle_wall_point
	var dist_along_normal = to_wall.dot(climb.surface_normal)
	if dist_along_normal < MANTLE_MIN_WALL_DIST:
		# 角色太靠近或穿進牆了，推回來
		global_position += climb.surface_normal * (MANTLE_MIN_WALL_DIST - dist_along_normal)
	
	# Debug
	if Engine.get_physics_frames() % 10 == 0:
		if verbose_debug: print(">>> [Root Motion] pos=%s, motion=%s, elapsed=%.2f/%.2f" % [
			global_position, root_motion, climb.mantle_elapsed, climb.mantle_duration
		])

## ★ Mantle 動畫結束回調
func _on_mantle_finished(anim_name: StringName) -> void:
	if "Hang_To_Crouch" not in str(anim_name):
		return
	
	if verbose_debug: print(">>> [Root Motion] Mantle 完成! 最終位置=%s" % global_position)
	_finish_mantle()

## ★ 完成 Mantle 清理
func _finish_mantle() -> void:
	# 關閉 Root Motion
	climb.mantle_root_motion_active = false
	anim_player.root_motion_track = NodePath("")
	anim_player.speed_scale = 1.0
	
	# 斷開信號
	if anim_player.animation_finished.is_connected(_on_mantle_finished):
		anim_player.animation_finished.disconnect(_on_mantle_finished)
	
	# 恢復正常狀態
	climb.state = ClimbState.NONE
	_set_gait(MovementEnums.Gait.CROUCH) # 攀上後蹲著
	if anim_tree:
		anim_tree.active = true

## 處理懸掛狀態輸入
func _process_hanging_input(delta: float) -> void:
	if climb.state != ClimbState.HANGING:
		return
	
	# 如果正在 shimmy，不接受新輸入
	if climb.is_shimmying:
		return
	
	# W 鍵或跳躍 = 攀上
	if Input.is_key_pressed(KEY_W) or Input.is_action_just_pressed("ui_accept"):
		_trigger_mantle_from_hang()
		return
	
	# S 鍵 = 放手
	if Input.is_key_pressed(KEY_S):
		_exit_hanging_state(true)
		return
	
	# A/D 鍵 = 左右移動 (Shimmy)
	if Input.is_key_pressed(KEY_A):
		_start_shimmy(-1) # 左
	elif Input.is_key_pressed(KEY_D):
		_start_shimmy(1) # 右

## 開始 Shimmy 移動
func _start_shimmy(direction: int) -> void:
	if climb.state != ClimbState.HANGING or climb.is_shimmying:
		return
	
	# 計算移動方向：使用角色的 "右" 方向（角色面向牆面，所以 X 軸是左右）
	# direction: -1 = 往角色左邊（A鍵），1 = 往角色右邊（D鍵）
	var char_right = global_transform.basis.x.normalized()
	var move_dir = char_right * direction
	
	# 檢測側向是否有邊緣可以移動
	var check_result = _check_shimmy_ledge(move_dir)
	if not check_result.found:
		if verbose_debug: print(">>> Shimmy 方向無邊緣可抓！")
		return
	
	climb.is_shimmying = true
	climb.shimmy_direction = direction
	climb.shimmy_target_pos = check_result.position
	
	# 播放對應動畫
	var anim_name = SHIMMY_LEFT_ANIM if direction < 0 else SHIMMY_RIGHT_ANIM
	if verbose_debug: print(">>> Shimmy 方向: %s, 動畫: %s" % [direction, anim_name])
	anim_player.play("movement/" + anim_name)
	
	# 計算動畫長度
	var anim = anim_player.get_animation("movement/" + anim_name)
	var anim_length = anim.length if anim else 0.5
	
	# Tween 移動到新位置
	var tween = create_tween()
	tween.tween_property(self , "global_position", climb.shimmy_target_pos, anim_length * 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# 更新抓握點
	tween.tween_callback(func():
		climb.grab_point = check_result.grab_point
		climb.is_shimmying = false
		_update_hand_ik_for_shimmy() # ★ 更新手部 IK 位置
		# 回到懸掛待機
		anim_player.play("movement/" + HANG_IDLE_ANIM)
	)
	
	if verbose_debug: print(">>> Shimmy %s: target=%s" % ["左" if direction < 0 else "右", climb.shimmy_target_pos])

## 檢測 Shimmy 方向是否有可抓握的邊緣
func _check_shimmy_ledge(move_dir: Vector3) -> Dictionary:
	var result = {"found": false, "position": Vector3.ZERO, "grab_point": Vector3.ZERO}
	
	var space_state = get_world_3d().direct_space_state
	var check_distance = SHIMMY_LEDGE_CHECK_DIST
	
	# 從當前抓握點往側邊方向檢測
	var side_pos = climb.grab_point + move_dir * check_distance
	
	# 1. 向下射線找邊緣
	var down_query = PhysicsRayQueryParameters3D.create(
		side_pos + Vector3.UP * 0.3,
		side_pos - Vector3.UP * 0.5
	)
	down_query.exclude = [get_rid()]
	
	var down_hit = space_state.intersect_ray(down_query)
	if down_hit.is_empty():
		return result
	
	# 確認是水平表面
	if down_hit.normal.dot(Vector3.UP) < 0.7:
		return result
	
	# 2. 向前射線確認牆面存在
	var forward_dir = - climb.surface_normal
	var wall_check_pos = down_hit.position - Vector3.UP * 0.5
	var wall_query = PhysicsRayQueryParameters3D.create(
		wall_check_pos - forward_dir * 0.3,
		wall_check_pos + forward_dir * 0.3
	)
	wall_query.exclude = [get_rid()]
	
	var wall_hit = space_state.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return result
	
	# 計算新的懸掛位置
	result.found = true
	result.grab_point = down_hit.position
	
	# 身體位置（與進入懸掛狀態相同的偏移邏輯）
	var wall_offset = 0.5 # ★ 減少：讓角色更靠近牆面
	var offset_dir = climb.surface_normal.normalized()
	result.position = Vector3(
		wall_hit.position.x + offset_dir.x * wall_offset,
		down_hit.position.y - 2.18, # ★ 分析 Hanging_Idle：手高度 2.18m
		wall_hit.position.z + offset_dir.z * wall_offset
	)
	
	return result

## ==================== Hand IK for Climbing ====================

## 設置手部 IK 用於懸掛狀態
func _setup_hand_ik_for_hang() -> void:
	if not _skeleton:
		return
	
	_hand_ik_enabled = true
	
	# 計算手部目標位置（在邊緣上方，左右對稱）
	_update_hand_ik_targets()
	
	# ★ 平滑 blend-in（跟腳部 IK 同樣模式，左右手分開計時）
	# 右手先抵達 (0.05s 後開始, 0.25s blend)
	var right_tween = create_tween()
	right_tween.tween_interval(0.05)
	right_tween.tween_method(_set_right_arm_ik_weight, 0.0, ARM_IK_MAX_INFLUENCE, 0.25)
	
	# 左手稍後 (0.1s 後開始, 0.25s blend)
	var left_tween = create_tween()
	left_tween.tween_interval(0.1)
	left_tween.tween_method(_set_left_arm_ik_weight, 0.0, ARM_IK_MAX_INFLUENCE, 0.25)
	
	if verbose_debug: print(">>> [Hand IK] 平滑啟用手部 IK (最大權重=%.1f)" % ARM_IK_MAX_INFLUENCE)
	if verbose_debug: print(">>> [Hand IK] grab_point=%s, char_pos=%s, 手到邊緣距離=%.2fm" % [climb.grab_point, global_position, climb.grab_point.y - global_position.y])

## 更新手部 IK 目標位置（可在懸掛/shimmy 時每幀調用）
func _update_hand_ik_targets() -> void:
	var wall_tangent = climb.surface_normal.cross(Vector3.UP).normalized()
	var edge_pos = climb.grab_point - Vector3.UP * HAND_OFFSET_FROM_EDGE
	# ★ 手部往牆面方向偏移，讓手指勾住邊緣轉角處
	edge_pos -= climb.surface_normal * 0.1
	
	var right_hand_pos = edge_pos - wall_tangent * HAND_HORIZONTAL_SPREAD
	var left_hand_pos = edge_pos + wall_tangent * HAND_HORIZONTAL_SPREAD
	
	# 設置 Hand Target 位置
	if right_hand_target:
		right_hand_target.global_position = right_hand_pos
	if left_hand_target:
		left_hand_target.global_position = left_hand_pos
	
	# ★ 設置 Pole Node 位置（業界標準：手肘指向下方）
	# Pole 在手的下方，讓手肘自然向下彎曲
	# 加上往身體中心偏移 + 往外側展開，讓手肘不會太僵硬
	var body_center = global_position + Vector3.UP * 1.0 # 約胸口高度
	var to_body_r = (body_center - right_hand_pos).normalized()
	var to_body_l = (body_center - left_hand_pos).normalized()
	
	var right_elbow_pos = right_hand_pos + Vector3.DOWN * ELBOW_POLE_DROP + to_body_r * ELBOW_POLE_TOWARD_BODY - wall_tangent * ELBOW_POLE_OUTWARD
	var left_elbow_pos = left_hand_pos + Vector3.DOWN * ELBOW_POLE_DROP + to_body_l * ELBOW_POLE_TOWARD_BODY + wall_tangent * ELBOW_POLE_OUTWARD
	
	if right_elbow_pole:
		right_elbow_pole.global_position = right_elbow_pos
	if left_elbow_pole:
		left_elbow_pole.global_position = left_elbow_pos

## 禁用手部 IK（平滑 blend-out，跟腳部 IK 同樣模式）
func _disable_hand_ik() -> void:
	_hand_ik_enabled = false
	
	# 平滑 blend-out (0.2 秒)
	var right_tween = create_tween()
	right_tween.tween_method(_set_right_arm_ik_weight, _right_arm_ik_weight, 0.0, 0.2)
	
	var left_tween = create_tween()
	left_tween.tween_method(_set_left_arm_ik_weight, _left_arm_ik_weight, 0.0, 0.2)
	
	if verbose_debug: print(">>> [Hand IK] 平滑禁用手部 IK (blend →0)")

## 設置右手 IK 權重（跟腳部 _set_right_ik_weight 同樣模式）
func _set_right_arm_ik_weight(weight: float) -> void:
	_right_arm_ik_weight = weight
	if right_arm_ik:
		right_arm_ik.set("influence", weight)

## 設置左手 IK 權重
func _set_left_arm_ik_weight(weight: float) -> void:
	_left_arm_ik_weight = weight
	if left_arm_ik:
		left_arm_ik.set("influence", weight)


## ★ 初始化手部 IK 節點（跟腳部 IK 同樣模式：啟動時 influence=0, active=true）
func _setup_arm_ik_nodes() -> void:
	if not _skeleton:
		return
	
	# 查找現有的 TwoBoneIK3D 節點（在骨架下）
	for child in _skeleton.get_children():
		if child is SkeletonModifier3D:
			var child_name = child.name.to_lower()
			if "rightarm" in child_name or "right_arm" in child_name:
				right_arm_ik = child
				if verbose_debug: print(">>> [Arm IK] 找到 RightArmIK: ", child.name)
			elif "leftarm" in child_name or "left_arm" in child_name:
				left_arm_ik = child
				if verbose_debug: print(">>> [Arm IK] 找到 LeftArmIK: ", child.name)
	
	# 查找 Player 節點下的 IK 標記節點
	right_hand_target = get_node_or_null("RightHandTarget")
	left_hand_target = get_node_or_null("LeftHandTarget")
	right_elbow_pole = get_node_or_null("RightElbowPole")
	left_elbow_pole = get_node_or_null("LeftElbowPole")
	
	# 如果沒有找到，動態創建
	if not right_hand_target:
		right_hand_target = Marker3D.new()
		right_hand_target.name = "RightHandTarget"
		add_child(right_hand_target)
	if not left_hand_target:
		left_hand_target = Marker3D.new()
		left_hand_target.name = "LeftHandTarget"
		add_child(left_hand_target)
	if not right_elbow_pole:
		right_elbow_pole = Marker3D.new()
		right_elbow_pole.name = "RightElbowPole"
		add_child(right_elbow_pole)
	if not left_elbow_pole:
		left_elbow_pole = Marker3D.new()
		left_elbow_pole.name = "LeftElbowPole"
		add_child(left_elbow_pole)
	
	# ★ 關鍵：跟腳部 IK 同樣，先設 influence=0，再 active=true
	# 這樣啟動時手不會被 IK 控制，只有攀爬時才啟用
	if right_arm_ik:
		right_arm_ik.set("influence", 0.0)
		right_arm_ik.set("active", true)
	if left_arm_ik:
		left_arm_ik.set("influence", 0.0)
		left_arm_ik.set("active", true)
	
	_right_arm_ik_weight = 0.0
	_left_arm_ik_weight = 0.0
	
	if verbose_debug: print(">>> [Arm IK] 初始化完成: influence=0, active=true")
	if verbose_debug: print(">>> [Arm IK] right_ik=%s, left_ik=%s, right_target=%s, left_target=%s, right_pole=%s, left_pole=%s" % [
		right_arm_ik != null, left_arm_ik != null,
		right_hand_target != null, left_hand_target != null,
		right_elbow_pole != null, left_elbow_pole != null
	])

## 更新 Shimmy 時的手部 IK 目標
func _update_hand_ik_for_shimmy() -> void:
	if not _hand_ik_enabled:
		return
	_update_hand_ik_targets()

#endregion

#region ==================== 速度曲線系統 (Velocity Curve System) ====================

## 使用自定義曲線應用速度變化
## target_vel: 目標速度向量
## delta: 幀時間
func _apply_velocity_curve(target_vel: Vector3, delta: float) -> void:
	var _current_h_speed = Vector2(velocity.x, velocity.z).length() # 供調試用
	var target_h_speed = Vector2(target_vel.x, target_vel.z).length()
	var is_moving_now = target_h_speed > 0.1
	
	# 檢測狀態變化（開始移動 or 停止移動）
	if is_moving_now != _curve_was_moving:
		# 狀態改變，重置曲線
		_curve_time = 0.0
		_curve_start_velocity = velocity
		_curve_target_velocity = target_vel
		_is_accelerating = is_moving_now
		_curve_was_moving = is_moving_now
	elif (_curve_target_velocity - target_vel).length() > 1.0:
		# 目標速度顯著變化（例如改變方向）
		_curve_time = 0.0
		_curve_start_velocity = velocity
		_curve_target_velocity = target_vel
	
	# 選擇曲線和持續時間
	var active_curve: Curve = movement_data.acceleration_curve if _is_accelerating else movement_data.deceleration_curve
	var duration: float = movement_data.curve_duration_accel if _is_accelerating else movement_data.curve_duration_decel
	
	# 更新曲線時間
	_curve_time += delta
	var t = clamp(_curve_time / maxf(duration, 0.01), 0.0, 1.0)
	
	# 計算曲線插值因子
	var curve_factor: float = t
	if active_curve:
		curve_factor = active_curve.sample(t)
	
	# 對於減速曲線：曲線值代表「剩餘速度比例」(1=全速, 0=停止)
	# 所以需要直接用曲線值作為速度的乘數
	if _is_accelerating:
		# 加速：從 start 插值到 target
		velocity.x = lerpf(_curve_start_velocity.x, _curve_target_velocity.x, curve_factor)
		velocity.z = lerpf(_curve_start_velocity.z, _curve_target_velocity.z, curve_factor)
	else:
		# 減速：曲線值代表剩餘速度比例
		velocity.x = _curve_start_velocity.x * curve_factor
		velocity.z = _curve_start_velocity.z * curve_factor

#endregion

#region ==================== 腳部過渡鎖定系統 (Foot Transition Lock) ====================

## 初始化腳部骨骼索引（應在 _ready 中呼叫）
func _init_foot_bone_indices() -> void:
	if skeleton:
		_left_foot_bone_idx = skeleton.find_bone("LeftFoot")
		_right_foot_bone_idx = skeleton.find_bone("RightFoot")
		if _left_foot_bone_idx == -1 or _right_foot_bone_idx == -1:
			push_warning("Foot bones not found! LeftFoot: %d, RightFoot: %d" % [_left_foot_bone_idx, _right_foot_bone_idx])

## 捕捉當前腳部世界位置（過渡開始時呼叫）
func _capture_foot_positions() -> void:
	if not skeleton:
		return
	if _left_foot_bone_idx == -1:
		_init_foot_bone_indices()
	var left_pose := skeleton.get_bone_global_pose(_left_foot_bone_idx)
	var right_pose := skeleton.get_bone_global_pose(_right_foot_bone_idx)
	_locked_left_foot_pos = skeleton.global_transform * left_pose.origin
	_locked_right_foot_pos = skeleton.global_transform * right_pose.origin

## 開始腳部過渡鎖定（從移動到 Idle 過渡時呼叫）
func _start_foot_transition_lock() -> void:
	_capture_foot_positions()
	_transition_foot_lock_active = true
	_transition_foot_lock_time = 0.0

## 處理腳部過渡鎖定（每幀在過渡期間呼叫）
func _process_foot_transition_lock(delta: float) -> bool:
	if not _transition_foot_lock_active:
		return false
	_transition_foot_lock_time += delta
	var lock_duration := 0.3
	if _transition_foot_lock_time >= lock_duration:
		_transition_foot_lock_active = false
		return false
	var blend := 1.0 - (_transition_foot_lock_time / lock_duration)
	blend = ease(blend, 0.5)
	if not skeleton:
		return true
	# IK 目標位置計算完成，需配合場景 TwoBoneIK3D 使用
	return true

## 獲取腳部鎖定混合權重
func get_foot_lock_blend() -> float:
	if not _transition_foot_lock_active:
		return 0.0
	return 1.0 - clamp(_transition_foot_lock_time / 0.3, 0.0, 1.0)

## 獲取鎖定的左腳位置
func get_locked_left_foot_pos() -> Vector3:
	return _locked_left_foot_pos

## 獲取鎖定的右腳位置
func get_locked_right_foot_pos() -> Vector3:
	return _locked_right_foot_pos

#endregion

#region ==================== 逼真移動系統 (Realistic Movement) ====================


## 應用逼真移動效果：身體傾斜 + 轉向慣性
## move_dir: 當前移動方向（世界座標）
## delta: 幀時間
func _apply_realistic_movement(p_move_dir: Vector3, delta: float) -> void:
	# 初始化（首次執行時記錄原始視覺模型旋轉）
	if not _realistic_movement_initialized:
		if visuals_node:
			# 記錄場景中設定的原始 Y 旋轉（Human 模型有 180° 旋轉）
			_visual_facing_angle = visuals_node.rotation.y
		_target_facing_angle = _visual_facing_angle
		_realistic_movement_initialized = true
	
	# 計算身體傾斜
	if movement_data.body_lean_enabled:
		_apply_body_lean(delta)
	
	# ★ Souls-like：不再需要 visual 模型獨立旋轉
	# CharacterBody3D.rotation.y 直接面向移動方向
	# visuals_node 保持原始 180° 旋轉即可

## 身體傾斜：根據加速度方向傾斜角色身體
## 轉彎時角色會向彎道內側傾斜，增加重量感
func _apply_body_lean(delta: float) -> void:
	if not skeleton:
		return
	
	# 獲取當前水平速度
	var current_h_vel = Vector2(velocity.x, velocity.z)
	var h_speed = current_h_vel.length()
	
	# 計算加速度（速度變化率）
	var h_accel = (current_h_vel - _prev_h_velocity) / maxf(delta, 0.001)
	_prev_h_velocity = current_h_vel
	
	# 將加速度轉換到角色本地座標系
	var world_accel = Vector3(h_accel.x, 0, h_accel.y)
	var local_accel = transform.basis.inverse() * world_accel
	
	# 側向加速度決定傾斜方向（負 = 向左傾斜）
	# 速度越快傾斜越明顯（速度因子：0~1）
	var speed_factor = clampf(h_speed / movement_data.sprint_speed, 0.0, 1.0)
	var target_lean = clamp(-local_accel.x * 0.15 * speed_factor, -movement_data.body_lean_amount, movement_data.body_lean_amount)
	
	# 平滑過渡到目標傾斜角度
	_current_body_lean = lerp(_current_body_lean, target_lean, movement_data.body_lean_smooth * delta)
	
	# ★ 分散到 Spine + Spine1 骨骼（更自然的弧度，不會在一個關節折斷）
	var lean_rad = deg_to_rad(_current_body_lean)
	var spine_names = ["Spine", "Spine1"]
	var spine_weights = [1.0, 0.6] # Spine 全量，Spine1 60%
	for i in spine_names.size():
		var bone_idx = skeleton.find_bone(spine_names[i])
		if bone_idx >= 0:
			var pose = skeleton.get_bone_pose(bone_idx)
			var lean_rotation = Quaternion(Vector3.FORWARD, lean_rad * spine_weights[i])
			pose.basis = Basis(pose.basis.get_rotation_quaternion() * lean_rotation)
			skeleton.set_bone_pose(bone_idx, pose)

## 轉向慣性：視覺模型平滑轉向目標方向
## 角色不會瞬間轉身，而是有自然的轉向動畫
func _apply_turn_momentum(move_dir: Vector3, delta: float) -> void:
	if not visuals_node:
		return
	
	# 計算目標朝向角度（基於移動方向）
	_target_facing_angle = atan2(move_dir.x, move_dir.z)
	
	# 使用 lerp_angle 避免 360° 跳變問題
	# turn_rate 是度/秒，需要轉換為弧度並計算每幀的插值量
	var turn_speed_this_frame = deg_to_rad(movement_data.turn_rate) * delta
	var angle_diff = abs(wrapf(_target_facing_angle - _visual_facing_angle, -PI, PI))
	
	# 根據角度差動態調整轉向速度
	# 小角度時更快完成轉向，大角度時保持一致的角速度
	var t: float
	if angle_diff < 0.1: # 幾乎對齊時直接 snap
		t = 1.0
	else:
		t = clampf(turn_speed_this_frame / angle_diff, 0.0, 1.0)
	
	_visual_facing_angle = lerp_angle(_visual_facing_angle, _target_facing_angle, t)
	
	# 應用到視覺模型的 Y 軸旋轉（水平轉向）
	# 注意：需要減去 CharacterBody3D 的旋轉，因為視覺模型是子節點
	visuals_node.rotation.y = _visual_facing_angle - rotation.y

#endregion

# ==============================================================================
# region Step-Up Stair Climbing (樓梯攀爬系統)
# ==============================================================================

## 載入樓梯動畫：優先從 movement library 取得，否則從 FBX 提取
func _load_stair_animations() -> void:
	if not anim_player:
		return
	
	# ★ Root Motion 版：從 FBX 運行時提取（保留 Hips Y 位移作為 Root Motion）
	if verbose_debug: print(">>> [Stairs-RM] 載入 Root Motion 樓梯動畫...")
	var stair_lib = AnimationLibrary.new()
	var loaded_count = 0
	
	# ★ 走路上樓動畫 (Walking Up The Stairs - 有完整 Y+Z Root Motion)
	var ascend_anim = _extract_fbx_animation(STAIR_WALK_ASCEND_FBX)
	if ascend_anim:
		ascend_anim.loop_mode = Animation.LOOP_LINEAR
		# ★ 將 Root Motion 動畫轉換為 In-Place 動畫，並去趨勢 Y 軸
		_strip_root_motion_from_stair_animation(ascend_anim)
		stair_lib.add_animation(STAIR_ASCEND_ANIM, ascend_anim)
		loaded_count += 1
		if verbose_debug: print(">>> [Stairs] ✅ 走路上樓: %s" % STAIR_ASCEND_ANIM)
	
	# ★ 走路下樓動畫 (Descending Stairs (1) - 有完整 Y+Z Root Motion)
	var descend_anim = _extract_fbx_animation(STAIR_DESCEND_FBX)
	if descend_anim:
		descend_anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion_from_stair_animation(descend_anim)
		stair_lib.add_animation(STAIR_DESCEND_ANIM, descend_anim)
		loaded_count += 1
		if verbose_debug: print(">>> [Stairs] ✅ 走路下樓: %s" % STAIR_DESCEND_ANIM)
	
	# ★ 跑步上樓動畫 (Running Up Stairs - 有完整 Y+Z Root Motion)
	var run_ascend_anim = _extract_fbx_animation(STAIR_RUN_ASCEND_FBX)
	if run_ascend_anim:
		run_ascend_anim.loop_mode = Animation.LOOP_LINEAR
		_strip_root_motion_from_stair_animation(run_ascend_anim)
		stair_lib.add_animation(STAIR_RUN_ASCEND_ANIM, run_ascend_anim)
		_stair_run_anim_loaded = true
		loaded_count += 1
		if verbose_debug: print(">>> [Stairs] ✅ 跑步上樓: %s" % STAIR_RUN_ASCEND_ANIM)
	
	if loaded_count == 0:
		if verbose_debug: print(">>> [Stairs-RM] ❌ 沒有載入任何樓梯動畫")
		return
	
	# 移除舊的樓梯動畫庫
	if anim_player.has_animation_library(STAIR_ANIM_LIB):
		anim_player.remove_animation_library(STAIR_ANIM_LIB)
	
	anim_player.add_animation_library(STAIR_ANIM_LIB, stair_lib)
	_stair_anim_prefix = STAIR_ANIM_LIB
	_stair_anims_loaded = true
	if verbose_debug: print(">>> [Stairs-RM] ✅ 樓梯動畫庫已載入 (%d 個動畫，run=%s)" % [loaded_count, _stair_run_anim_loaded])


func _extract_fbx_animation(fbx_path: String) -> Animation:
	var fbx_scene = load(fbx_path) as PackedScene
	if not fbx_scene:
		if verbose_debug: print(">>> [Stairs] ❌ 無法載入 FBX: %s" % fbx_path)
		return null
	
	var fbx_instance = fbx_scene.instantiate()
	
	# 搜尋 AnimationPlayer
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
		if verbose_debug: print(">>> [Stairs] ❌ FBX 中找不到 AnimationPlayer: %s" % fbx_path)
		fbx_instance.queue_free()
		return null
	
	# 提取第一個動畫
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
	
	# 重新映射軌道路徑（FBX 骨骼路徑 → 場景骨骼路徑）
	# ★ AnimationPlayer.root_node = "../Visuals/Human"，所以路徑相對於 Visuals/Human
	var our_skeleton_path = "%GeneralSkeleton" # ★ Godot unique name 語法
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

## ★ 轉換為 In-Place 動畫：完全消除 X 與 Z 位移，並去趨勢 Hips Y
## 原理：強制將 X 和 Z 鎖定為第一幀的值；Y 軸則減去線性趨勢保留步伐擺動。
func _strip_root_motion_from_stair_animation(anim: Animation) -> void:
	for i in range(anim.get_track_count()):
		var path = str(anim.track_get_path(i))
		# 找到 Hips 位置軌（type=1 = TYPE_POSITION_3D）
		if path.ends_with(":Hips") and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			var key_count = anim.track_get_key_count(i)
			if key_count < 2:
				break
			
			# 取得第一幀和最後一幀的值
			var first_val: Vector3 = anim.track_get_key_value(i, 0)
			var last_val: Vector3 = anim.track_get_key_value(i, key_count - 1)
			
			var first_y: float = first_val.y
			var last_y: float = last_val.y
			var total_y_drift: float = last_y - first_y # 累積 Y 漂移
			var duration: float = anim.length
			
			# 對每個 keyframe：消除 XZ 位移，減去 Y 線性趨勢
			for k in range(key_count):
				var key_time: float = anim.track_get_key_time(i, k)
				var val: Vector3 = anim.track_get_key_value(i, k)
				
				# 去除 Y 線性趨勢 (如果有)
				if abs(total_y_drift) >= 0.01 and duration >= 0.01:
					var trend_y: float = total_y_drift * (key_time / duration)
					val.y = val.y - trend_y
				
				# ★ 完全消除 X 與 Z 的位移，讓它變成一個純原地的 In-Place 動畫！
				val.x = first_val.x
				val.z = first_val.z
				
				anim.track_set_key_value(i, k, val)
			
			if verbose_debug: print(">>> [Stairs] ★ 已將 RootMotion 轉為 In-Place, 並去趨勢 Hips Y（%d keys）" % key_count)
			break

## 偵測是否在樓梯上（前方射線高度差法 + step-up 狀態）
## 使用原始輸入方向（避免 move_and_slide 碰撞後 velocity 為零）
func _detect_stairs() -> void:
	# ★ 遞減寬限計時器
	var delta = get_physics_process_delta_time()
	if stair.grace_timer > 0:
		stair.grace_timer -= delta
	
	# ★ 使用 ground.was_on_floor 容忍樓梯間隙 1 幀離地
	if not is_on_floor() and not ground.was_on_floor or _is_jumping or _is_landing:
		# ★ 寬限期內保持 stair.on_stairs 為 true（防止閃爍）
		if stair.grace_timer > 0:
			return
		stair.on_stairs = false
		stair.params_valid = false
		stair.step_height_measured = 0.0
		return
	
	# ★ step-up 正在執行或剛完成 → 設為樓梯（物理管線需要）
	# 動畫選擇（走路 vs 樓梯）在動畫觸發處另外判斷
	if stair.step_up_offset > 0.0 or stair.post_step_up_cooldown > 0:
		stair.on_stairs = true
		stair.ascending = true
		stair.grace_timer = 0.3
		return
	
	# ★ 使用原始輸入方向取代 velocity
	var move_dir := Vector3.ZERO
	if _main_camera:
		var raw = Input.get_vector("left", "right", "forward", "backward")
		if raw.length() > 0.1:
			var cam_basis = _main_camera.global_transform.basis
			var cam_fwd = (-cam_basis.z)
			cam_fwd.y = 0
			cam_fwd = cam_fwd.normalized()
			var cam_right = cam_basis.x
			cam_right.y = 0
			cam_right = cam_right.normalized()
			move_dir = (cam_fwd * (-raw.y) + cam_right * raw.x).normalized()
	
	if move_dir.length() < 0.1:
		stair.on_stairs = false
		stair.params_valid = false
		stair.step_height_measured = 0.0
		return
	
	var space = get_world_3d().direct_space_state
	
	# ★★★ 改進版樓梯偵測：區分「台階」與「斜坡」 ★★★
	# 台階特徵：
	#   1. 踏面 (tread) — 水平面，法線接近 Vector3.UP (dot > 0.9)
	#   2. 踢面 (riser) — 垂直面，前方水平射線能命中
	# 斜坡特徵：
	#   - 表面法線傾斜 (dot with UP < 0.9)
	#   - 前方沒有垂直面
	
	# --- Pass 1: 下方射線偵測高度差，同時檢查法線 ---
	var hits: Array[Dictionary] = []
	var has_flat_tread := false # 是否偵測到水平踏面
	
	for dist in [0.3, 0.6]:
		var check_pos = global_position + move_dir * dist + Vector3.UP * 0.6
		var query = PhysicsRayQueryParameters3D.create(check_pos, check_pos + Vector3.DOWN * 1.2)
		query.exclude = [get_rid()]
		query.collision_mask = 1
		var hit = space.intersect_ray(query)
		
		if hit:
			var height_diff = hit.position.y - global_position.y
			if abs(height_diff) > 0.05 and abs(height_diff) < movement_data.max_step_height:
				# ★ 關鍵：檢查表面法線 — 台階踏面是水平的
				var normal_dot = hit.normal.dot(Vector3.UP)
				if normal_dot > 0.9: # 幾乎水平 (< ~25° 傾斜)
					has_flat_tread = true
					hits.append(hit)
				# else: 斜坡表面，忽略
	
	# --- Pass 2: 前方水平射線偵測垂直踢面 (riser) ---
	var has_riser := false
	if has_flat_tread:
		# 從腳踝高度向前射線，偵測台階的垂直面
		for check_h in [0.08, 0.15, 0.25]:
			var ray_start = global_position + Vector3.UP * check_h
			var ray_end = ray_start + move_dir * 0.5
			var riser_query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
			riser_query.exclude = [get_rid()]
			riser_query.collision_mask = 1
			var riser_hit = space.intersect_ray(riser_query)
			
			if riser_hit:
				# 踢面法線應該接近水平 (垂直牆面)
				var riser_normal_y = abs(riser_hit.normal.y)
				if riser_normal_y < 0.3: # 法線幾乎水平 → 垂直面
					has_riser = true
					break
	
	# ★★★ 結論：只有同時偵測到「水平踏面 + 垂直踢面」才算樓梯 ★★★
	if hits.size() > 0 and has_flat_tread and has_riser:
		stair.on_stairs = true
		var first_h_diff = hits[0].position.y - global_position.y
		stair.ascending = first_h_diff > 0.05 or stair.step_up_offset > 0.0
		stair.grace_timer = 0.3
		
		# ★ 階梯投影參數：使用 floor-to-hit 策略（不再依賴兩 hit 不同高度）
		# Step 1: step_height 來自 step-up running average（已在 step-up 時更新）
		#         只在沒有 running average 時用 hit 高度差作為種子
		if stair.step_height_measured < 0.01 and first_h_diff > 0.03:
			stair.step_height_measured = abs(first_h_diff)
		
		# Step 2: step_depth 從第一個 hit 的水平距離 / hit 的高度差估算
		#         多數台階深度在 0.25-0.35m 之間
		if hits.size() >= 2:
			var h1: Vector3 = hits[0].position
			var h2: Vector3 = hits[1].position
			var dy = abs(h2.y - h1.y)
			var dxz = Vector2(h2.x - h1.x, h2.z - h1.z).length()
			if dy > 0.03 and dxz > 0.05:
				stair.step_depth = lerpf(stair.step_depth, dxz, 0.3)
		elif stair.step_depth < 0.01:
			stair.step_depth = 0.30 # 合理預設值
		
		# Step 3: 方向鎖定 — 首次設定用 move_dir，之後只有角度差 > 30° 才漸進更新
		var new_dir = Vector2(move_dir.x, move_dir.z).normalized()
		# 確保方向指向上坡方向（ascending = 正方向）
		if not stair.ascending:
			new_dir = - new_dir # 反轉為上坡方向
		
		if not stair.params_valid:
			# 首次捕獲：直接設定
			stair.dir_xz = new_dir
		else:
			# 已有方向：只在角度差 > 30° 時漸進更新（防止抖動）
			var dot = stair.dir_xz.dot(new_dir)
			if dot < 0.866: # cos(30°) ≈ 0.866
				stair.dir_xz = stair.dir_xz.lerp(new_dir, 0.1).normalized()
		
		# Step 4: base_pos 持續更新為最新的 hit 位置
		stair.base_pos = hits[0].position
		
		# ★ 只要有 step_height 就激活投影（不再要求兩 hit 不同高度）
		if stair.step_height_measured > 0.02:
			stair.params_valid = true
		
		if Engine.get_frames_drawn() % 60 == 0 and stair.params_valid:
			if verbose_debug: print(">>> [StairProj] step_h=%.3f step_d=%.3f dir=(%.2f,%.2f) base_y=%.3f valid=%s" % [
				stair.step_height_measured, stair.step_depth,
				stair.dir_xz.x, stair.dir_xz.y, stair.base_pos.y, stair.params_valid
			])
		return
	
	# ★ 寬限期內保持 stair.on_stairs
	if stair.grace_timer > 0:
		return
	stair.on_stairs = false
	stair.params_valid = false
	stair.step_height_measured = 0.0

## 檢測前方是否有可攀越的台階（3-ray detection）
## 返回需要提升的高度，如果無法攀越則返回 0
## UE5-style step-up：raise → forward → lower
## 使用 test_move() 取代射線，用整個膠囊形狀偵測碰撞
func _check_step_up() -> float:
	var max_step = movement_data.max_step_height
	
	# ★ 前方探測距離 0.35m（必須夠長，讓膠囊落在台階頂面而非邊緣）
	var h_motion := Vector3.ZERO
	if _main_camera:
		var raw = Input.get_vector("left", "right", "forward", "backward")
		if raw.length() > 0.1:
			var cam_basis = _main_camera.global_transform.basis
			var cam_forward = - cam_basis.z
			cam_forward.y = 0
			cam_forward = cam_forward.normalized()
			var cam_right = cam_basis.x
			cam_right.y = 0
			cam_right = cam_right.normalized()
			h_motion = (cam_forward * (-raw.y) + cam_right * raw.x).normalized() * 0.35
	
	if h_motion.length() < 0.001:
		var h_vel = Vector3(velocity.x, 0, velocity.z)
		if h_vel.length() < 0.1:
			if stair.on_stairs and Engine.get_frames_drawn() % 10 == 0:
				if verbose_debug: print(">>> [CheckStep] FAIL: no h_motion & h_vel < 0.1 (vel=%.3f)" % h_vel.length())
			return 0.0
		h_motion = h_vel.normalized() * 0.35
	
	# 用較短距離偵測前方是否有障礙
	# ★ 在樓梯上跳過此檢查 — 膠囊弧形底部會滑過台階面，test_move 偵測不到
	if not (stair.on_stairs and stair.ascending):
		var short_probe = h_motion.normalized() * 0.15
		var from_xform_probe = global_transform
		if not test_move(from_xform_probe, short_probe):
			return 0.0 # 前方沒有障礙，不需要 step-up
	
	# === 前方被擋住，開始 step-up ===
	var from_xform = global_transform
	var raise_motion = Vector3(0, max_step, 0)
	var raise_col = KinematicCollision3D.new()
	var raise_blocked = test_move(from_xform, raise_motion, raise_col)
	var actual_raise = max_step
	if raise_blocked:
		actual_raise = raise_col.get_travel().y
	if actual_raise < 0.02:
		return 0.0
	
	var raised_xform = from_xform
	raised_xform.origin.y += actual_raise
	# 在提升後的位置用完整距離前進
	if test_move(raised_xform, h_motion):
		if stair.on_stairs and Engine.get_frames_drawn() % 10 == 0:
			if verbose_debug: print(">>> [CheckStep] FAIL: blocked after raise (raise=%.3f)" % actual_raise)
		return 0.0
	
	var forward_xform = raised_xform
	forward_xform.origin += h_motion
	var drop_motion = Vector3(0, - (actual_raise + 0.05), 0)
	var drop_col = KinematicCollision3D.new()
	if not test_move(forward_xform, drop_motion, drop_col):
		if stair.on_stairs and Engine.get_frames_drawn() % 10 == 0:
			if verbose_debug: print(">>> [CheckStep] FAIL: no ground after forward+drop")
		return 0.0
	
	var drop_travel = drop_col.get_travel().y
	var final_y = forward_xform.origin.y + drop_travel
	var step_height = final_y - global_position.y
	
	if step_height > 0.01 and step_height <= max_step:
		var normal = drop_col.get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle:
			return step_height
		# ★ 邊緣角度太陡 → 往前多偏移一點重試（找到台階頂面而非邊緣）
		var nudge_xform = forward_xform
		nudge_xform.origin += h_motion.normalized() * 0.05
		var nudge_col = KinematicCollision3D.new()
		if test_move(nudge_xform, drop_motion, nudge_col):
			var nudge_normal = nudge_col.get_normal()
			if nudge_normal.angle_to(Vector3.UP) <= floor_max_angle:
				var nudge_y = nudge_xform.origin.y + nudge_col.get_travel().y
				var nudge_step = nudge_y - global_position.y
				if nudge_step > 0.01 and nudge_step <= max_step:
					return nudge_step
		# ★ 最後防線：角度雖陡但高度合法 → 仍然接受（防卡死）
		return step_height
	return 0.0
## Step-Up 後貼回地面
func _snap_after_step_up() -> void:
	var space_state = get_world_3d().direct_space_state
	var ray_start = global_position + Vector3.UP * 0.1
	var ray_end = global_position + Vector3.DOWN * (movement_data.max_step_height + 0.2)
	
	var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	
	if result:
		global_position.y = result.position.y

## ★ 新版 Step-Up：社區最佳實踐（move_and_slide 前呼叫）
## 使用 test_move 做 raise→forward→drop 偵測，自適應任何台階幾何
func _snap_up_stairs_check(_delta: float) -> void:
	# ★ Pre-MAS snap_up（在 move_and_slide 前呼叫）
	# 偵測前方台階 → 只抬升 Y → MAS 在抬升後的高度平滑前進
	# 不修改 XZ → 保持樓梯攀爬動畫的自然感
	var h_vel = Vector3(velocity.x, 0, velocity.z)
	if h_vel.length() < 0.1:
		return
	
	var fwd_dir = h_vel.normalized()
	var max_step = movement_data.max_step_height
	var cur_pos = global_position
	
	# 動態取得碰撞體半徑
	var capsule_r = 0.35
	var col_shape = get_node_or_null("CollisionShape3D")
	if col_shape and col_shape.shape:
		if col_shape.shape is CapsuleShape3D or col_shape.shape is CylinderShape3D:
			capsule_r = col_shape.shape.radius
	
	# ★ Pre-Gate: 前方是否被台階擋住？
	# 如果一幀的前進不會被擋住 → 還沒到台階邊 → 不需要抬升 → 正常行走
	var gate_params = PhysicsTestMotionParameters3D.new()
	gate_params.from = Transform3D(global_basis, cur_pos)
	gate_params.motion = fwd_dir * (h_vel.length() * _delta + 0.01)
	var gate_result = PhysicsTestMotionResult3D.new()
	var would_be_blocked = PhysicsServer3D.body_test_motion(get_rid(), gate_params, gate_result)
	if not would_be_blocked:
		return # 沒被擋住 → 不在台階邊緣 → 跳過
	
	# ★ 斜坡過濾已移除 — body_test_motion 的碰撞法線在膠囊圓弧碰角時不可靠
	# 改由下方 Phase 3 的「著陸面法線檢查」來過濾斜坡（更準確）
	
	# ★ Phase 1: 從當前位置向上提升 max_step
	var raise_xform = Transform3D(global_basis, cur_pos)
	var raise_params = PhysicsTestMotionParameters3D.new()
	raise_params.from = raise_xform
	raise_params.motion = Vector3(0, max_step, 0)
	var raise_result = PhysicsTestMotionResult3D.new()
	
	var raise_blocked = PhysicsServer3D.body_test_motion(get_rid(), raise_params, raise_result)
	var actual_raise = max_step
	if raise_blocked:
		actual_raise = raise_result.get_travel().y
	if actual_raise < 0.02:
		return
	
	# ★ Phase 2: 從抬升位置向前探測（用膠囊半徑距離偵測台階）
	var raised_pos = cur_pos + Vector3(0, actual_raise, 0)
	var raised_xform = Transform3D(global_basis, raised_pos)
	
	var fwd_dist = capsule_r + 0.1 # 足夠偵測台階邊緣
	var fwd_params = PhysicsTestMotionParameters3D.new()
	fwd_params.from = raised_xform
	fwd_params.motion = fwd_dir * fwd_dist
	var fwd_result = PhysicsTestMotionResult3D.new()
	
	var fwd_blocked = PhysicsServer3D.body_test_motion(get_rid(), fwd_params, fwd_result)
	var fwd_travel = fwd_result.get_travel() if fwd_blocked else fwd_dir * fwd_dist
	
	if fwd_travel.length() < 0.001:
		return
	
	# ★ Phase 3: 從抬升+前進位置向下探測 → 找台階表面
	var fwd_pos = raised_pos + fwd_travel
	var drop_params = PhysicsTestMotionParameters3D.new()
	drop_params.from = Transform3D(global_basis, fwd_pos)
	drop_params.motion = Vector3(0, - (actual_raise + 0.1), 0)
	var drop_result = PhysicsTestMotionResult3D.new()
	
	if not PhysicsServer3D.body_test_motion(get_rid(), drop_params, drop_result):
		return
	
	# ★ 計算台階高度
	var landing_pos = fwd_pos + drop_result.get_travel()
	var step_height = landing_pos.y - cur_pos.y
	
	# 驗證：步高必須在合理範圍
	if step_height < 0.01 or step_height > max_step:
		return
	
	# 驗證：表面法線必須是地面
	var normal = drop_result.get_collision_normal()
	if normal.angle_to(Vector3.UP) > floor_max_angle:
		# 邊緣法線有時不準，微推後重試
		var nudge_pos = fwd_pos + fwd_dir * 0.05
		var nudge_params = PhysicsTestMotionParameters3D.new()
		nudge_params.from = Transform3D(global_basis, nudge_pos)
		nudge_params.motion = Vector3(0, - (actual_raise + 0.1), 0)
		var nudge_result = PhysicsTestMotionResult3D.new()
		
		if PhysicsServer3D.body_test_motion(get_rid(), nudge_params, nudge_result):
			var nudge_normal = nudge_result.get_collision_normal()
			if nudge_normal.angle_to(Vector3.UP) <= floor_max_angle:
				landing_pos = nudge_pos + nudge_result.get_travel()
				step_height = landing_pos.y - cur_pos.y
				if step_height < 0.01 or step_height > max_step:
					return
			else:
				return
		else:
			return
	
	# ★ 成功！只修改 Y — 讓 MAS 處理平滑的水平移動
	# (物理 Y 必須即時抬升，否則膠囊會撞到台階正面而卡住)
	global_position.y += step_height
	stair.step_up_offset = step_height
	ground.snapped_to_stairs_last_frame = true
	
	# ★ 階梯投影：更新 running average
	if stair.on_stairs and stair.ascending and step_height > 0.02:
		stair.step_height_measured = lerpf(stair.step_height_measured, step_height, 0.3)
	
	# ★ 視覺補償（非樓梯上行時累積 debt）
	if not (stair.on_stairs and stair.ascending):
		stair.step_up_visual_debt -= step_height
	
	if verbose_debug: print(">>> [SnapUp] ✅ step=%.3f pos=(%.2f,%.3f,%.2f) raise=%.3f" % [step_height, global_position.x, global_position.y, global_position.z, actual_raise])

## ★ 新版 Step-Down：社區最佳實踐（move_and_slide 後呼叫）
## 每幀偵測，用 ground.snapped_to_stairs_last_frame 保持連續步進
func _snap_down_stairs_check() -> void:
	# ★ step-up 當幀：保留 snap 狀態，跳過 snap_down
	if stair.step_up_offset > 0.0:
		# ground.snapped_to_stairs_last_frame 已在 snap_up 中設為 true，保留不動
		return
	
	# ★ 非 step-up 幀：重置旗標
	ground.snapped_to_stairs_last_frame = false
	
	# ★ 上行樓梯時跳過 snap_down（避免跟 snap_up 振盪）
	if stair.on_stairs and stair.ascending:
		return
	
	# 已在地面 → 不需要 snap
	if is_on_floor():
		return
	
	# 跳躍中 / 快速上升 → 不處理
	if _is_jumping or velocity.y > 0.1:
		return
	
	# ★ 區分樓梯 vs 平地
	if stair.on_stairs or ground.step_down_snapped:
		pass # 樓梯/持續 snap 模式
	else:
		if not ground.was_on_floor:
			return
	
	var max_down = movement_data.max_step_height
	var down_motion = Vector3(0, -max_down, 0)
	var col = KinematicCollision3D.new()
	
	if not test_move(global_transform, down_motion, col):
		ground.snapped_to_stairs_last_frame = false
		return # 下方 max_step 內無地面
	
	var snap_travel = col.get_travel()
	var snap_y = snap_travel.y
	
	# ★ 用寬鬆角度（65°）因為 test_move 常撞到台階邊角，法線偏斜
	var normal = col.get_normal()
	var normal_angle = rad_to_deg(normal.angle_to(Vector3.UP))
	if normal_angle > 65.0:
		ground.snapped_to_stairs_last_frame = false
		return
	
	if abs(snap_y) < 0.01 or abs(snap_y) >= max_down:
		ground.snapped_to_stairs_last_frame = false
		return
	
	# ★ 執行 snap
	global_position.y += snap_y
	velocity.y = 0.0
	ground.snapped_to_stairs_last_frame = true
	ground.step_down_snapped = true
	air.air_time = 0.0 # 重置離地時間，避免觸發 FALLING
	
	# ★ 視覺補償（非樓梯上行時）
	if not (stair.on_stairs and stair.ascending):
		stair.step_up_visual_debt += snap_y # snap_y 是負值
	
	if Engine.get_frames_drawn() % 30 == 0:
		if verbose_debug: print(">>> [SnapDown] snap_y=%.3f pos_y=%.3f" % [snap_y, global_position.y])

## 樓梯動畫切換
func _update_stair_animation(delta: float) -> void:
	if not _stair_anims_loaded or not anim_player:
		stair.root_motion_active = false
		return
	
	var raw_input = Input.get_vector("left", "right", "forward", "backward")
	var has_input = raw_input.length() > 0.1
	
	# ★ Debug: 每 60 幀印出狀態
	if Engine.get_frames_drawn() % 60 == 0 and has_input:
		if verbose_debug: print(">>> [StairRM] on=%s asc=%s blend=%.2f rm_active=%s vel_y=%.3f" % [
			stair.on_stairs, stair.ascending, stair.blend_weight,
			stair.root_motion_active, stair.rm_velocity.y])
	
	# ★ 條件：在樓梯上 + 有輸入 + 實際在移動 + 不在跳/落地/停止
	# ★ 坡度過濾：只有踩在接近水平的表面（台階踏面）才觸發樓梯動畫
	#   斜坡的法線傾斜 (dot < 0.95) → 用走路動畫
	var h_speed = Vector2(velocity.x, velocity.z).length()
	var is_on_flat_tread = not is_on_floor() or get_floor_normal().dot(Vector3.UP) > 0.95
	var want_stair_anim = stair.on_stairs and is_on_flat_tread and has_input and h_speed > 0.5 and not _is_jumping and not _is_landing and not _is_stopping
	
	if want_stair_anim:
		# ★★★ 方向穩定：使用 committed direction 防止 ascending↔descending 快速切換
		# 每次單步的 snap_up 會讓 velocity.y 短暫反轉，只有計時器到期才允許切換
		const DIR_COMMIT_TIME: float = 0.5 # 最少維持此方向 0.5 秒
		if not stair.dir_committed:
			# 尚未提交方向，直接用當前 stair.ascending
			stair.committed_ascending = stair.ascending
			stair.dir_commit_timer = DIR_COMMIT_TIME
			stair.dir_committed = true
		else:
			stair.dir_commit_timer -= delta
			if stair.dir_commit_timer <= 0.0:
				# 計時器到期 → 若方向仍然不同才切換
				if stair.committed_ascending != stair.ascending:
					stair.committed_ascending = stair.ascending
					if verbose_debug: print(">>> [StairAnim] 方向切換: %s" % ("ascending" if stair.committed_ascending else "descending"))
				stair.dir_commit_timer = DIR_COMMIT_TIME # 重置計時器
		
		# ★ 選擇動畫：上樓走/跑 vs 下樓（使用已提交的穩定方向）
		var stair_anim: String
		var rm_base_speed: float
		if stair.committed_ascending:
			if h_speed > STAIR_RUN_SPEED_THRESHOLD and _stair_run_anim_loaded:
				stair_anim = _stair_anim_prefix + "/" + STAIR_RUN_ASCEND_ANIM
				rm_base_speed = STAIR_RM_RUN_H_SPEED
			else:
				stair_anim = _stair_anim_prefix + "/" + STAIR_ASCEND_ANIM
				rm_base_speed = STAIR_RM_WALK_H_SPEED
		else:
			stair_anim = _stair_anim_prefix + "/" + STAIR_DESCEND_ANIM
			rm_base_speed = STAIR_RM_DESCEND_H_SPEED
		
		# ★ 進入樓梯時：關閉 AnimationTree
		if anim_tree and anim_tree.active:
			anim_tree.active = false
			if verbose_debug: print(">>> [StairAnim] AnimationTree OFF, 進入樓梯動畫模式")
		
		# ★ 不設定 root_motion_track — 讓動畫自然播放（Hips 擺動保留，膝蓋抬起可見）
		# snap_up 處理實際的台階物理攀爬
		
		# ★ 播放動畫
		var is_new_anim = (anim_player.assigned_animation != stair_anim) or not anim_player.is_playing()
		if is_new_anim:
			anim_player.play(stair_anim, 0.2)
			if verbose_debug: print(">>> [StairAnim] Play: %s" % stair_anim)
			
			# ★★★ 相位匹配 (Phase Matching) ★★★
			# 決定動畫應該從 0.0s 還是從一半 (0.5 * length) 開始
			if _skeleton:
				var r_bone = _skeleton.find_bone("RightFoot")
				var l_bone = _skeleton.find_bone("LeftFoot")
				if r_bone >= 0 and l_bone >= 0 and anim_player.has_animation(stair_anim):
					var right_y = _skeleton.get_bone_global_pose(r_bone).origin.y
					var left_y = _skeleton.get_bone_global_pose(l_bone).origin.y
					var anim_len = anim_player.get_animation(stair_anim).length
					
					var start_time: float = 0.0
					# 如果右腳高於左腳，代表接下來應該踏左腳 (從 50% 時間點開始)
					if right_y > left_y + 0.05:
						start_time = anim_len * 0.5
						if verbose_debug: print(">>> [StairAnim] Phase Match: 右腳較高，從 %.2fs 開始 (左腳步)" % start_time)
					elif left_y > right_y + 0.05:
						start_time = 0.0
						if verbose_debug: print(">>> [StairAnim] Phase Match: 左腳較高，從 %.2fs 開始 (右腳步)" % start_time)
					
					anim_player.seek(start_time, true)
		
		# ★ 動態 speed_scale：玩家實際水平速度 / 動畫內建 root motion 水平速度
		var target_speed_scale := clampf(h_speed / rm_base_speed, 0.3, 3.0) if rm_base_speed > 0.01 else 1.0
		anim_player.speed_scale = lerpf(anim_player.speed_scale, target_speed_scale, delta * 8.0)
		
		stair.root_motion_active = true
		stair.blend_weight = lerpf(stair.blend_weight, 1.0, delta * 8.0)
		stair.anim_exit_timer = 0.0
		
		# ★ Debug: 每 30 幀印出狀態
		if Engine.get_frames_drawn() % 30 == 0:
			if verbose_debug: print(">>> [StairAnim] anim=%s scale=%.2f h_speed=%.2f blend=%.2f" % [
				stair_anim, anim_player.speed_scale, h_speed, stair.blend_weight])
	
	elif stair.root_motion_active:
		# ★ 立即停止樓梯動畫，不用 grace timer
		stair.root_motion_active = false
		stair.blend_weight = 0.0
		stair.rm_velocity = Vector3.ZERO
		stair.dir_committed = false
		air.air_time = 0.0
		
		# 停止 anim_player 的樓梯動畫
		anim_player.stop()
		anim_player.speed_scale = 1.0
		
		# 清除 root motion track
		var empty_track = NodePath("")
		if anim_player.root_motion_track != empty_track:
			anim_player.root_motion_track = empty_track
		
		# ★ 恢復 AnimationTree
		if anim_tree:
			_blend_position = Vector2.ZERO
			anim_tree.set("parameters/movement/stand_movement/blend_position", Vector2.ZERO)
			if not anim_tree.active:
				anim_tree.active = true
			var playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
			if playback:
				playback.travel("movement")
		
		# ★ IK 恢復由 _debug_bone_after_ik 根據 stair.on_stairs 自動控制
		
		if verbose_debug: print(">>> [StairAnim] 停止 → 恢復 AnimationTree")
#endregion

#region ==================== 階梯投影 Debug 可視化 ====================

## ★ F4 切換 Debug 可視化
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			_stair_debug_enabled = not _stair_debug_enabled
			if verbose_debug: print(">>> [StairDebug] 可視化 %s" % ("開啟 ✅" if _stair_debug_enabled else "關閉 ❌"))
			if not _stair_debug_enabled and _stair_debug_imm:
				_stair_debug_imm.clear_surfaces()

## ★ 階梯投影 Debug 繪製（每幀呼叫）
func _draw_stair_debug() -> void:
	if not _stair_debug_enabled or not _stair_debug_imm:
		return
	
	_stair_debug_imm.clear_surfaces()
	
	# ========== 線段 ==========
	_stair_debug_imm.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var base = stair.base_pos if stair.params_valid else global_position
	var dir3 = Vector3(stair.dir_xz.x, 0, stair.dir_xz.y) if stair.params_valid else Vector3.FORWARD
	var step_h = stair.step_height_measured if stair.step_height_measured > 0.01 else 0.2
	var step_d = stair.step_depth if stair.step_depth > 0.01 else 0.3
	var cross = dir3.cross(Vector3.UP).normalized() * 0.3 # 階梯寬度方向
	
	# --- 1. 基準點十字標記（品紅色）---
	var mk_c = Color(1, 0, 1, 1) # 品紅
	_debug_line(base + Vector3.LEFT * 0.15, base + Vector3.RIGHT * 0.15, mk_c)
	_debug_line(base + Vector3.FORWARD * 0.15, base + Vector3.BACK * 0.15, mk_c)
	_debug_line(base + Vector3.UP * 0.3, base + Vector3.DOWN * 0.05, mk_c)
	
	# --- 2. 階梯方向箭頭（青色）---
	var arrow_c = Color(0, 1, 1, 1) # 青色
	var arrow_end = base + dir3 * 1.5 + Vector3.UP * 0.05
	_debug_line(base + Vector3.UP * 0.05, arrow_end, arrow_c)
	# 箭頭頭部
	var arrow_right = dir3.cross(Vector3.UP).normalized() * 0.15
	_debug_line(arrow_end, arrow_end - dir3 * 0.2 + arrow_right, arrow_c)
	_debug_line(arrow_end, arrow_end - dir3 * 0.2 - arrow_right, arrow_c)
	
	# --- 3. 台階網格（黃色）— 顯示分析式計算的每階表面 ---
	var grid_c = Color(1, 1, 0, 0.6) # 黃色半透明
	var n_steps = 8 # 前後各畫 n 階
	for i in range(-2, n_steps):
		var step_base_xz = base + dir3 * (i * step_d)
		var step_y = base.y + i * step_h
		var p = Vector3(step_base_xz.x, step_y, step_base_xz.z)
		# 水平線（台階表面寬度）
		_debug_line(p - cross, p + cross, grid_c)
		# 台階深度線（連接水平線端點到下一階）
		var p_next = Vector3(step_base_xz.x + dir3.x * step_d, step_y, step_base_xz.z + dir3.z * step_d)
		_debug_line(p - cross, p_next - cross, Color(1, 1, 0, 0.3))
		_debug_line(p + cross, p_next + cross, Color(1, 1, 0, 0.3))
		# 垂直線（台階高度差）
		var rise_end = Vector3(p_next.x, step_y + step_h, p_next.z)
		_debug_line(p_next - cross, rise_end - cross, Color(1, 0.5, 0, 0.5))
		_debug_line(p_next + cross, rise_end + cross, Color(1, 0.5, 0, 0.5))
	
	# --- 4. 右腳鎖定標記 ---
	if _right_foot_locked:
		var rp = Vector3(_smoothed_right_ray_xz.x, _locked_right_step_y, _smoothed_right_ray_xz.y)
		var lk_c = Color(0, 1, 0, 1) # 綠色 = 鎖定中
		# 十字 + 上下柱
		_debug_line(rp + Vector3.LEFT * 0.1, rp + Vector3.RIGHT * 0.1, lk_c)
		_debug_line(rp + Vector3(0, 0, -0.1), rp + Vector3(0, 0, 0.1), lk_c)
		_debug_line(rp, rp + Vector3.UP * 0.2, lk_c)
		# IK target（白色點標記）
		var ik_r = _smoothed_right_target if _smoothed_right_target != Vector3.ZERO else rp + Vector3.UP * FOOT_HEIGHT_OFFSET
		_debug_line(ik_r + Vector3.LEFT * 0.05, ik_r + Vector3.RIGHT * 0.05, Color.WHITE)
		_debug_line(ik_r + Vector3(0, 0, -0.05), ik_r + Vector3(0, 0, 0.05), Color.WHITE)
	else:
		# 右腳未鎖定 — 紅色 X
		if _smoothed_right_ray_xz != Vector2.ZERO:
			var rp = Vector3(_smoothed_right_ray_xz.x, global_position.y, _smoothed_right_ray_xz.y)
			var ul_c = Color(1, 0, 0, 0.5) # 紅色 = 擺動中
			_debug_line(rp + Vector3(-0.08, 0, -0.08), rp + Vector3(0.08, 0, 0.08), ul_c)
			_debug_line(rp + Vector3(0.08, 0, -0.08), rp + Vector3(-0.08, 0, 0.08), ul_c)
	
	# --- 5. 左腳鎖定標記 ---
	if _left_foot_locked:
		var lp = Vector3(_smoothed_left_ray_xz.x, _locked_left_step_y, _smoothed_left_ray_xz.y)
		var lk_c = Color(0, 1, 0, 1)
		_debug_line(lp + Vector3.LEFT * 0.1, lp + Vector3.RIGHT * 0.1, lk_c)
		_debug_line(lp + Vector3(0, 0, -0.1), lp + Vector3(0, 0, 0.1), lk_c)
		_debug_line(lp, lp + Vector3.UP * 0.2, lk_c)
		var ik_l = _smoothed_left_target if _smoothed_left_target != Vector3.ZERO else lp + Vector3.UP * FOOT_HEIGHT_OFFSET
		_debug_line(ik_l + Vector3.LEFT * 0.05, ik_l + Vector3.RIGHT * 0.05, Color.WHITE)
		_debug_line(ik_l + Vector3(0, 0, -0.05), ik_l + Vector3(0, 0, 0.05), Color.WHITE)
	else:
		if _smoothed_left_ray_xz != Vector2.ZERO:
			var lp = Vector3(_smoothed_left_ray_xz.x, global_position.y, _smoothed_left_ray_xz.y)
			var ul_c = Color(1, 0, 0, 0.5)
			_debug_line(lp + Vector3(-0.08, 0, -0.08), lp + Vector3(0.08, 0, 0.08), ul_c)
			_debug_line(lp + Vector3(0.08, 0, -0.08), lp + Vector3(-0.08, 0, 0.08), ul_c)
	
	# --- 6. 狀態資訊面板（角色頭頂）---
	if stair.on_stairs:
		var head = global_position + Vector3.UP * 2.0
		var state_c = Color(0, 1, 1, 0.8) if stair.params_valid else Color(1, 0.5, 0, 0.8)
		# 小三角指示「在樓梯上」
		_debug_line(head, head + Vector3.UP * 0.15, state_c)
		_debug_line(head + Vector3.UP * 0.15, head + Vector3(0.1, 0.1, 0), state_c)
		_debug_line(head + Vector3.UP * 0.15, head + Vector3(-0.1, 0.1, 0), state_c)
	
	# --- 7. ShapeCast IK 射線（腳部 raycast 起點 → 向下 → 碰撞點）---
	var ray_c_r = Color(0.3, 1.0, 0.3, 0.8) # 淺綠 = 右腳 ray
	var ray_c_l = Color(1.0, 0.3, 0.3, 0.8) # 淺紅 = 左腳 ray
	var hit_c = Color(1, 1, 1, 1) # 白色 = 碰撞點
	
	if _right_foot_ray:
		var r_origin = _right_foot_ray.global_position
		var r_end = r_origin + Vector3.DOWN * 1.5 # ShapeCast 向下長度
		_debug_line(r_origin, r_end, ray_c_r)
		# 起點小方框
		_debug_line(r_origin + Vector3(-0.03, 0, -0.03), r_origin + Vector3(0.03, 0, 0.03), ray_c_r)
		_debug_line(r_origin + Vector3(0.03, 0, -0.03), r_origin + Vector3(-0.03, 0, 0.03), ray_c_r)
		# 碰撞點
		if _right_foot_ray.is_colliding():
			var rh = _right_foot_ray.get_collision_point(0)
			_debug_line(rh + Vector3.LEFT * 0.06, rh + Vector3.RIGHT * 0.06, hit_c)
			_debug_line(rh + Vector3(0, 0, -0.06), rh + Vector3(0, 0, 0.06), hit_c)
			_debug_line(rh, rh + Vector3.UP * 0.08, hit_c)
	
	if _left_foot_ray:
		var l_origin = _left_foot_ray.global_position
		var l_end = l_origin + Vector3.DOWN * 1.5
		_debug_line(l_origin, l_end, ray_c_l)
		_debug_line(l_origin + Vector3(-0.03, 0, -0.03), l_origin + Vector3(0.03, 0, 0.03), ray_c_l)
		_debug_line(l_origin + Vector3(0.03, 0, -0.03), l_origin + Vector3(-0.03, 0, 0.03), ray_c_l)
		if _left_foot_ray.is_colliding():
			var lh = _left_foot_ray.get_collision_point(0)
			_debug_line(lh + Vector3.LEFT * 0.06, lh + Vector3.RIGHT * 0.06, hit_c)
			_debug_line(lh + Vector3(0, 0, -0.06), lh + Vector3(0, 0, 0.06), hit_c)
			_debug_line(lh, lh + Vector3.UP * 0.08, hit_c)
	
	# --- 8. IK Target 實際位置（白色 ⊕ 標記）---
	var ik_tc = Color(1, 0.9, 0.3, 1.0) # 金色
	if _smoothed_right_target != Vector3.ZERO:
		var rt = _smoothed_right_target
		_debug_line(rt + Vector3.LEFT * 0.04, rt + Vector3.RIGHT * 0.04, ik_tc)
		_debug_line(rt + Vector3(0, 0, -0.04), rt + Vector3(0, 0, 0.04), ik_tc)
		_debug_line(rt, rt + Vector3.UP * 0.06, ik_tc)
	if _smoothed_left_target != Vector3.ZERO:
		var lt = _smoothed_left_target
		_debug_line(lt + Vector3.LEFT * 0.04, lt + Vector3.RIGHT * 0.04, ik_tc)
		_debug_line(lt + Vector3(0, 0, -0.04), lt + Vector3(0, 0, 0.04), ik_tc)
		_debug_line(lt, lt + Vector3.UP * 0.06, ik_tc)
	
	_stair_debug_imm.surface_end()

## 輔助：ImmediateMesh 畫單條線
func _debug_line(from: Vector3, to: Vector3, color: Color) -> void:
	_stair_debug_imm.surface_set_color(color)
	_stair_debug_imm.surface_add_vertex(from)
	_stair_debug_imm.surface_set_color(color)
	_stair_debug_imm.surface_add_vertex(to)

#endregion
