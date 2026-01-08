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
	# This represents a 2x scale relative to the center mesh's coverage.
	# We want the inner density to match CenterMesh density.
	# Center Mesh Size = 1. Subdivs = N. Density = N/1.
	# Ring Mesh Inner Edge Length = 1. Subdivs must be N.
	# Ring Mesh Thickness = 0.5. Subdivs must be N/2.
	# Ring Mesh Outer Edge Length = 2. Subdivs must be 2N.
	ring_mesh = _create_unit_ring_mesh(base_subdivisions)
	
	# 2. Instantiate Levels
	var current_scale = base_grid_size
	
	for i in range(clipmap_levels):
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		if i == 0:
			mesh_inst.mesh = center_mesh
			# Center mesh is unit size 1 (-0.5 to 0.5).
			# We want it to cover 'base_grid_size'.
			# So we scale by base_grid_size.
			mesh_inst.scale = Vector3(current_scale, 1, current_scale)
		else:
			mesh_inst.mesh = ring_mesh
			# Ring mesh is unit size 2 (outer -1 to 1).
			# We want it to surround previous level.
			# Level 0 covers 'current_scale'.
			# Level 1 needs hole of 'current_scale'.
			# RingMesh hole is -0.5 to 0.5 (size 1). 
			# Scaling RingMesh by 'current_scale' makes the hole size 'current_scale'.
			# PERFECT.
			mesh_inst.scale = Vector3(current_scale, 1, current_scale)
			
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
	if not follow_target:
		return
	var t_pos = follow_target.global_position
	var flat_pos = Vector3(t_pos.x, 0, t_pos.z)
	
	# Smooth follow (no snapping) prevents vertex swimming in shader.
	# The geometry centers are always aligned.
	for m in meshes:
		m.global_position = flat_pos

# --- Mesh Generation Helpers ---

func _create_center_mesh(N: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half = 0.5
	var step = 1.0 / N
	
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
	
	return st.commit()

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
