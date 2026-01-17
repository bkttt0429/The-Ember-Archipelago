class_name FoamParticleRenderer
extends MultiMeshInstance3D

## Efficiently renders foam particles using MultiMeshInstance3D

@export var max_particles: int = 2000
@export var foam_texture: Texture2D

var _shader_material: ShaderMaterial

func _ready():
	# Setup MultiMesh
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = max_particles
	multimesh.visible_instance_count = 0
	
	# QuadMesh for particles
	var q_mesh = QuadMesh.new()
	q_mesh.size = Vector2(1.5, 1.5) # Slightly larger
	multimesh.mesh = q_mesh
	
	# Setup Material
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = load("res://NewWaterSystem/Core/Shaders/Internal/FoamParticle.gdshader")
	
	# Default Noise if none (create a simple one on fly for robustness)
	if not foam_texture:
		var noise = FastNoiseLite.new()
		noise.seed = randi()
		noise.frequency = 0.05
		var noise_tex = NoiseTexture2D.new()
		noise_tex.width = 128
		noise_tex.height = 128
		noise_tex.noise = noise
		foam_texture = noise_tex
		
	_shader_material.set_shader_parameter("noise_texture", foam_texture)
	material_override = _shader_material

func update_particles(particles: Array):
	if not multimesh: return
	
	var count = min(particles.size(), max_particles)
	multimesh.visible_instance_count = count
	
	# Optimization Note: For extremely high counts (e.g. > 5000), 
	# modifying the MultiMesh buffer directly via PackingFloat32Array is faster.
	# For < 2000, GDScript loop is usually acceptable.
	
	for i in range(count):
		var p = particles[i]
		
		# Position
		var t = Transform3D()
		t.origin = p.position
		
		# Scale based on particle property
		var s = p.get("scale", 0.5)
		t.basis = Basis().scaled(Vector3(s, s, s))
		
		multimesh.set_instance_transform(i, t)
		
		# Custom Data: 
		# R (x) = Life normalized (age / lifetime)
		# G (y) = Random seed (for texture offset)
		# B (z) = Unused
		# A (w) = Unused
		
		var life_factor = clamp(p.age / p.lifetime, 0.0, 1.0)
		var rnd = float(i) * 0.1 # stable random per instance index
		
		multimesh.set_instance_custom_data(i, Color(life_factor, rnd, 0.0, 0.0))
