extends RefCounted
class_name FootTrajectory

## FootTrajectory - 計算腳從起點到落腳點的弧線軌跡
## 使用 Bezier 曲線模擬自然的腳步抬起-落下動作

# 軌跡參數
var start_pos: Vector3
var end_pos: Vector3
var control_point: Vector3 # Bezier 控制點 (決定弧線高度)
var step_height: float
var progress: float = 0.0 # 0.0 = 起點, 1.0 = 終點

# 速度控制
var duration: float = 0.3 # 單步時間 (秒)
var _elapsed: float = 0.0

# 狀態
var is_active: bool = false
var is_complete: bool = false


## 初始化軌跡
## @param from: 起始位置 (當前腳位置)
## @param to: 目標位置 (落腳點)
## @param height_clearance: 最高點離地高度 (額外抬起高度)
func setup(from: Vector3, to: Vector3, height_clearance: float = 0.15) -> void:
	start_pos = from
	end_pos = to
	
	# 計算需要跨越的高度差
	step_height = max(to.y - from.y, 0.0)
	
	# 計算 Bezier 控制點 (弧線最高點)
	# 位於起點和終點的中間，高度為較高點 + clearance
	var mid_xz = (from + to) / 2.0
	var peak_height = max(from.y, to.y) + step_height + height_clearance
	control_point = Vector3(mid_xz.x, peak_height, mid_xz.z)
	
	# 重置狀態
	progress = 0.0
	_elapsed = 0.0
	is_active = true
	is_complete = false


## 更新軌跡進度，返回當前腳的位置
func update(delta: float) -> Vector3:
	if not is_active or is_complete:
		return end_pos
	
	_elapsed += delta
	progress = clamp(_elapsed / duration, 0.0, 1.0)
	
	if progress >= 1.0:
		is_complete = true
		is_active = false
		return end_pos
	
	# 計算 Bezier 曲線上的點
	return get_position_at(progress)


## 取得軌跡上指定進度的位置 (Quadratic Bezier)
## t: 0.0 = 起點, 0.5 = 最高點附近, 1.0 = 終點
func get_position_at(t: float) -> Vector3:
	# Quadratic Bezier: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
	var one_minus_t = 1.0 - t
	var p0 = start_pos * (one_minus_t * one_minus_t)
	var p1 = control_point * (2.0 * one_minus_t * t)
	var p2 = end_pos * (t * t)
	return p0 + p1 + p2


## 取得軌跡上指定進度的速度向量 (Bezier 導數)
func get_velocity_at(t: float) -> Vector3:
	# Quadratic Bezier derivative: B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
	var one_minus_t = 1.0 - t
	var v0 = (control_point - start_pos) * (2.0 * one_minus_t)
	var v1 = (end_pos - control_point) * (2.0 * t)
	return v0 + v1


## 使用 Ease 函數調整進度，讓動作更自然
## 開始慢、中間快、結束慢
func ease_in_out(t: float) -> float:
	if t < 0.5:
		return 2.0 * t * t
	else:
		return 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0


## 取得緩動後的位置 (更自然的動作)
func get_eased_position_at(t: float) -> Vector3:
	var eased_t = ease_in_out(t)
	return get_position_at(eased_t)


## 強制完成軌跡
func complete() -> void:
	progress = 1.0
	is_complete = true
	is_active = false


## 取消軌跡
func cancel() -> void:
	is_active = false
	is_complete = false


## Debug: 取得軌跡的採樣點 (用於視覺化)
func get_sample_points(sample_count: int = 10) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(sample_count + 1):
		var t = float(i) / float(sample_count)
		points.append(get_position_at(t))
	return points


## 計算軌跡總長度 (近似值)
func get_arc_length(sample_count: int = 20) -> float:
	var length = 0.0
	var prev = start_pos
	for i in range(1, sample_count + 1):
		var t = float(i) / float(sample_count)
		var current = get_position_at(t)
		length += prev.distance_to(current)
		prev = current
	return length
