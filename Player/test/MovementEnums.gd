class_name MovementEnums
## 集中定義移動系統相關枚舉
## 用於取代分散的 bool 旗標，確保互斥狀態不會衝突

## 主要移動狀態（互斥）
## 取代: _is_landing, _is_jumping, _is_falling, _is_stopping
enum MotionState {
	IDLE, ## 站定不動（地面上，無輸入）
	MOVING, ## 地面移動中（有方向輸入）
	JUMPING, ## 跳躍中（包含上升 + 跳躍後下落）
	FALLING, ## 非跳躍的自由落體（走下邊緣等）
	LANDING, ## 落地恢復動畫
	STOPPING, ## 減速停止動畫（Run To Stop）
}

## 移動節奏（互斥）
## 取代: _is_crouching + is_sprinting 局部變數
enum Gait {
	WALK, ## 走路（預設）
	SPRINT, ## 衝刺
	CROUCH, ## 蹲走
}
