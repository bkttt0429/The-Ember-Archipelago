@tool
extends MultiMeshInstance3D

## 渲染泡沫粒子的高效系統

@export var water_manager_path: NodePath
var water_manager: OceanWaterManager

var _particle_mesh: QuadMesh
var _particle_material: ShaderMaterial

func _ready():
    if not water_manager_path.is_empty():
        water_manager = get_node(water_manager_path)
    
    if not water_manager:
        water_manager = get_tree().get_first_node_in_group("WaterSystem_Managers")

    # 設置 Mesh
    _particle_mesh = QuadMesh.new()
    _particle_mesh.size = Vector2(0.5, 0.5)
    
    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.instance_count = 2000 # 最大粒子數
    multimesh.mesh = _particle_mesh
    
    # 創建 Billboard Material
    _particle_material = ShaderMaterial.new()
    _particle_material.shader = preload("res://NewWaterSystem/Core/Shaders/FoamParticle.gdshader")
    material_override = _particle_material
    
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta):
    if not water_manager: return
    if not "foam_particles" in water_manager: return
    
    var particles = water_manager.foam_particles
    var visible_count = min(particles.size(), multimesh.instance_count)
    multimesh.visible_instance_count = visible_count
    
    for i in range(visible_count):
        var p = particles[i]
        
        # Transform
        var t = Transform3D()
        t.origin = p.position
        
        # Scale（根據生命週期）
        var life_factor = 1.0 - (p.age / p.lifetime)
        var p_scale = p.get("scale", 1.0) * life_factor
        t = t.scaled(Vector3(p_scale, p_scale, p_scale))
        
        multimesh.set_instance_transform(i, t)

        
        # Custom Data（傳遞給 Shader）
        var velocity = p.get("velocity", Vector3.ZERO)
        var custom = Color(
            life_factor, # R: 生命係數
            velocity.length() / 10.0, # G: 速度（用於拉伸）
            0.0, 1.0
        )
        multimesh.set_instance_custom_data(i, custom)
