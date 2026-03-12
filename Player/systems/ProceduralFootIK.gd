extends Node3D
class_name ProceduralFootIK

## ProceduralFootIK - 程序式腳步 IK 控制器
## 整合 StepPlanner + FootTrajectory 驅動 IK 目標點
##
## ★ 支撐腳 Y 鎖定：踏步時鎖定對側腳的 Y 軸（防止滑動）
## ★ 膝蓋驅動 IK phasing：抬腳階段讓動畫主導，落腳階段 IK 貼地

signal foot_step_started(foot: String)
signal foot_step_completed(foot: String)

@export_group("IK Targets")
@export var left_target: Marker3D
@export var right_target: Marker3D
@export var skeleton: Skeleton3D

@export_group("Step Settings")
@export var step_duration: float = 0.25 # 單步時間
@export var step_height_clearance: float = 0.1 # 抬腳額外高度
@export var min_step_trigger_distance: float = 0.4 # 觸發踏步的最小距離

@export_group("Knee-Driven IK Phasing")
## 抬腳階段（0.0 ~ lift_phase_end）的 IK influence（低=動畫主導=膝蓋帶動）
@export var lift_phase_influence: float = 0.1
## 落腳階段（plant_phase_start ~ 1.0）的 IK influence（高=IK 精準貼地）
@export var plant_phase_influence: float = 1.0
## 抬腳階段結束的 progress 位置
@export var lift_phase_end: float = 0.4
## 落腳階段開始的 progress 位置
@export var plant_phase_start: float = 0.7

@export_group("Debug")
@export var debug_print: bool = true
@export var debug_draw_trajectory: bool = false

# 骨骼索引
var _left_foot_idx: int = -1
var _right_foot_idx: int = -1

# 當前軌跡
var _left_trajectory: FootTrajectory = null
var _right_trajectory: FootTrajectory = null

# 狀態
var _is_left_stepping: bool = false
var _is_right_stepping: bool = false

# 參照
var _player: CharacterBody3D
var _step_planner: StepPlanner
var _simple_foot_ik: SimpleFootIK


func _ready() -> void:
	# 尋找 Player
	_player = get_parent() as CharacterBody3D
	if not _player:
		_player = get_tree().get_first_node_in_group("Player") as CharacterBody3D
	
	# 尋找 StepPlanner
	if _player:
		_step_planner = _player.get_node_or_null("StepPlanner") as StepPlanner
		if _step_planner:
			_step_planner.step_detected.connect(_on_step_detected)
			print("[ProceduralFootIK] Connected to StepPlanner")
	
	# 尋找骨骼索引
	if skeleton:
		_left_foot_idx = skeleton.find_bone("LeftFoot")
		if _left_foot_idx == -1:
			_left_foot_idx = skeleton.find_bone("mixamorig1_LeftFoot")
		
		_right_foot_idx = skeleton.find_bone("RightFoot")
		if _right_foot_idx == -1:
			_right_foot_idx = skeleton.find_bone("mixamorig1_RightFoot")
		
		print("[ProceduralFootIK] Left foot bone: %d, Right foot bone: %d" % [_left_foot_idx, _right_foot_idx])
	
	# 尋找 SimpleFootIK (用於鎖定/解鎖)
	if _player:
		_simple_foot_ik = _player.get_node_or_null("SimpleFootIK") as SimpleFootIK
		if _simple_foot_ik:
			print("[ProceduralFootIK] Connected to SimpleFootIK")


func _physics_process(delta: float) -> void:
	# 更新左腳軌跡
	if _left_trajectory and _left_trajectory.is_active:
		var pos = _left_trajectory.update(delta)
		if left_target:
			left_target.global_position = pos
		
		# ★ 膝蓋驅動：根據 progress 調整左腳 IK influence
		_apply_step_influence("left", _left_trajectory.progress)
		
		if _left_trajectory.is_complete:
			_complete_step("left")
	
	# 更新右腳軌跡
	if _right_trajectory and _right_trajectory.is_active:
		var pos = _right_trajectory.update(delta)
		if right_target:
			right_target.global_position = pos
		
		# ★ 膝蓋驅動：根據 progress 調整右腳 IK influence
		_apply_step_influence("right", _right_trajectory.progress)
		
		if _right_trajectory.is_complete:
			_complete_step("right")


