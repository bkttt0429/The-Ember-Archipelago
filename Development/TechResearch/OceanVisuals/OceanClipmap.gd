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
		base_subdivisions = (base_subdivisions / 4 + 1) * 4
	
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
		# Wait, the error says: Cannot find member "TRANSPARENCY_DISABLED" in base "GeometryInstance3D".
		# It's likely BaseMaterial3D.TRANSPARENCY_DISABLED.
		# But wait, why are we setting transparency here? The material handles transparency.
		# Let's remove this line as it's causing errors and likely unnecessary if material is set up right.
		# Or if we want to force opaque:
		# mesh_inst.transparency = 0.0 
		
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
		
		if i > 0:
			current_scale *= 2.0

func _process(delta):
	# Optimize: Only update if target moved significantly? For now per frame is fine.
	if not follow_target:
		return
	var t_pos = follow_target.global_position
	var flat_pos = Vector3(t_pos.x, 0, t_pos.z)
	
	# Smooth follow (no snapping)
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
	_add_skirt(st, N, half, -0.1, center_verts)
			
	return st.commit()

func _create_unit_ring_mesh(N: int) -> ArrayMesh:
	# Ring Unit Mesh
	# Outer: -1.0 to 1.0 (Size 2.0)
	# Inner: -0.5 to 0.5 (Size 1.0)
	# Density target: based on Inner edge having N subdivisions.
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Thickness = (2.0 - 1.0) / 2 = 0.5.
	# N subdivs per unit length.
	# So Thickness needs N * 0.5 = N/2 subdivs.
	var N_thickness = N / 2
	var N_full = 2 * N
	
	var vert_offset = 0
	
	# 1. Top Rect: X[-1, 1], Z[-1, -0.5]
	# Width 2 (2N subdivs). Height 0.5 (N/2 subdivs).
	vert_offset += _add_rect(st, -1.0, 1.0, -1.0, -0.5, 2*N, N_thickness, vert_offset)
	
	# 2. Bot Rect: X[-1, 1], Z[0.5, 1.0]
	vert_offset += _add_rect(st, -1.0, 1.0, 0.5, 1.0, 2*N, N_thickness, vert_offset)
	
	# 3. Left Rect: X[-1, -0.5], Z[-0.5, 0.5]
	# Width 0.5 (N/2). Height 1 (N).
	vert_offset += _add_rect(st, -1.0, -0.5, -0.5, 0.5, N_thickness, N, vert_offset)
	
	# 4. Right Rect: X[0.5, 1.0], Z[-0.5, 0.5]
	vert_offset += _add_rect(st, 0.5, 1.0, -0.5, 0.5, N_thickness, N, vert_offset)
	
	# Add Skirts (Only Outer Edge needed: -1 to 1)
	# Ring Outer Perimeter matches a square of size 2.0 (half_size 1.0)
	# subdivisions = 2*N along the edge
	# vert_offset is currently at the end of all ring rects
	var skirt_N = 2 * N 
	_add_skirt(st, skirt_N, 1.0, -0.1, vert_offset)
	
	return st.commit()

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

func _add_rect(st: SurfaceTool, xmin: float, xmax: float, zmin: float, zmax: float, subx: int, subz: int, offset: int) -> int:
	var sx = (xmax - xmin) / subx
	var sz = (zmax - zmin) / subz
	
	for z in range(subz + 1):
		for x in range(subx + 1):
			# UVs? For Clipmaps, world pos is usually used.
			# But we can provide 0-1 UVs relative to the Rect for debug.
			st.set_uv(Vector2(float(x)/subx, float(z)/subz))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(xmin + x * sx, 0, zmin + z * sz))
			
	for z in range(subz):
		for x in range(subx):
			var i = offset + z * (subx + 1) + x
			st.add_index(i)
			st.add_index(i + (subx + 1))
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + (subx + 1))
			st.add_index(i + (subx + 1) + 1)
			
	return (subx + 1) * (subz + 1)
