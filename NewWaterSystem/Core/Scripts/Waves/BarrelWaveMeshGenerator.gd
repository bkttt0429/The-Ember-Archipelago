class_name BarrelWaveMeshGenerator
extends RefCounted

## 程序化生成桶浪網格 (體積版 - 有厚度的水牆)
## 生成一個有實際厚度的捲曲水牆結構
## 參考真實衝浪照片的視覺效果

## 生成厚實的桶浪網格
static func generate(
	radius: float = 5.0,
	length: float = 30.0,
	arc_segments: int = 12,
	length_segments: int = 8,
	spiral_tightness: float = 0.3,
	lip_droop: float = 0.4
) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# 🔥 體積厚度：外表面和內表面之間的距離
	# 底部最厚，唇部較薄（真實波浪的特徵）
	var base_thickness = radius * 0.35 # 底部厚度 = 半徑的 35%
	var lip_thickness = radius * 0.08 # 唇部厚度 = 半徑的 8%
	
	var vertex_count_per_surface = (length_segments + 1) * (arc_segments + 1)
	
	# === 生成外表面 ===
	_generate_surface(surface_tool, radius, length, arc_segments, length_segments,
					  spiral_tightness, lip_droop, 0.0, false)
	
	# === 生成內表面（縮小半徑 = 厚度）===
	_generate_surface(surface_tool, radius, length, arc_segments, length_segments,
					  spiral_tightness, lip_droop, base_thickness, true)
	
	# === 生成三角形索引 ===
	# 外表面
	for li in range(length_segments):
		for ai in range(arc_segments):
			var i0 = li * (arc_segments + 1) + ai
			var i1 = i0 + 1
			var i2 = i0 + (arc_segments + 1)
			var i3 = i2 + 1
			
			surface_tool.add_index(i0)
			surface_tool.add_index(i2)
			surface_tool.add_index(i1)
			surface_tool.add_index(i1)
			surface_tool.add_index(i2)
			surface_tool.add_index(i3)
	
	# 內表面（翻轉方向）
	for li in range(length_segments):
		for ai in range(arc_segments):
			var i0 = vertex_count_per_surface + li * (arc_segments + 1) + ai
			var i1 = i0 + 1
			var i2 = i0 + (arc_segments + 1)
			var i3 = i2 + 1
			
			surface_tool.add_index(i0)
			surface_tool.add_index(i1)
			surface_tool.add_index(i2)
			surface_tool.add_index(i1)
			surface_tool.add_index(i3)
			surface_tool.add_index(i2)
	
	# === 生成端蓋（封閉厚度）===
	# 底部端蓋（a_t = 0 的位置，連接外表面和內表面）
	for li in range(length_segments):
		var outer_i0 = li * (arc_segments + 1)
		var outer_i1 = (li + 1) * (arc_segments + 1)
		var inner_i0 = vertex_count_per_surface + li * (arc_segments + 1)
		var inner_i1 = vertex_count_per_surface + (li + 1) * (arc_segments + 1)
		
		surface_tool.add_index(outer_i0)
		surface_tool.add_index(inner_i0)
		surface_tool.add_index(outer_i1)
		surface_tool.add_index(outer_i1)
		surface_tool.add_index(inner_i0)
		surface_tool.add_index(inner_i1)
	
	# 唇部端蓋（a_t = 1 的位置）
	for li in range(length_segments):
		var outer_i0 = li * (arc_segments + 1) + arc_segments
		var outer_i1 = (li + 1) * (arc_segments + 1) + arc_segments
		var inner_i0 = vertex_count_per_surface + li * (arc_segments + 1) + arc_segments
		var inner_i1 = vertex_count_per_surface + (li + 1) * (arc_segments + 1) + arc_segments
		
		surface_tool.add_index(outer_i0)
		surface_tool.add_index(outer_i1)
		surface_tool.add_index(inner_i0)
		surface_tool.add_index(outer_i1)
		surface_tool.add_index(inner_i1)
		surface_tool.add_index(inner_i0)
	
	surface_tool.generate_tangents()
	surface_tool.commit(mesh)
	
	return mesh


