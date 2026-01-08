@tool
extends Node3D

# Ocean Clipmap LOD System
# Uses instanced unit meshes to create a high-performance nested grid key concept of Geometry Clipmaps.
# Level 0: Uses a Center Mesh.
# Level 1..N: Uses a Ring Mesh scaled 2x each level.

@export var clipmap_levels: int = 6
@export var base_grid_size: float = 64.0
@export var base_subdivisions: int = 32: # Reduced to 32 to avoid >65k vertex limit in a single mesh (Ring has ~4x count)  
	set(v):
		base_subdivisions = v
		if is_inside_tree(): _generate_clipmap()

@export var skirt_depth: float = 10.0:
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
	for m in meshes:
		if m: m.material_override = material

func _generate_clipmap():
	# Cleaning
	for m in meshes:
		if m: m.queue_free()
	meshes.clear()
	
	center_mesh = null
	ring_mesh = null
	
	# Safeguard subdivisions
	if base_subdivisions % 4 != 0:
		base_subdivisions = int((float(base_subdivisions) / 4.0 + 1.0)) * 4
	
	# 1. Generate Base Meshes (Unit sized)
	# Center Mesh: -0.5 to 0.5
	center_mesh = _create_center_mesh(base_subdivisions)
	
	# Ring Mesh: Outer -1.0 to 1.0, Inner -0.5 to 0.5
	ring_mesh = _create_unit_ring_mesh(base_subdivisions)
	
	# 2. Instantiate Levels
	var current_scale = base_grid_size
	
	for i in range(clipmap_levels):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Set Cull Margin huge to prevent flickering
		mesh_inst.extra_cull_margin = 16384.0
		
		# Ensure proper rendering order and depth testing
		# Godot 4 API Change: transparency is an enum on GeometryInstance3D base? 
		# No, it's a property on BaseMaterial3D for materials, but for GeometryInstance3D it's 'transparency' property with float or Transparency mode enum?
		# Actually, 'TRANSPARENCY_DISABLED' is part of BaseMaterial3D enum Transparency.
		# But 'transparency' property on GeometryInstance3D takes a float (0.0 - 1.0) in some contexts or an enum in others?
		# Inspecting docs: GeometryInstance3D has 'transparency' property which is float.
		
		if i == 0:
			mesh_inst.mesh = center_mesh
			mesh_inst.scale = Vector3(current_scale, 1, current_scale)
		else:
			mesh_inst.mesh = ring_mesh
			mesh_inst.scale = Vector3(current_scale, 1, current_scale) # Ring hole (0.5*2*S = S) matches prev layer
			
			# After using current_scale for the Ring, the 'outer' size is effectively 2*base_grid_size.
			# This is exactly what the *next* Ring needs as a hole.
			# So we double current_scale for the next iteration.
	
		mesh_inst.name = "LOD_Level_" + str(i)
		if material:
			mesh_inst.material_override = material
		
		add_child(mesh_inst)
		meshes.append(mesh_inst)
		
		# Double the scale for the next level (concentric rings)
		current_scale *= 2.0

func _process(_delta):
	# Optimize: Only update if target moved significantly? For now per frame is fine.
	if not follow_target:
		return
	var t_pos = follow_target.global_position
	# Snap the grid to maintain alignment with the simulation pixels
	# and prevent LOD crawling artifacts.
	var step_size = base_grid_size / float(base_subdivisions)
	var snapped_x = floor(t_pos.x / step_size) * step_size
	var snapped_z = floor(t_pos.z / step_size) * step_size
	var flat_pos = Vector3(snapped_x, 0, snapped_z)
	
	for m in meshes:
		m.global_position = flat_pos

# --- Mesh Generation Helpers ---

