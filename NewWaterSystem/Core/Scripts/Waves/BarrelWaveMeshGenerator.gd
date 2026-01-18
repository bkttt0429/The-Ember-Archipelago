class_name BarrelWaveMeshGenerator
extends RefCounted

## 程序化生成桶浪網格 (物理破碎版)
## 基於 Catenary (懸鏈線) 與 Bezier 曲線模擬真實破碎波形態
## 參考圖五 Breaking sea waves profiles 的演化邏輯

## 生成具有物理形態演化的桶浪網格
static func generate(
	radius: float = 5.0,
	length: float = 30.0,
	arc_segments: int = 16,
	length_segments: int = 12,
	base_t: float = 0.5, # 基礎破碎階段 (0=Building, 1=Breaking)
	temporal_spread: float = 0.5 # 沿長度方向的演化跨度 (實現 Peeling 效果)
) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var base_thickness = radius * 0.4
	var vertex_count_per_surface = (length_segments + 1) * (arc_segments + 1)
	
	# === 生成外表面 ===
	_generate_surface(surface_tool, radius, length, arc_segments, length_segments,
					  base_t, temporal_spread, 0.0, false)
	
	# === 生成內表面（帶厚度偏移）===
	_generate_surface(surface_tool, radius, length, arc_segments, length_segments,
					  base_t, temporal_spread, base_thickness, true)
	
	# === 生成三角形索引 (與之前一致) ===
	for li in range(length_segments):
		for ai in range(arc_segments):
			var i0 = li * (arc_segments + 1) + ai
			var i1 = i0 + 1
			var i2 = i0 + (arc_segments + 1)
			var i3 = i2 + 1
			surface_tool.add_index(i0); surface_tool.add_index(i2); surface_tool.add_index(i1)
			surface_tool.add_index(i1); surface_tool.add_index(i2); surface_tool.add_index(i3)
	
	for li in range(length_segments):
		for ai in range(arc_segments):
			var i0 = vertex_count_per_surface + li * (arc_segments + 1) + ai
			var i1 = i0 + 1
			var i2 = i0 + (arc_segments + 1)
			var i3 = i2 + 1
			surface_tool.add_index(i0); surface_tool.add_index(i1); surface_tool.add_index(i2)
			surface_tool.add_index(i1); surface_tool.add_index(i3); surface_tool.add_index(i2)
	
	# 封閉厚度 (端蓋)
	for li in range(length_segments):
		var outer_i0 = li * (arc_segments + 1)
		var outer_i1 = (li + 1) * (arc_segments + 1)
		var inner_i0 = vertex_count_per_surface + li * (arc_segments + 1)
		var inner_i1 = vertex_count_per_surface + (li + 1) * (arc_segments + 1)
		surface_tool.add_index(outer_i0); surface_tool.add_index(inner_i0); surface_tool.add_index(outer_i1)
		surface_tool.add_index(outer_i1); surface_tool.add_index(inner_i0); surface_tool.add_index(inner_i1)
	
	for li in range(length_segments):
		var outer_i0 = li * (arc_segments + 1) + arc_segments
		var outer_i1 = (li + 1) * (arc_segments + 1) + arc_segments
		var inner_i0 = vertex_count_per_surface + li * (arc_segments + 1) + arc_segments
		var inner_i1 = vertex_count_per_surface + (li + 1) * (arc_segments + 1) + arc_segments
		surface_tool.add_index(outer_i0); surface_tool.add_index(outer_i1); surface_tool.add_index(inner_i0)
		surface_tool.add_index(outer_i1); surface_tool.add_index(inner_i1); surface_tool.add_index(inner_i0)
	
	surface_tool.generate_tangents()
	surface_tool.commit(mesh)
	return mesh