static func _generate_surface(
	surface_tool: SurfaceTool,
	radius: float, length: float,
	arc_segments: int, length_segments: int,
	spiral_tightness: float, lip_droop: float,
	thickness_offset: float, is_inner: bool
):
	# 厚度從底部到唇部漸變
	var base_thickness = radius * 0.35
	var lip_thickness = radius * 0.08
	
	for li in range(length_segments + 1):
		var l_t = float(li) / float(length_segments)
		var z_pos = (l_t - 0.5) * length
		
		for ai in range(arc_segments + 1):
			var a_t = float(ai) / float(arc_segments)
			
			# 當前厚度（從底部到唇部漸減）
			var current_thickness = lerpf(base_thickness, lip_thickness, a_t)
			var actual_offset = current_thickness if is_inner else 0.0
			
			# 調整半徑（內表面縮小）
			var effective_radius = radius - actual_offset
			var spiral_radius = effective_radius * exp(-spiral_tightness * a_t)
			
			var total_arc = PI + lip_droop
			var angle = PI - a_t * total_arc
			
			var x_pos = cos(angle) * spiral_radius
			var y_pos = sin(angle) * spiral_radius
			y_pos = max(y_pos, 0.0)
			
			var extra_droop = smoothstep(0.7, 1.0, a_t) * lip_droop * effective_radius * 0.5
			y_pos -= extra_droop
			
			# 法線
			var normal = Vector3(cos(angle), sin(angle), 0.0).normalized()
			if normal.y < 0.1:
				normal.y = 0.1
				normal = normal.normalized()
			
			if is_inner:
				normal = - normal
			
			# edge_blend 控制透明度
			var edge_blend = smoothstep(0.0, 0.15, a_t)
			
			var tangent = Vector3(sin(angle), -cos(angle), 0.0).normalized()
			if is_inner:
				tangent = - tangent
			
			var uv = Vector2(a_t, l_t)
			
			surface_tool.set_normal(normal)
			surface_tool.set_uv(uv)
			
			# 水厚度用於 SSS 計算
			var water_thickness = current_thickness
			# 內表面使用較高的 edge_blend
			var final_edge_blend = edge_blend if not is_inner else max(edge_blend, 0.7)
			surface_tool.set_color(Color(final_edge_blend, water_thickness / base_thickness, a_t, 1.0))
			surface_tool.set_tangent(Plane(tangent, 1.0))
			surface_tool.add_vertex(Vector3(x_pos, y_pos, z_pos))


## 生成簡化版網格 (用於 LOD)
static func generate_lod(radius: float, length: float) -> ArrayMesh:
	return generate(radius, length, 6, 4, 0.2, 0.3)


## 生成碰撞形狀
static func generate_collision_shape(radius: float, length: float) -> ConvexPolygonShape3D:
	var shape = ConvexPolygonShape3D.new()
	var points = PackedVector3Array()
	
	var thickness = radius * 0.35
	
	for li in range(3):
		var l_t = float(li) / 2.0
		var z_pos = (l_t - 0.5) * length
		
		# 外表面點
		for ai in range(6):
			var a_t = float(ai) / 5.0
			var angle = PI - a_t * (PI + 0.4)
			var spiral_radius = radius * exp(-0.3 * a_t)
			var x_pos = cos(angle) * spiral_radius
			var y_pos = max(sin(angle) * spiral_radius, 0.0)
			points.append(Vector3(x_pos, y_pos, z_pos))
		
		# 內表面點
		for ai in range(6):
			var a_t = float(ai) / 5.0
			var current_thickness = lerpf(thickness, thickness * 0.2, a_t)
			var angle = PI - a_t * (PI + 0.4)
			var spiral_radius = (radius - current_thickness) * exp(-0.3 * a_t)
			var x_pos = cos(angle) * spiral_radius
			var y_pos = max(sin(angle) * spiral_radius, 0.0)
			points.append(Vector3(x_pos, y_pos, z_pos))
	
	shape.points = points
	return shape
