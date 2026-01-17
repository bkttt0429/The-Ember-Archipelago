class_name BarrelWaveMeshGenerator
extends RefCounted

## 程序化生成桶浪網格 (Phase 1 Enhanced)
## 使用對數螺旋輪廓 + edge_blend_factor 實現自然捲曲

## 生成桶浪網格
## @param radius: 管道半徑（控制"捲曲"的大小）
## @param length: 沿波冠延伸的長度
## @param arc_segments: 弧形分段數
## @param length_segments: 長度分段數
## @param spiral_tightness: 螺旋緊密度 (0.2-0.5 推薦)
## @param lip_droop: 唇部下垂量 (0-1)
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
	
	# 🔥 Phase 1: 對數螺旋弧形
	# 弧形從 0° (後方/接海面) 到 220° (唇部下垂)
	var arc_start = deg_to_rad(0.0)
	var arc_end = deg_to_rad(220.0) # 超過 180° 形成下垂
	var arc_range = arc_end - arc_start
	
	# 生成頂點
	for li in range(length_segments + 1):
		var l_t = float(li) / float(length_segments)
		var z_pos = (l_t - 0.5) * length # 沿 Z 軸延伸（波冠方向）
		
		for ai in range(arc_segments + 1):
			var a_t = float(ai) / float(arc_segments)
			var angle = arc_start + arc_range * a_t
			
			# 🔥 Phase 1 Fix: 對數螺旋半徑 (漸細的捲曲)
			# 底部 (a_t=0) 使用完整 radius，唇部 (a_t=1) 漸細
			var spiral_radius = radius * exp(-spiral_tightness * a_t)
			
			# 🔥 Phase 1 Fix: 唇部下垂效果
			# 只在弧形後半段 (a_t > 0.6) 應用下垂
			var droop_factor = smoothstep(0.6, 1.0, a_t)
			var lip_droop_offset = sin(a_t * PI) * lip_droop * radius * droop_factor
			
			# 圓柱座標 -> 笛卡爾座標
			var x_pos = - cos(angle) * spiral_radius
			var y_pos = sin(angle) * spiral_radius - lip_droop_offset
			
			# 法線指向圓心外側 (考慮螺旋變形)
			var normal = Vector3(-cos(angle), sin(angle), 0.0).normalized()
			
			# 🔥 Phase 1 Fix: edge_blend_factor 存入 COLOR.r
			# 0 = 底部 (應與海面混合), 1 = 完整桶浪形狀
			var edge_blend = smoothstep(0.0, 0.2, a_t) # 底部 20% 漸變
			
			# 🔥 Phase 1: 切線方向 (用於流動法線)
			# 切線沿弧形方向
			var tangent = Vector3(sin(angle), cos(angle), 0.0).normalized()
			
			# UV: U = 弧形位置 (用於深度模擬), V = 長度位置
			var uv = Vector2(a_t, l_t)
			
			surface_tool.set_normal(normal)
			surface_tool.set_uv(uv)
			# 存儲 edge_blend 和 water_thickness 到 COLOR
			# R = edge_blend, G = water_thickness 估算, B = unused, A = 1
			var water_thickness = mix(3.0, 0.2, a_t) # 底部厚，唇部薄
			surface_tool.set_color(Color(edge_blend, water_thickness / 3.0, 0.0, 1.0))
			surface_tool.set_tangent(Plane(tangent, 1.0))
			surface_tool.add_vertex(Vector3(x_pos, y_pos, z_pos))
	
	# 生成三角形索引
	for li in range(length_segments):
		for ai in range(arc_segments):
			var i0 = li * (arc_segments + 1) + ai
			var i1 = i0 + 1
			var i2 = i0 + (arc_segments + 1)
			var i3 = i2 + 1
			
			# 兩個三角形組成一個四邊形
			surface_tool.add_index(i0)
			surface_tool.add_index(i2)
			surface_tool.add_index(i1)
			
			surface_tool.add_index(i1)
			surface_tool.add_index(i2)
			surface_tool.add_index(i3)
	
	surface_tool.generate_tangents()
	surface_tool.commit(mesh)
	
	return mesh

## 輔助函數：線性插值
static func mix(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

## 生成簡化版網格 (用於 LOD)
static func generate_lod(radius: float, length: float) -> ArrayMesh:
	return generate(radius, length, 6, 4, 0.2, 0.3)


## 生成碰撞形狀
static func generate_collision_shape(radius: float, length: float) -> ConvexPolygonShape3D:
	var shape = ConvexPolygonShape3D.new()
	var points = PackedVector3Array()
	
	# 簡化版：8 個弧形點 × 3 個長度點 = 24 點
	for li in range(3):
		var l_t = float(li) / 2.0
		var z_pos = (l_t - 0.5) * length
		
		for ai in range(8):
			var a_t = float(ai) / 7.0
			var angle = deg_to_rad(220.0 * a_t)
			# 使用螺旋半徑
			var spiral_radius = radius * exp(-0.3 * a_t)
			var x_pos = - cos(angle) * spiral_radius
			var y_pos = sin(angle) * spiral_radius
			points.append(Vector3(x_pos, y_pos, z_pos))
	
	shape.points = points
	return shape
