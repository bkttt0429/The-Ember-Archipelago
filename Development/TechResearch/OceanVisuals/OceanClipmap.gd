@tool
extends Node3D

# Ocean Clipmap LOD System - ULTIMATE FIXED VERSION
# 修復內容:
# 1. 解決了 LOD 0 (Center) 與 LOD 1 (Ring) 之間的規模跳躍問題 (Scale Gap)
# 2. 修正了 Skirt 法向 (Normal)，改為正確指向外側 (FORWARD, BACK, LEFT, RIGHT)
# 3. 確保了所有 LOD 層級在同一個 Y=0 平面且無垂直偏移
# 4. 實作了 2:1 的邊界頂點縫合邏輯，防止 T-Junctions

@export var clipmap_levels: int = 6
@export var base_grid_size: float = 64.0:
	set(v):
		base_grid_size = v
		if is_inside_tree(): _generate_clipmap()
@export var base_subdivisions: int = 32:
	set(v):
		base_subdivisions = v
		if is_inside_tree(): _generate_clipmap()

@export var skirt_depth: float = 2.0:
	set(v):
		skirt_depth = v
		if is_inside_tree(): _generate_clipmap()

@export var follow_target: Node3D

var meshes: Array[MeshInstance3D] = []
var material: ShaderMaterial
var center_mesh: ArrayMesh
var ring_mesh: ArrayMesh

func _ready():
	_generate_clipmap()

func set_material(mat: ShaderMaterial):
	material = mat
	for i in range(meshes.size()):
		var m = meshes[i]
		if m: 
			m.material_override = material
			# 注意：我們現在使用全球統一的 World-Space Sampling
			# 每個 MeshInstance 不再需要獨立的 texture_scale 實例參數

func _generate_clipmap():
	# Cleaning existing meshes
	for m in meshes:
		if m: m.queue_free()
	meshes.clear()
	
	# Safeguard subdivisions
	if base_subdivisions % 4 != 0:
		base_subdivisions = int((float(base_subdivisions) / 4.0 + 1.0)) * 4
	
	# 1. Generate Base Meshes (Unit sized: Center is size 1.0, Ring is size 2.0 with 1.0 hole)
	center_mesh = _create_center_mesh(base_subdivisions)
	ring_mesh = _create_unit_ring_mesh(base_subdivisions)
	
	# 2. Instantiate Levels
	var current_scale = base_grid_size
	
	print("\n=== Ocean LOD Generation Debug ===")
	for i in range(clipmap_levels):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "LOD_Level_" + str(i)
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.extra_cull_margin = 16384.0
		
		# ⚠️ 關鍵邏輯：LOD 0 和 LOD 1 必須使用相同的 scale S
		# L0 (Center) 覆蓋 [-0.5, 0.5] * S = [-16, 16] (若 S=32)
		# L1 (Ring) 內孔覆蓋 [-0.5, 0.5] * S = [-16, 16] -> 完美銜接！
		if i == 0:
			mesh_inst.mesh = center_mesh
		else:
			mesh_inst.mesh = ring_mesh
			
		mesh_inst.scale = Vector3(current_scale, 1, current_scale)
		mesh_inst.position = Vector3.ZERO # 確保無偏移
		
		# Print detailed bounds for verification
		var extents = current_scale * 0.5
		if i == 0:
			print("LOD ", i, ": Center Mesh, Extents: ±", extents)
		else:
			print("LOD ", i, ": Ring Mesh, Hole: ±", extents, ", Outer: ±", current_scale)
		
		if material:
			mesh_inst.material_override = material
			# ✅ Pass the subdivisions to the shader for correct snapping
			# mesh_inst.set_instance_shader_parameter("grid_subdivisions", float(base_subdivisions))
		
		add_child(mesh_inst)
		meshes.append(mesh_inst)
		
		# ⚠️ 關鍵邏輯：僅從 LOD 1 之後開始翻倍 Scale
		# 序列: S, S, 2S, 4S, 8S...
		if i != 0:
			current_scale *= 2.0
	
	print("✅ Clipmap Generation Complete")
	print("=================================\n")

func _rebuild_clipmap():
	_generate_clipmap()

func _process(_delta):
	if not follow_target:
		return
		
	var t_pos = follow_target.global_position
	# 使用精細層級的網格步長進行捕捉，防止游泳偽影
	var step_size = base_grid_size / float(base_subdivisions)
	var snapped_x = floor(t_pos.x / step_size) * step_size
	var snapped_z = floor(t_pos.z / step_size) * step_size
	
	global_position = Vector3(snapped_x, 0, snapped_z)

