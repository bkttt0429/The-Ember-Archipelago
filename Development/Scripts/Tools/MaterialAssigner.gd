@tool
extends EditorScript

## MaterialAssigner - 一键自动套用材质脚本
## 使用方法：在脚本编辑器中打开此文件，点击 "文件" -> "运行" (或按 Ctrl+Shift+X)
## 脚本会扫描当前正在编辑的场景，根据节点名称自动匹配 Assets 目录中的贴图或材质。

const ASSETS_PATH = "res://Assets/Models/"

func _run():
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		printerr("[MaterialAssigner] 错误：未找到正在编辑的场景根节点。")
		return
	
	print("[MaterialAssigner] 开始扫描场景：%s" % root.name)
	var count = scan_node(root)
	print("[MaterialAssigner] 完成。共套用/更新材质数：%d" % count)

func scan_node(node: Node) -> int:
	var count = 0
	
	if node is MeshInstance3D:
		if apply_material_to_mesh(node):
			count += 1
	
	for child in node.get_children():
		count += scan_node(child)
	
	return count

func apply_material_to_mesh(mesh_node: MeshInstance3D) -> bool:
	# 如果已经有材质且不是默认材质，可以选择跳过（目前逻辑是尝试找更好的）
	var current_mat = mesh_node.get_surface_override_material(0)
	
	var mesh_name = mesh_node.name.to_lower()
	# 处理一些常见的后缀，如 -col, -mesh 等
	mesh_name = mesh_name.split("-")[0].split("_")[0]
	
	# 1. 尝试寻找现成的 .tres 材质
	var material_path = find_file_recursive(ASSETS_PATH, mesh_name + ".tres")
	if material_path != "":
		var mat = load(material_path)
		if mat is Material:
			mesh_node.set_surface_override_material(0, mat)
			print("  [✓] 节点 %s -> 套用材质: %s" % [mesh_node.name, material_path])
			return true

	# 2. 尝试寻找贴图并生成材质
	# 搜索模式：basecolor, albedo, diffuse
	var tex_keywords = ["basecolor", "albedo", "diffuse", "color"]
	var texture_path = ""
	
	for kw in tex_keywords:
		# 尝试 节点名_关键词
		texture_path = find_file_recursive(ASSETS_PATH, mesh_name + "_" + kw + ".png")
		if texture_path == "": texture_path = find_file_recursive(ASSETS_PATH, mesh_name + "_" + kw + ".jpg")
		if texture_path == "": texture_path = find_file_recursive(ASSETS_PATH, mesh_name + "_" + kw + ".jpeg")
		
		# 如果找不到，尝试直接节点名（针对某些简单命名）
		if texture_path == "":
			texture_path = find_file_recursive(ASSETS_PATH, mesh_name + ".png")
			if texture_path == "": texture_path = find_file_recursive(ASSETS_PATH, mesh_name + ".jpg")
			if texture_path == "": texture_path = find_file_recursive(ASSETS_PATH, mesh_name + ".jpeg")
		
		if texture_path != "":
			break
			
	if texture_path != "":
		var tex = load(texture_path)
		if tex is Texture2D:
			var new_mat = StandardMaterial3D.new()
			new_mat.albedo_texture = tex
			
			# 尝试寻找法线贴图
			var normal_path = find_file_recursive(ASSETS_PATH, mesh_name + "_normal.png")
			if normal_path == "": normal_path = find_file_recursive(ASSETS_PATH, mesh_name + "_normal.jpg")
			if normal_path != "":
				var norm_tex = load(normal_path)
				if norm_tex is Texture2D:
					new_mat.normal_enabled = true
					new_mat.normal_texture = norm_tex
			
			mesh_node.set_surface_override_material(0, new_mat)
			print("  [+] 节点 %s -> 生成材质 (基于贴图: %s)" % [mesh_node.name, texture_path.get_file()])
			return true

	return false

# 递归寻找文件（简单实现，大型项目建议缓存）
func find_file_recursive(path: String, target_file: String) -> String:
	var dir = DirAccess.open(path)
	if not dir: return ""
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				var result = find_file_recursive(path.path_join(file_name), target_file)
				if result != "": return result
		else:
			if file_name.to_lower() == target_file.to_lower():
				return path.path_join(file_name)
		file_name = dir.get_next()
	
	return ""
