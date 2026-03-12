@tool
class_name ShipWakeTrail
extends MeshInstance3D

## ShipWakeTrail - 動態生成船隻尾跡（Ribbon Mesh）
## 透過追蹤船隻路徑，動態生成一個帶狀網格，並套用自訂 Shader 產生綿延的泡沫尾跡。

@export var is_active: bool = true

@export_group("Trail Settings")
## 尾跡的總生命週期（秒），超過此時間的頂點會被移除
@export var trail_lifetime: float = 8.0
## 尾跡的寬度（公尺）
@export var trail_width: float = 3.0
## 尾跡隨時間擴散放大倍率（模擬 Kelvin Wake 的 V 型擴散）
@export var trail_expansion: float = 0.5
## 產生新頂點的最小距離（公尺），避免生成過多頂點
@export var min_vertex_distance: float = 0.5
## 尾跡材質
@export var trail_material: ShaderMaterial

class TrailPoint:
	var position: Vector3
	var normal: Vector3
	var spawn_time: float
	
	func _init(p_pos: Vector3, p_normal: Vector3, p_time: float):
		position = p_pos
		normal = p_normal
		spawn_time = p_time

var _points: Array[TrailPoint] = []
var _immediate_mesh: ImmediateMesh
var _time_passed: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	mesh = _immediate_mesh
	
	if trail_material:
		material_override = trail_material
	else:
		push_warning("ShipWakeTrail 需要一個 trail_material (ShaderMaterial) 才能正確顯示。")
		
	# 由於我們動態生成網格，將頂層 node 從世界座標系獨立出來以避免繼承船舶的旋轉
	top_level = true
	global_position = Vector3.ZERO
	global_rotation = Vector3.ZERO

func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not is_active:
		# 在編輯器中且未啟用時清空
		_immediate_mesh.clear_surfaces()
		return
		
	_time_passed += delta
	
	var parent = get_parent() as Node3D
	if not parent:
		return
		
	var current_pos = parent.global_position
	
	# 如果距離超過閾值，添加新點
	if _points.is_empty() or current_pos.distance_to(_last_pos) >= min_vertex_distance:
		# 使用父節點向上的方向作為法線（確保尾跡與水面或船體姿態一致）
		var _parent_up = parent.global_transform.basis.y.normalized()
		# 如果是平鋪在海面上，通常強制為 Vector3.UP
		var use_normal = Vector3.UP
		
		_points.push_front(TrailPoint.new(current_pos, use_normal, _time_passed))
		_last_pos = current_pos
		
	# 移除過期的軌跡點
	while _points.size() > 0 and (_time_passed - _points.back().spawn_time) > trail_lifetime:
		_points.pop_back()
		
	_update_mesh()

func _update_mesh() -> void:
	_immediate_mesh.clear_surfaces()
	
	# 至少需要兩個點才能組成多邊形
	if _points.size() < 2:
		return
	
	# === Catmull-Rom 樣條插值 ===
	# 在每兩個記錄點之間插入多個子頂點，使轉彎處變成絲滑的圓弧曲線
	var subdivisions: int = 4 # 每段之間插入幾個子頂點
	var smooth_points: Array = [] # [{pos, normal, age}]
	
	for i in range(_points.size()):
		if i == _points.size() - 1:
			# 最後一個點直接加入
			var age_val = (_time_passed - _points[i].spawn_time) / trail_lifetime
			smooth_points.append({"pos": _points[i].position, "normal": _points[i].normal, "age": age_val})
			break
		
		# Catmull-Rom 需要 4 個控制點: p0, p1, p2, p3
		var p0 = _points[max(i - 1, 0)].position
		var p1 = _points[i].position
		var p2 = _points[i + 1].position
		var p3 = _points[min(i + 2, _points.size() - 1)].position
		
		var age1 = (_time_passed - _points[i].spawn_time) / trail_lifetime
		var age2 = (_time_passed - _points[i + 1].spawn_time) / trail_lifetime
		var n1 = _points[i].normal
		var n2 = _points[i + 1].normal
		
		for s in range(subdivisions):
			var t = float(s) / float(subdivisions)
			# Catmull-Rom 插值公式
			var pos = 0.5 * (
				2.0 * p1 +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t
			)
			var age_interp = lerp(age1, age2, t)
			var normal_interp = n1.lerp(n2, t).normalized()
			smooth_points.append({"pos": pos, "normal": normal_interp, "age": age_interp})
	
	if smooth_points.size() < 2:
		return
	
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	var total_length = 0.0
	for i in range(smooth_points.size()):
		var sp = smooth_points[i]
		var pos: Vector3 = sp["pos"]
		var nrm: Vector3 = sp["normal"]
		var age: float = sp["age"]
		
		# 計算前進方向
		var forward = Vector3.FORWARD
		if i == 0 and smooth_points.size() > 1:
			forward = (smooth_points[0]["pos"] - smooth_points[1]["pos"]).normalized()
		elif i == smooth_points.size() - 1:
			forward = (smooth_points[i - 1]["pos"] - smooth_points[i]["pos"]).normalized()
		elif i > 0 and i < smooth_points.size() - 1:
			forward = (smooth_points[i - 1]["pos"] - smooth_points[i + 1]["pos"]).normalized()
		
		# 計算左右向量
		var right = forward.cross(nrm).normalized()
		if right.length_squared() < 0.01:
			right = Vector3.RIGHT
		
		var current_width = trail_width * (1.0 + age * trail_expansion)
		var half_width = current_width * 0.5
		var left_pos = pos - right * half_width
		var right_pos = pos + right * half_width
		
		# 累積長度
		if i > 0:
			total_length += pos.distance_to(smooth_points[i - 1]["pos"])
		
		var alpha = 1.0 - ease_out_quad(age)
		var vertex_color = Color(1.0, 1.0, 1.0, alpha)
		
		# 左側頂點
		_immediate_mesh.surface_set_normal(nrm)
		_immediate_mesh.surface_set_color(vertex_color)
		_immediate_mesh.surface_set_uv(Vector2(0.0, total_length))
		_immediate_mesh.surface_add_vertex(left_pos)
		
		# 右側頂點
		_immediate_mesh.surface_set_normal(nrm)
		_immediate_mesh.surface_set_color(vertex_color)
		_immediate_mesh.surface_set_uv(Vector2(1.0, total_length))
		_immediate_mesh.surface_add_vertex(right_pos)
		
	_immediate_mesh.surface_end()

# Helper easing function
func ease_out_quad(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)

func clear_trail() -> void:
	_points.clear()
	_immediate_mesh.clear_surfaces()
