extends Resource
class_name MovementData
## 移動參數資源類
## 可在 Inspector 中即時調整，也可以存為 .tres 檔案熱切換
## 取代 SimpleCapsuleMove.gd 中分散的 @export 變數

@export_group("Speed")
@export var walk_speed: float = 3.5 ## 走路速度
@export var sprint_speed: float = 6.0 ## 衝刺速度
@export var crouch_speed: float = 1.8 ## 蹲走速度

@export_group("Acceleration")
@export var ground_acceleration: float = 12.0 ## 地面加速度
@export var ground_deceleration: float = 15.0 ## 地面減速度
@export var air_acceleration: float = 3.0 ## 空中加速度
@export var air_deceleration: float = 2.0 ## 空中減速度
@export var use_exponential_curve: bool = true ## 使用指數曲線（更自然）
@export var use_velocity_curves: bool = false ## 使用自定義速度曲線
@export var acceleration_curve: Curve ## 加速曲線：X=時間(0-1), Y=速度比例(0-1)
@export var deceleration_curve: Curve ## 減速曲線：X=時間(0-1), Y=速度比例(0-1)
@export var curve_duration_accel: float = 0.3 ## 加速曲線持續時間（秒）
@export var curve_duration_decel: float = 0.25 ## 減速曲線持續時間（秒）

@export_group("Jump")
@export var jump_velocity: float = 6.0 ## 初始跳躍速度
@export var gravity: float = 20.0 ## 重力加速度
@export var coyote_time: float = 0.15 ## 土狼時間
@export var jump_buffer_time: float = 0.1 ## 跳躍緩衝時間
@export var jump_hold_force: float = 30.0 ## 跳躍保持力
@export var jump_hold_max_time: float = 0.12 ## 最大跳躍保持時間
@export var variable_jump_height: bool = true ## 可變跳躍高度

@export_group("Turning")
@export var turn_rate: float = 540.0 ## 轉身速度（度/秒）
@export var turn_threshold_angle: float = 60.0 ## 觸發轉身的角度閾值
@export var turn_speed: float = 180.0 ## 轉身速度（度/秒）

@export_group("Body Lean")
@export var body_lean_enabled: bool = true ## 啟用身體傾斜
@export var body_lean_amount: float = 5.0 ## 最大傾斜角度（度）
@export var body_lean_smooth: float = 8.0 ## 傾斜平滑速度
@export var turn_momentum_enabled: bool = true ## 啟用轉向慣性

@export_group("Step Climbing (樓梯)")
@export var step_enabled: bool = true ## 啟用自動踏上台階
@export var max_step_height: float = 0.5 ## 最大可踏上高度（50cm）
@export var step_check_distance: float = 0.5 ## 向前偵測距離
@export var step_smooth_speed: float = 12.0 ## Y 軸平滑速度