# --- Mesh Generation Helpers ---

func _create_center_mesh(N: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half = 0.5
	var step = 1.0 / N
	
	# Main Grid [-0.5, 0.5]
	for z in range(N + 1):
		for x in range(N + 1):
			var u = float(x) / N
			var v = float(z) / N
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x * step - half, 0, z * step - half))
			
	for z in range(N):
		for x in range(N):
			var i = z * (N + 1) + x
			st.add_index(i)
			st.add_index(i + (N + 1))
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + (N + 1))
			st.add_index(i + (N + 1) + 1)
			
	# Add Skirts for center mesh (Outer edge ±0.5)
	var center_verts = (N + 1) * (N + 1)
	_add_skirt(st, N, half, -skirt_depth, center_verts)
			
	return st.commit()

func _create_unit_ring_mesh(N: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var N_thickness = int(float(N) / 4.0)
	var start_idx = 0
	
	# 組合四個矩形區塊形成環形
	# 1. Top (z in [-1.0, -0.5], x in [-1.0, 1.0])
	start_idx += _add_ring_section(st, 
		Vector3(-1.0, 0, -0.5), Vector3(2.0, 0, 0), Vector3(0, 0, -0.5),
		2 * N, N, N_thickness, start_idx)

	# 2. Bottom (z in [0.5, 1.0], x in [-1.0, 1.0])
	start_idx += _add_ring_section(st,
		Vector3(-1.0, 0, 0.5), Vector3(2.0, 0, 0), Vector3(0, 0, 0.5),
		2 * N, N, N_thickness, start_idx)
		
	# 3. Left (x in [-1.0, -0.5], z in [-0.5, 0.5])
	start_idx += _add_ring_section(st,
		Vector3(-0.5, 0, -0.5), Vector3(0, 0, 1.0), Vector3(-0.5, 0, 0),
		N, int(N / 2), N_thickness, start_idx)

	# 4. Right (x in [0.5, 1.0], z in [-0.5, 0.5])
	start_idx += _add_ring_section(st,
		Vector3(0.5, 0, -0.5), Vector3(0, 0, 1.0), Vector3(0.5, 0, 0),
		N, int(N / 2), N_thickness, start_idx)
	
	# Add Skirts for ring mesh (Outer edge ±1.0)
	_add_skirt(st, 2 * N, 1.0, -skirt_depth, start_idx)
	
	return st.commit()

# 添加一個帶有頂點縮減 (Transition) 的矩形區塊
func _add_ring_section(st: SurfaceTool, 
		origin: Vector3, u_vec: Vector3, v_vec: Vector3, 
		segs_inner: int, segs_outer: int, 
		rows: int, start_idx: int) -> int:
	
	var total_verts = 0
	var current_idx = start_idx
	
	for r in range(rows + 1):
		var v_fraction = float(r) / float(rows)
		var current_segs = segs_inner
		if r == rows:
			current_segs = segs_outer
			
		var row_pos = origin + v_vec * v_fraction
		
		for i in range(current_segs + 1):
			var u_fraction = float(i) / float(current_segs)
			var pos = row_pos + u_vec * u_fraction
			
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(u_fraction, v_fraction)) 
			st.add_vertex(pos)
			total_verts += 1
			
	# 面索引 (常規區)
	for r in range(rows - 1):
		var row_start = current_idx + r * (segs_inner + 1)
		var next_row_start = current_idx + (r + 1) * (segs_inner + 1)
		for i in range(segs_inner):
			var p1 = row_start + i
			var p2 = row_start + i + 1
			var p3 = next_row_start + i
			var p4 = next_row_start + i + 1
			st.add_index(p1); st.add_index(p2); st.add_index(p3)
			st.add_index(p2); st.add_index(p4); st.add_index(p3)

	# 縫合區 (Transition Strip: 2 to 1 vertex reduction)
	var dense_row_start = current_idx + (rows - 1) * (segs_inner + 1)
	var sparse_row_start = current_idx + (rows) * (segs_inner + 1)
	for i in range(segs_outer):
		var s1 = sparse_row_start + i
		var s2 = sparse_row_start + i + 1
		var d1 = dense_row_start + 2 * i
		var d2 = dense_row_start + 2 * i + 1
		var d3 = dense_row_start + 2 * i + 2
		st.add_index(d1); st.add_index(d2); st.add_index(s1)
		st.add_index(d2); st.add_index(s2); st.add_index(s1)
		st.add_index(d2); st.add_index(d3); st.add_index(s2)
		
	return total_verts

