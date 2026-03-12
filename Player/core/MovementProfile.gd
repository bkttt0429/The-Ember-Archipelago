extends Resource
class_name MovementProfile
## 數據驅動的移動參數配置
## 取代硬編碼在 InputSystem / MovementSystem 中的速度與加速度值
## 可在 Inspector 裡直接調整，並支持為不同狀態/角色使用不同的 Profile

@export_group("速度 (Speed)")
## 行走速度
@export var walk_speed: float = 5.0
## 跑步速度
@export var run_speed: float = 8.0
## 衝刺速度
@export var sprint_speed: float = 12.0
## 蹲伏速度
@export var crouch_speed: float = 2.5
## 游泳速度
@export var swim_speed: float = 3.5

@export_group("加速度 (Acceleration)")
## 移動加速度
@export var acceleration: float = 14.0
## 停止減速度
@export var deceleration: float = 18.0
## 反向移動加速度 (掉頭時更快減速)
@export var reverse_acceleration: float = 26.0

@export_group("旋轉 (Rotation)")
## 角色旋轉速率
@export var rotation_rate: float = 10.0

## 根據移動模式獲取目標速度
func get_speed_for_mode(mode: String) -> float:
	match mode:
		"sprint": return sprint_speed
		"crouch": return crouch_speed
		"swim": return swim_speed
		"run": return run_speed
		"walk", _: return walk_speed
