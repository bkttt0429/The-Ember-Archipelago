class_name BarrelWaveMeshGenerator
extends RefCounted

## 程序化生成桶浪網格 (180° 弧形管道)

const TWO_PI = PI * 2.0

## 生成桶浪網格
## @param radius: 管道半徑
## @param length: 波浪長度 (沿波浪方向)
## @param arc_segments: 弧形分段數 (越多越圓滑)
## @param length_segments: 長度分段數
## @param arc_start_deg: 弧形起始角度 (0=右側水平)
## @param arc_end_deg: 弧形結束角度 (180=左側水平)
static func generate(
	radius: float = 5.0,
	length: float = 30.0,
	arc_segments: int = 12,
	length_segments: int = 8,
	arc_start_deg: float = 190.0, # 稍微低於水平（銜接後面）
	arc_end_deg: float = -20.0 # 前方捲曲，稍微超過 0° 形成唇部下垂
) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var arc_start = deg_to_rad(arc_start_deg)
	var arc_end = deg_to_rad(arc_end_deg)
	var arc_range = arc_end - arc_start
	
	# 生成頂點
	for li in range(length_segments + 1):
		var l_t = float(li) / float(length_segments)
		var z_pos = (l_t - 0.5) * length # 沿 Z 軸延伸
		
		for ai in range(arc_segments + 1):
			var a_t = float(ai) / float(arc_segments)
			var angle = arc_start + arc_range * a_t
			
			# 圓柱座標 -> 笛卡爾座標
			# Y = 上方, X = 右側 (波浪前進方向)
			var x_pos = cos(angle) * radius
			var y_pos = sin(angle) * radius
			
			# 法線指向圓心外側
			var normal = Vector3(cos(angle), sin(angle), 0.0).normalized()
			
			# UV: U = 弧形位置, V = 長度位置
			var uv = Vector2(a_t, l_t)
			
			surface_tool.set_normal(normal)
			surface_tool.set_uv(uv)
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


## 生成簡化版網格 (用於 LOD)
static func generate_lod(radius: float, length: float) -> ArrayMesh:
	return generate(radius, length, 6, 4, 190.0, -20.0)


## 生成碰撞形狀
static func generate_collision_shape(radius: float, length: float) -> ConvexPolygonShape3D:
	var shape = ConvexPolygonShape3D.new()
	var points = PackedVector3Array()
	
	# 簡化版：只用 8 個弧形點 × 3 個長度點 = 24 點
	for li in range(3):
		var l_t = float(li) / 2.0
		var z_pos = (l_t - 0.5) * length
		
		for ai in range(8):
			var angle = deg_to_rad(190.0 - 210.0 * float(ai) / 7.0)
			var x_pos = cos(angle) * radius
			var y_pos = sin(angle) * radius
			points.append(Vector3(x_pos, y_pos, z_pos))
	
	shape.points = points
	return shape