# 正確的裙邊邏輯：法向朝向外側，而非向上
func _add_skirt(st: SurfaceTool, N: int, half_size: float, depth: float, start_idx: int):
	var step = (half_size * 2.0) / N
	var current_idx = start_idx
	
	# Top Edge (法線朝前 FORWARD)
	for i in range(N):
		var x1 = -half_size + i * step
		var x2 = x1 + step
		var p1 = Vector3(x1, 0, -half_size)
		var p2 = Vector3(x2, 0, -half_size)
		var p3 = Vector3(x1, -depth, -half_size) # Downwards
		var p4 = Vector3(x2, -depth, -half_size) # Downwards
		st.set_normal(Vector3.FORWARD); st.add_vertex(p1)
		st.set_normal(Vector3.FORWARD); st.add_vertex(p2)
		st.set_normal(Vector3.FORWARD); st.add_vertex(p3)
		st.set_normal(Vector3.FORWARD); st.add_vertex(p4)
		# Face order: (p1, p3, p2), (p2, p3, p4) for Front Face
		st.add_index(current_idx); st.add_index(current_idx+2); st.add_index(current_idx+1)
		st.add_index(current_idx+1); st.add_index(current_idx+2); st.add_index(current_idx+3)
		current_idx += 4
		
	# Bottom Edge (法線朝後 BACK)
	for i in range(N):
		var x1 = -half_size + i * step
		var x2 = x1 + step
		var p1 = Vector3(x2, 0, half_size)
		var p2 = Vector3(x1, 0, half_size)
		var p3 = Vector3(x2, -depth, half_size) # Downwards
		var p4 = Vector3(x1, -depth, half_size) # Downwards
		st.set_normal(Vector3.BACK); st.add_vertex(p1)
		st.set_normal(Vector3.BACK); st.add_vertex(p2)
		st.set_normal(Vector3.BACK); st.add_vertex(p3)
		st.set_normal(Vector3.BACK); st.add_vertex(p4)
		st.add_index(current_idx); st.add_index(current_idx+2); st.add_index(current_idx+1)
		st.add_index(current_idx+1); st.add_index(current_idx+2); st.add_index(current_idx+3)
		current_idx += 4
		
	# Left Edge (法線朝左 LEFT)
	for i in range(N):
		var z1 = -half_size + i * step
		var z2 = z1 + step
		var p1 = Vector3(-half_size, 0, z2)
		var p2 = Vector3(-half_size, 0, z1)
		var p3 = Vector3(-half_size, -depth, z2) # Downwards
		var p4 = Vector3(-half_size, -depth, z1) # Downwards
		st.set_normal(Vector3.LEFT); st.add_vertex(p1)
		st.set_normal(Vector3.LEFT); st.add_vertex(p2)
		st.set_normal(Vector3.LEFT); st.add_vertex(p3)
		st.set_normal(Vector3.LEFT); st.add_vertex(p4)
		st.add_index(current_idx); st.add_index(current_idx+2); st.add_index(current_idx+1)
		st.add_index(current_idx+1); st.add_index(current_idx+2); st.add_index(current_idx+3)
		current_idx += 4
		
	# Right Edge (法線朝右 RIGHT)
	for i in range(N):
		var z1 = -half_size + i * step
		var z2 = z1 + step
		var p1 = Vector3(half_size, 0, z1)
		var p2 = Vector3(half_size, 0, z2)
		var p3 = Vector3(half_size, -depth, z1) # Downwards
		var p4 = Vector3(half_size, -depth, z2) # Downwards
		st.set_normal(Vector3.RIGHT); st.add_vertex(p1)
		st.set_normal(Vector3.RIGHT); st.add_vertex(p2)
		st.set_normal(Vector3.RIGHT); st.add_vertex(p3)
		st.set_normal(Vector3.RIGHT); st.add_vertex(p4)
		st.add_index(current_idx); st.add_index(current_idx+2); st.add_index(current_idx+1)
		st.add_index(current_idx+1); st.add_index(current_idx+2); st.add_index(current_idx+3)
		current_idx += 4
