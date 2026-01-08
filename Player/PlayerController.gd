extends CharacterBody3D

# 匯出變數，方便在編輯器中調整
@export_group("Movement Properties (移動屬性)")
@export var speed: float = 5.0             # 基礎移動速度
@export var sprint_speed: float = 10.0      # 衝刺速度
@export var acceleration: float = 10.0     # 加速度 (讓移動有慣性)
@export var decelaration: float = 10.0     # 減速度
@export var jump_velocity: float = 4.5     # 跳躍力道
@export var mouse_sensitivity: float = 0.003 # 滑鼠靈敏度
@export var min_pitch: float = -90.0       # 最小俯仰角 (向上看)
@export var max_pitch: float = 90.0        # 最大俯仰角 (向下看)

@export_group("Nodes (節點參照)")
@export var camera_mount: Node3D # 負責垂直旋轉的節點 (通常是 Head 或 CameraMount)

# 從專案設定中獲取重力值
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	# 隱藏並鎖定滑鼠游標
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# 處理滑鼠旋轉
	if event is InputEventMouseMotion:
		# 水平旋轉 (旋轉角色身體)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# 垂直旋轉 (旋轉相機/頭部)
		if camera_mount:
			camera_mount.rotate_x(-event.relative.y * mouse_sensitivity)
			# 限制垂直旋轉角度
			camera_mount.rotation.x = clamp(camera_mount.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

func _physics_process(delta: float) -> void:
	# 處理重力
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 處理跳躍
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
	
	# 處理衝刺按下狀態 (這裡暫時使用 Shift 鍵，若有自定義 InputMap 可更換)
	var is_sprinting = Input.is_key_pressed(KEY_SHIFT)
	var current_speed = sprint_speed if is_sprinting else speed

	# 獲取輸入方向並處理移動
	# 建議在專案設定的 Input Map 中定義清晰的動作名稱 (如 move_forward, move_right 等)
	# 這裡先使用預設的 ui_left, ui_right, ui_up, ui_down 相容 WASD 與方向鍵
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		# 加速到目標速度
		velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
	else:
		# 減速停止
		velocity.x = move_toward(velocity.x, 0, decelaration * delta)
		velocity.z = move_toward(velocity.z, 0, decelaration * delta)

	move_and_slide()