## 踏步完成時的統一清理
func _complete_step(foot: String) -> void:
	if foot == "left":
		_is_left_stepping = false
	else:
		_is_right_stepping = false
	
	# 解鎖踏步腳（完全鎖定）
	_unlock_foot(foot)
	
	# ★ 解鎖支撐腳的 Y 軸
	var support_foot = "right" if foot == "left" else "left"
	_unlock_support_foot(support_foot)
	
	# ★ 清除踏步腳的 influence 覆蓋，恢復全局值
	_clear_influence_override(foot)
	
	if debug_print:
		print("[ProceduralFootIK] %s腳落地完成" % ("左" if foot == "left" else "右"))
	
	foot_step_completed.emit(foot)


## 當 StepPlanner 偵測到台階時的回調
func _on_step_detected(foot: String, target_pos: Vector3, step_height: float) -> void:
	# 避免同時踏兩隻腳
	if _is_left_stepping and _is_right_stepping:
		return
	
	# 計算落腳點
	if foot == "left" and not _is_left_stepping:
		_start_left_step(target_pos, step_height)
	elif foot == "right" and not _is_right_stepping:
		_start_right_step(target_pos, step_height)


## 開始左腳踏步
func _start_left_step(target_pos: Vector3, _step_height: float) -> void:
	if not left_target:
		return
	
	var start_pos = left_target.global_position
	
	# 創建軌跡
	_left_trajectory = FootTrajectory.new()
	_left_trajectory.duration = step_duration
	_left_trajectory.setup(start_pos, target_pos, step_height_clearance)
	
	_is_left_stepping = true
	_lock_foot("left")
	
	# ★ 鎖定支撐腳（右腳）的 Y 軸
	_lock_support_foot("right")
	
	if debug_print:
		print("[ProceduralFootIK] 左腳開始踏步: %s → %s (支撐腳=右腳 Y鎖定)" % [start_pos, target_pos])
	
	foot_step_started.emit("left")


## 開始右腳踏步
func _start_right_step(target_pos: Vector3, _step_height: float) -> void:
	if not right_target:
		return
	
	var start_pos = right_target.global_position
	
	# 創建軌跡
	_right_trajectory = FootTrajectory.new()
	_right_trajectory.duration = step_duration
	_right_trajectory.setup(start_pos, target_pos, step_height_clearance)
	
	_is_right_stepping = true
	_lock_foot("right")
	
	# ★ 鎖定支撐腳（左腳）的 Y 軸
	_lock_support_foot("left")
	
	if debug_print:
		print("[ProceduralFootIK] 右腳開始踏步: %s → %s (支撐腳=左腳 Y鎖定)" % [start_pos, target_pos])
	
	foot_step_started.emit("right")


# =============================================
# ★★★ 膝蓋驅動 IK Phasing ★★★
# =============================================

## 根據軌跡進度計算 IK influence
## 前半段（lift）：低 influence → 動畫的膝蓋帶動
## 後半段（plant）：高 influence → IK 精準貼地
func _calculate_step_influence(progress: float) -> float:
	if progress < lift_phase_end:
		# 抬腳階段：幾乎純動畫
		return lift_phase_influence
	elif progress < plant_phase_start:
		# 過渡階段：從 lift → plant 線性插值
		var t = (progress - lift_phase_end) / (plant_phase_start - lift_phase_end)
		return lerp(lift_phase_influence, plant_phase_influence, t)
	else:
		# 落腳階段：IK 精準貼地
		return plant_phase_influence


