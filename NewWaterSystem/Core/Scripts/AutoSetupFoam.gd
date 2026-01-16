@tool
extends EditorScript

# 使用說明：
# 1. 在 FileSystem 面板中右鍵點擊此腳本 -> Run
# 2. 或者打開腳本編輯器，點擊 File -> Run
# 3. 確保你的場景中有 OceanWaterManager 節點

func _run():
	var root = get_scene()
	if not root:
		print("Error: No active scene root found.")
		return
		
	var water_manager = _find_node_by_type(root, "OceanWaterManager")
	if not water_manager:
		print("Error: Could not find OceanWaterManager in the scene.")
		return
		
	print("Found WaterManager: ", water_manager.name)
	
	# 1. Create Foam Detail Texture
	if not water_manager.foam_detail_tex:
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.05
		noise.fractal_octaves = 4
		
		var tex = NoiseTexture2D.new()
		tex.noise = noise
		tex.width = 512; tex.height = 512
		tex.seamless = true
		tex.as_normal_map = false
		
		water_manager.foam_detail_tex = tex
		print("--> Created and assigned Foam Detail Texture")
		
	# 2. Create Foam Sparkle Texture
	if not water_manager.foam_sparkle_tex:
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.1
		noise.fractal_octaves = 2
		noise.cellular_jitter = 1.0
		
		var tex = NoiseTexture2D.new()
		tex.noise = noise
		tex.width = 512; tex.height = 512
		tex.seamless = true
		
		water_manager.foam_sparkle_tex = tex
		print("--> Created and assigned Foam Sparkle Texture")

	# 3. Create Foam Normal Texture
	if not water_manager.foam_normal_tex:
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
		noise.frequency = 0.05
		
		var tex = NoiseTexture2D.new()
		tex.noise = noise
		tex.width = 512; tex.height = 512
		tex.seamless = true
		tex.as_normal_map = true # Key
		tex.bump_strength = 8.0
		
		water_manager.foam_normal_tex = tex
		print("--> Created and assigned Foam Normal Texture")
		
	# 4. Check FoamParticleManager
	var foam_particles = _find_node_by_name(root, "FoamParticleManager")
	if not foam_particles:
		foam_particles = _find_node_by_name(root, "FoamParticles")
	
	# If not found, try to create it?
	if not foam_particles:
		print("FoamParticleManager node not found. Creating one...")
		var particle_script = load("res://NewWaterSystem/Core/Scripts/FoamParticleManager.gd")
		if particle_script:
			var node = Node3D.new()
			node.name = "FoamParticleManager"
			node.set_script(particle_script)
			water_manager.add_child(node)
			node.owner = root # Ensure it saves with scene
			node.position = Vector3(0, 0, 0)
			
			# Assign reference
			node.water_manager = water_manager
			
			# Assign Texture (reuse detail or create new billbaord tex)
			var noise_bb = FastNoiseLite.new()
			noise_bb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			var tex_bb = NoiseTexture2D.new()
			tex_bb.noise = noise_bb
			node.foam_texture = tex_bb
			
			foam_particles = node
			print("--> Created FoamParticleManager node and assigned dependencies.")
		else:
			print("Error: Could not load FoamParticleManager.gd script.")
	else:
		print("Found FoamParticleManager. Updating dependencies...")
		if "water_manager" in foam_particles:
			foam_particles.water_manager = water_manager
		if "foam_texture" in foam_particles and not foam_particles.foam_texture:
			var noise_bb = FastNoiseLite.new()
			noise_bb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			var tex_bb = NoiseTexture2D.new()
			tex_bb.noise = noise_bb
			foam_particles.foam_texture = tex_bb
			print("--> Assigned default texture to FoamParticleManager")

	# 5. Setup Boat Loop
	var boat = _find_node_by_name(root, "Boat")
	if boat:
		print("Found Boat node.")
		if not boat.get_script() or boat.get_script().resource_path != "res://NewWaterSystem/Core/Scripts/BoatAutoCircle.gd":
			var boat_script = load("res://NewWaterSystem/Core/Scripts/BoatAutoCircle.gd")
			if boat_script:
				boat.set_script(boat_script)
				# Need to explicitly set values because assigning script at runtime resets them or they might be 0
				boat.forward_force = 8000.0
				boat.turn_strength = 1500.0
				boat.active = true
				print("--> Attached BoatAutoCircle script to Boat. It will now move in circles!")
			else:
				print("Error Loading BoatAutoCircle script")
		else:
			print("--> Boat already has the AutoCircle script.")
			
	print("\n=== Auto Setup Complete. Please save the scene. ===")

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name or (node.get_script() and node.get_script().resource_path.ends_with(type_name + ".gd")): # Loose check
		return node
	# Specific check for our class_name
	if node is OceanWaterManager:
		return node
		
	for child in node.get_children():
		var res = _find_node_by_type(child, type_name)
		if res: return res
	return null

func _find_node_by_name(node: Node, name_str: String) -> Node:
	if node.name == name_str: return node
	for child in node.get_children():
		var res = _find_node_by_name(child, name_str)
		if res: return res
	return null
