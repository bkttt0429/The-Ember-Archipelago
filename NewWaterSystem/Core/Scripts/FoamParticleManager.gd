class_name FoamParticleManager
extends Node3D

@export var water_manager: OceanWaterManager
@export var particle_count: int = 1000
@export var particle_size: float = 1.0
@export var foam_texture: Texture2D

var foam_multimesh: MultiMesh
var mesh_instance: MultiMeshInstance3D
var particles = [] # Array of Dictionary: {pos: Vector3, vel: Vector3, age: float, lifetime: float}

# Physics constants
const GRAVITY = -9.81
const DRAG = 0.5
const BUOYANCY = 12.0 # Slightly higher to float quickly
const MAX_LIFETIME = 3.0

func _ready():
	_setup_multimesh()

func _setup_multimesh():
	# Clean up logic
	if mesh_instance:
		mesh_instance.queue_free()
	
	mesh_instance = MultiMeshInstance3D.new()
	mesh_instance.name = "FoamMultiMesh"
	add_child(mesh_instance)
	
	foam_multimesh = MultiMesh.new()
	foam_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	foam_multimesh.use_colors = true # Use color for alpha/fade
	foam_multimesh.use_custom_data = true # Use custom data for age/randomness
	foam_multimesh.instance_count = particle_count
	foam_multimesh.visible_instance_count = 0
	
	# QuadMesh for billboard particles
	var mesh = QuadMesh.new()
	mesh.size = Vector2(particle_size, particle_size)
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = foam_texture
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Emissive look like standard foam
	# Optional: proximity fade for softness
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.5
	mat.distance_fade_max_distance = 2.0
	
	mesh.material = mat
	# Assign the mesh to the MultiMesh resource
	foam_multimesh.mesh = mesh
	
	# Assign the MultiMesh resource to the Instance
	mesh_instance.multimesh = foam_multimesh

func _physics_process(delta):
	if not water_manager: return
	
	_spawn_particles(delta)
	_update_particles(delta)
	_render_particles()

func _spawn_particles(_delta):
	# Only spawn if we have capacity
	if particles.size() >= particle_count: return
	
	# Get breaking points from WaterManager
	# Limit density to save perf: Scan 16x16 grid
	var breaking_points = water_manager.get_breaking_wave_positions(16)
	
	for i in range(breaking_points.size()):
		if particles.size() >= particle_count: break
		
		# Probability check to scatter them
		if randf() > 0.3: continue
		
		var pt = breaking_points[i]
		
		# Create new particle
		# Initial velocity: Add some chaos + upward splash
		var vel = Vector3((randf() - 0.5) * 2.0, 3.0 + randf() * 2.0, (randf() - 0.5) * 2.0)
		
		particles.append({
			"pos": pt + Vector3(0, 0.2, 0), # Start slightly above surface
			"vel": vel,
			"age": 0.0,
			"lifetime": 1.5 + randf() * 1.5, # 1.5 - 3.0s
			"scale": 1.0 + randf() * 0.5
		})

func _update_particles(delta):
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p.age += delta
		
		if p.age >= p.lifetime:
			particles.remove_at(i)
			continue
			
		# Physics
		p.vel.y += GRAVITY * delta
		
		# Drag
		p.vel.x -= p.vel.x * DRAG * delta
		p.vel.z -= p.vel.z * DRAG * delta
		
		# Move
		p.pos += p.vel * delta
		
		# Water Interaction
		var water_height = water_manager.get_wave_height_at(p.pos)
		if p.pos.y < water_height:
			# Buoyancy override
			p.pos.y = water_height # Stick to surface
			p.vel.y += BUOYANCY * delta # Float up
			p.vel.y *= 0.5 # Damping when hitting water
			
			# Add surface velocity? (Optional)
			# Stick to surface more
			p.pos.y = lerp(p.pos.y, water_height, 0.5)

func _render_particles():
	if not foam_multimesh: return
	
	var count = particles.size()
	foam_multimesh.visible_instance_count = count
	
	for i in range(count):
		var p = particles[i]
		
		# Transform: Position
		var t = Transform3D()
		t.origin = p.pos
		# Scale based on age (fade in/out)
		var life_pct = p.age / p.lifetime
		var scale_val = (sin(life_pct * PI) * 0.8 + 0.2) * p.scale
		t = t.scaled(Vector3(scale_val, scale_val, scale_val))
		
		foam_multimesh.set_instance_transform(i, t)
		
		# Color: Fade alpha
		var alpha = smoothstep(1.0, 0.8, life_pct) # Fade out at end
		foam_multimesh.set_instance_color(i, Color(1, 1, 1, alpha))