func _create_center_mesh(N: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half = 0.5
	var step = 1.0 / N
	
	# Main Grid
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
			
	# Add Skirts (Outer Edge)
	# Perimeter: Top, Right, Bot, Left
	# Center mesh has (N+1)*(N+1) vertices before skirts
	var center_verts = (N + 1) * (N + 1)
	_add_skirt(st, N, half, -skirt_depth, center_verts)
			
	return st.commit()

func _create_unit_ring_mesh(N: int) -> ArrayMesh:
	# Ring Unit Mesh
	# Outer: -1.0 to 1.0 (Size 2.0)
	# Inner: -0.5 to 0.5 (Size 1.0)
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Thickness logic
	# Inner Edge of Ring (LOD i) must match Outer Edge of Center (LOD i-1) or Inner Ring (LOD i-1).
	# Center Mesh has N segments per unit length (0.5 to -0.5 is length 1.0 -> N segments).
	# Step size = 1.0 / N.
	
	# Outer Edge of Ring (LOD i) will touch Inner Edge of Ring (LOD i+1).
	# Ring (LOD i+1) has scale 2.0. Its inner edge (relative to self) is 1.0 unit length.
	# But in world space it traverses 2.0 units with N segments. 
	# So step size is 2.0 / N.
	
	# This Ring (LOD i) at its Outer Edge (length 2.0) naturally has 2N segments if we keep density.
	# Step size 2.0 / 2N = 1.0 / N.
	# To match LOD i+1, we must reduce segments from 2N to N at the outer edge.
	
	# Thickness reduced to N/4 to ensures the side edges (Corners) also sum up to N segments (N/4 + N/2 + N/4 = N)
	# matching the next LOD's inner edge.
	var N_thickness = int(float(N) / 4.0)
	var start_idx = 0
	
	# 1. Top Rect: X[-1, 1], Z connects -0.5 to -1.0
	# Inner Edge: Z=-0.5. Width 2.0. 
	# Note: The "Hole" is X[-0.5, 0.5]. 
	# The Top Rect effectively spans the full width X[-1, 1].
	# At Z=-0.5 (Inner), the segments must align with:
	#   Left Rect Top (X: -1 to -0.5) -> N/2 segments
	#   Center Mesh Top (X: -0.5 to 0.5) -> N segments
	#   Right Rect Top (X: 0.5 to 1) -> N/2 segments
	# Total 2N segments.
	# Outer Edge: Z=-1.0. Needs N segments to align with next LOD.
	# Direction: Z decreases (Inner -0.5 -> Outer -1.0).
	start_idx += _add_ring_section(st, 
		Vector3(-1.0, 0, -0.5), Vector3(2.0, 0, 0), Vector3(0, 0, -0.5), # Origin(Inner-Left), U(Right), V(Out/Back)
		2 * N, N,  # 2N segments at inner edge, reducing to N at outer
		N_thickness, start_idx)

	# 2. Bot Rect: X[-1, 1], Z connects 0.5 to 1.0
	# Inner Z=0.5. Outer Z=1.0.
	start_idx += _add_ring_section(st,
		Vector3(-1.0, 0, 0.5), Vector3(2.0, 0, 0), Vector3(0, 0, 0.5),
		2 * N, N,
		N_thickness, start_idx)
		
	# 3. Left Rect: X connects -0.5 to -1.0, Z[-0.5, 0.5]
	# Inner X=-0.5. Height 1.0 -> N segments.
	# Outer X=-1.0. Height 1.0 -> N/2 segments (to match next LOD vertical density).
	# Wait, Ring outer perimeter is a square of 2.0.
	# Next LOD inner hole is size 2.0. Next LOD inner step is 2.0/N.
	# So yes, we need N segments along the side of length 2.0.
	# But here Left Rect is length 1.0 (vertical).
	# Does next LOD Left Rect cover this?
	# Next LOD Left Rect spans Z from -1.0 to 1.0.
	# Our Left Rect spans Z from -0.5 to 0.5.
	# So along the Z axis, we have N segments.
	# Next LOD along Z axis (length 2.0) has N segments.
	# So for length 1.0, Next LOD has N/2 segments.
	# So we reduce N -> N/2. Correct.
	start_idx += _add_ring_section(st,
		Vector3(-0.5, 0, -0.5), Vector3(0, 0, 1.0), Vector3(-0.5, 0, 0), # Origin(Inner-Top), "U"(Down), "V"(Left-Out)
		N, int(N / 2),
		N_thickness, start_idx)

	# 4. Right Rect: X connects 0.5 to 1.0, Z[-0.5, 0.5]
	start_idx += _add_ring_section(st,
		Vector3(0.5, 0, -0.5), Vector3(0, 0, 1.0), Vector3(0.5, 0, 0), # Origin(Inner-Top), "U"(Down), "V"(Right-Out)
		N, int(N / 2),
		N_thickness, start_idx)
	
	# Add Skirts
	# We use the simplified N count for the outer edge
	var skirt_N = 4 * N # Total perimeter segments of next LOD?
	# Top side (Length 2.0) has N segments.
	# So 4 sides = 4N.
	# We can use _add_skirt but it assumes uniform square.
	# Our outer edge is uniformly N segments per side (Length 2.0).
	# So N parameter for _add_skirt should be N.
	# _add_skirt expects N to be segments per side.
	# half_size is 1.0.
	_add_skirt(st, N, 1.0, -skirt_depth, start_idx)
	
	return st.commit()

func _add_ring_section(st: SurfaceTool, 
		origin: Vector3, u_vec: Vector3, v_vec: Vector3, 
		segs_inner: int, segs_outer: int, 
		rows: int, start_idx: int) -> int:
	
	# Generates a grid that transitions from segs_inner to segs_outer.
	# Assumes segs_inner = 2 * segs_outer.
	# Rows: number of strips in v_direction.
	
	var total_verts = 0
	
	# We generate rows+1 lines of vertices.
	# For rows 0 to rows-1 (the "inner" part), keep high detail (segs_inner).
	# Only the very last row (index rows) drops to segs_outer?
	# No, T-junction repair happens at the last strip of triangles.
	# Vertices:
	# Row 0: segs_inner + 1 verts
	# ...
	# Row rows-1: segs_inner + 1 verts
	# Row rows: segs_outer + 1 verts
	
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
			
	# Indices
	# Regular, dense strips for 0 to rows-2
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

	# Transition Strip (Last Row)
	# Connects Row (rows-1) [Dense] to Row (rows) [Sparse]
	var dense_row_start = current_idx + (rows - 1) * (segs_inner + 1)
	var sparse_row_start = current_idx + (rows) * (segs_inner + 1) # Note: sparse count used for offset accumulation?
	# Wait, accumulation logic above matches? 
	# Row 0..rows-1 have (segs_inner+1) verts. Total rows * (segs_inner+1)
	# So sparse_row_start is correct.
	
	for i in range(segs_outer):
		# Sparse segment i connects with Dense segments 2*i and 2*i+1
		# Sparse indices: S1=i, S2=i+1
		# Dense indices: D1=2*i, D2=2*i+1, D3=2*i+2
		
		var s1 = sparse_row_start + i
		var s2 = sparse_row_start + i + 1
		
		var d1 = dense_row_start + 2 * i
		var d2 = dense_row_start + 2 * i + 1
		var d3 = dense_row_start + 2 * i + 2
		
		# Triangles:
		# (S1, D1, D2)
		# (S1, D2, S2)
		# (S2, D2, D3)
		
		# Winding order (Standard CCW? Godot defaults to CW/CCW depending on cull. Assuming CCW/Backface culling default)
		# Check previous: p1(BL), p2(BR), p3(TL)...
		# Standard quad (p1, p2, p3) -> (0,0), (1,0), (0,1).
		# Here "U" is Right, "V" is Out/Back.
		# Row r is Inner. Row r+1 is Outer.
		# So Dense is "Inner/Top", Sparse is "Outer/Bottom".
		# Wait, visual check:
		# Origin at (0,0). V goes down.
		# Dense Row at Y=0. Sparse Row at Y=1.
		# D1(0,0), D2(0.5,0), D3(1,0)
		# S1(0,1), S2(1,1)
		# Tri 1: D1, D2, S1 -> (0,0)->(0.5,0)->(0,1). CCW. Correct.
		# Tri 2: D2, S2, S1 -> (0.5,0)->(1,1)->(0,1). CCW. Correct.
		# Tri 3: D2, D3, S2 -> (0.5,0)->(1,0)->(1,1). CCW. Correct.
		
		st.add_index(d1); st.add_index(d2); st.add_index(s1)
		st.add_index(d2); st.add_index(s2); st.add_index(s1)
		st.add_index(d2); st.add_index(d3); st.add_index(s2)
		
	return total_verts

func _add_skirt(st: SurfaceTool, N: int, half_size: float, depth: float, start_idx: int):
	# Adds vertical quads around the square perimeter [-half_size, half_size]
	# N segments per side
	
	var step = (half_size * 2.0) / N
	var current_idx = start_idx
	
	# Top Edge (z = -half_size, x: -half -> half)
	for i in range(N):
		var x1 = -half_size + i * step
		var x2 = x1 + step
		var p1 = Vector3(x1, 0, -half_size)
		var p2 = Vector3(x2, 0, -half_size)
		
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0,0))
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(Vector3(p1.x, depth, p1.z))
		st.add_vertex(Vector3(p2.x, depth, p2.z))
		
		st.add_index(current_idx); st.add_index(current_idx+1); st.add_index(current_idx+2)
		st.add_index(current_idx+1); st.add_index(current_idx+3); st.add_index(current_idx+2)
		current_idx += 4
		
	# Bot Edge (z = half_size, x: -half -> half)
	for i in range(N):
		var x1 = -half_size + i * step
		var x2 = x1 + step
		var p1 = Vector3(x2, 0, half_size) # Reversed winding implies p1 is right
		var p2 = Vector3(x1, 0, half_size)
		
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0,0))
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(Vector3(p1.x, depth, p1.z))
		st.add_vertex(Vector3(p2.x, depth, p2.z))
		
		st.add_index(current_idx); st.add_index(current_idx+1); st.add_index(current_idx+2)
		st.add_index(current_idx+1); st.add_index(current_idx+3); st.add_index(current_idx+2)
		current_idx += 4
		
	# Left Edge (x = -half_size, z: -half -> half)
	for i in range(N):
		var z1 = -half_size + i * step
		var z2 = z1 + step
		var p1 = Vector3(-half_size, 0, z2)
		var p2 = Vector3(-half_size, 0, z1)
		
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0,0))
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(Vector3(p1.x, depth, p1.z))
		st.add_vertex(Vector3(p2.x, depth, p2.z))
		
		st.add_index(current_idx); st.add_index(current_idx+1); st.add_index(current_idx+2)
		st.add_index(current_idx+1); st.add_index(current_idx+3); st.add_index(current_idx+2)
		current_idx += 4
		
	# Right Edge (x = half_size, z: -half -> half)
	for i in range(N):
		var z1 = -half_size + i * step
		var z2 = z1 + step
		var p1 = Vector3(half_size, 0, z1)
		var p2 = Vector3(half_size, 0, z2)
		
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0,0))
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(Vector3(p1.x, depth, p1.z))
		st.add_vertex(Vector3(p2.x, depth, p2.z))
		
		st.add_index(current_idx); st.add_index(current_idx+1); st.add_index(current_idx+2)
		st.add_index(current_idx+1); st.add_index(current_idx+3); st.add_index(current_idx+2)
		current_idx += 4