static func _generate_surface(
	st: SurfaceTool, radius: float, length: float,
	arc_segs: int, len_segs: int,
	base_t: float, spread: float,
	thickness_offset: float, is_inner: bool
):
	for li in range(len_segs + 1):
		var l_t = float(li) / float(len_segs)
		# 關鍵：沿長度方向動態調整破碎進度 (Peeling 效果)
		var current_t = clamp(base_t + (l_t - 0.5) * spread, 0.0, 1.0)
		var z_pos = (l_t - 0.5) * length
		
		# 預計算剖面點以便計算法線
		var points = []
		for ai in range(arc_segs + 1):
			var a_t = float(ai) / float(arc_segs)
			points.append(_get_wave_profile_point(a_t, current_t, radius))
			
		for ai in range(arc_segs + 1):
			var a_t = float(ai) / float(arc_segs)
			var pos_2d = points[ai]
			
			# 計算法線與切線 (由相鄰點差分獲得)
			var next_idx = min(ai + 1, arc_segs)
			var prev_idx = max(ai - 1, 0)
			var delta = points[next_idx] - points[prev_idx]
			if delta.length() < 0.001: delta = Vector2(1, 0)
			var tangent_2d = delta.normalized()
			var normal_2d = Vector2(-tangent_2d.y, tangent_2d.x)
			
			# 厚度漸變：中間最厚，兩端（底部與唇部）漸薄
			var thick_mult = 1.0 - pow(abs(a_t - 0.5) * 2.0, 2.0)
			thick_mult = lerpf(0.2, 1.0, thick_mult)
			var actual_thickness = thickness_offset * thick_mult
			
			var final_pos = Vector3(pos_2d.x, pos_2d.y, z_pos)
			var normal = Vector3(normal_2d.x, normal_2d.y, 0).normalized()
			
			if is_inner:
				final_pos += normal * actual_thickness
				normal = - normal
			
			var edge_blend = smoothstep(0.0, 0.2, a_t)
			var uv = Vector2(a_t, l_t)
			
			st.set_normal(normal)
			st.set_uv(uv)
			# Color 傳遞資料給 Shader: R=邊緣混合, G=厚度比, B=弧位置
			st.set_color(Color(edge_blend, thick_mult, a_t, 1.0))
			st.set_tangent(Plane(Vector3(tangent_2d.x, tangent_2d.y, 0), 1.0))
			st.add_vertex(final_pos)

## 核心物理曲線函數
static func _get_wave_profile_point(a_t: float, t: float, radius: float) -> Vector2:
	# 基礎 Catenary 參數 (模擬水牆)
	var cat_a = radius * 0.7
	var shoaling = 1.0 + t * 0.5
	var steepening = t * 1.2
	
	if a_t <= 0.5:
		# 階段 1：底部到波峰 (Catenary)
		var p1_t = a_t * 2.0
		var x = - radius * (1.0 - p1_t * 0.4)
		var y = cat_a * cosh(p1_t * 1.5) - cat_a + radius * 0.2 * p1_t * shoaling
		# 加入前傾 (Steepening)
		x += p1_t * p1_t * steepening * 0.5
		return Vector2(x, y)
	else:
		# 階段 2：波峰到唇部 (Cubic Bezier)
		var p2_t = (a_t - 0.5) * 2.0
		
		# 起點 (波峰)
		var p0_x = - radius * (1.0 - 0.4) + steepening * 0.5
		var p0_y = cat_a * cosh(1.5) - cat_a + radius * 0.2 * shoaling
		var P0 = Vector2(p0_x, p0_y)
		
		# 控制點：模擬捲曲動態
		var P1 = P0 + Vector2(radius * 0.4, radius * 0.2 * (1.0 - t))
		var P2 = P0 + Vector2(radius * 1.2 * t, radius * 0.1 - radius * 0.4 * t)
		var P3 = P0 + Vector2(radius * 1.5 * t, -radius * 0.6 * t) # 唇部落點
		
		return _cubic_bezier(P0, P1, P2, P3, p2_t)

static func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var q0 = p0.lerp(p1, t)
	var q1 = p1.lerp(p2, t)
	var q2 = p2.lerp(p3, t)
	var r0 = q0.lerp(q1, t)
	var r1 = q1.lerp(q2, t)
	return r0.lerp(r1, t)

static func smoothstep(from: float, to: float, x: float) -> float:
	var t = clamp((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## 生成簡化版網格 (LOD)
static func generate_lod(radius: float, length: float) -> ArrayMesh:
	return generate(radius, length, 8, 4, 0.5, 0.3)

## 生成碰撞形狀
static func generate_collision_shape(radius: float, length: float) -> ConvexPolygonShape3D:
	var shape = ConvexPolygonShape3D.new()
	var points = PackedVector3Array()
	var steps = 8
	var z_steps = 3
	
	for zi in range(z_steps):
		var l_t = float(zi) / float(z_steps - 1)
		var z_pos = (l_t - 0.5) * length
		var current_t = 0.5 + (l_t - 0.5) * 0.5
		
		for ai in range(steps + 1):
			var a_t = float(ai) / float(steps)
			var p = _get_wave_profile_point(a_t, current_t, radius)
			points.append(Vector3(p.x, p.y, z_pos))
			# 簡單模擬內表面點以增加體積
			points.append(Vector3(p.x, p.y - 0.5, z_pos))
			
	shape.points = points
	return shape