## 應用 per-foot IK influence 到 SimpleFootIK
func _apply_step_influence(foot: String, progress: float) -> void:
	if not _simple_foot_ik:
		return
	
	var influence = _calculate_step_influence(progress)
	
	if foot == "left":
		_simple_foot_ik.set_left_influence(influence)
	else:
		_simple_foot_ik.set_right_influence(influence)


## 清除 per-foot influence 覆蓋
func _clear_influence_override(foot: String) -> void:
	if not _simple_foot_ik:
		return
	if foot == "left":
		_simple_foot_ik.clear_left_influence_override()
	else:
		_simple_foot_ik.clear_right_influence_override()


# =============================================
# ★★★ 支撐腳 Y 鎖定 ★★★
# =============================================

## 鎖定支撐腳（完全鎖定 XYZ，腳釘在原地）
## ★ 記錄世界座標 + 強制 IK influence = 1.0，防止動畫渲透
func _lock_support_foot(foot: String) -> void:
	if not _simple_foot_ik:
		return
	if foot == "left":
		# 記錄左腳目前的世界座標
		if left_target:
			_simple_foot_ik._locked_left_world_pos = left_target.global_position
		_simple_foot_ik.left_foot_locked = true
		# ★ 強制支撐腳 IK = 1.0，完全壓過動畫
		_simple_foot_ik.set_left_influence(1.0)
		if debug_print:
			print("[ProceduralFootIK] 支撐腳(左)鎖定在 %s, IK=1.0" % left_target.global_position if left_target else "N/A")
	else:
		# 記錄右腳目前的世界座標
		if right_target:
			_simple_foot_ik._locked_right_world_pos = right_target.global_position
		_simple_foot_ik.right_foot_locked = true
		# ★ 強制支撐腳 IK = 1.0，完全壓過動畫
		_simple_foot_ik.set_right_influence(1.0)
		if debug_print:
			print("[ProceduralFootIK] 支撐腳(右)鎖定在 %s, IK=1.0" % right_target.global_position if right_target else "N/A")


## 解鎖支撐腳（還原 IK influence）
func _unlock_support_foot(foot: String) -> void:
	if not _simple_foot_ik:
		return
	if foot == "left":
		_simple_foot_ik.left_foot_locked = false
		_simple_foot_ik.clear_left_influence_override()
	else:
		_simple_foot_ik.right_foot_locked = false
		_simple_foot_ik.clear_right_influence_override()


# =============================================
# 原有的完全鎖定 API（踏步腳用）
# =============================================

## 鎖定 SimpleFootIK 的腳（完全鎖定，軌跡接管）
func _lock_foot(foot: String) -> void:
	if not _simple_foot_ik:
		return
	if foot == "left":
		_simple_foot_ik.left_foot_locked = true
	else:
		_simple_foot_ik.right_foot_locked = true


## 解鎖 SimpleFootIK 的腳
func _unlock_foot(foot: String) -> void:
	if not _simple_foot_ik:
		return
	if foot == "left":
		_simple_foot_ik.left_foot_locked = false
	else:
		_simple_foot_ik.right_foot_locked = false


## 手動觸發踏步 (可供外部呼叫)
func trigger_step(foot: String, target_pos: Vector3) -> void:
	var step_height = target_pos.y - _player.global_position.y if _player else 0.0
	_on_step_detected(foot, target_pos, step_height)


## 獲取當前腳的世界位置
func get_foot_world_position(foot: String) -> Vector3:
	if not skeleton:
		return Vector3.ZERO
	
	var bone_idx = _left_foot_idx if foot == "left" else _right_foot_idx
	if bone_idx < 0:
		return Vector3.ZERO
	
	var pose = skeleton.get_bone_global_pose(bone_idx)
	return skeleton.global_transform * pose.origin


## 是否有腳正在踏步中
func is_stepping() -> bool:
	return _is_left_stepping or _is_right_stepping


## 獲取當前踏步的腳
func get_stepping_foot() -> String:
	if _is_left_stepping:
		return "left"
	elif _is_right_stepping:
		return "right"
	return ""
