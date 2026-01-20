extends Node3D

@onready var mesh_instance: MeshInstance3D = $BarrelWaveMesh
@onready var particles: GPUParticles3D = $SprayParticles

var time: float = 0.0
var cycle_duration: float = 12.0 # 12秒一個循環

func _process(delta: float) -> void:
    time += delta
    var cycle_pos = fmod(time, cycle_duration) / cycle_duration
    
    # 定義波浪狀態曲線 (0~1)
    # 使用 Sine 曲線：平靜 -> 逐漸變大 -> 爆發 -> 平息
    var intensity = sin(cycle_pos * PI) # 0 -> 1 -> 0
    intensity = pow(intensity, 2.0) # 讓平靜期稍微長一點
    
    # 映射參數
    var target_height = lerp(0.5, 3.5, intensity) # 高度: 0.5m -> 3.5m
    var target_steepness = lerp(0.2, 1.2, intensity) # 陡度: 0.2 -> 1.2
    var target_curl = lerp(0.0, 2.5, smoothstep(0.4, 0.9, intensity)) # 捲曲力度: 只有大浪才捲
    
    # 應用到 Shader
    var mat: ShaderMaterial = mesh_instance.get_surface_override_material(0)
    if mat:
        mat.set_shader_parameter("wave_height", target_height)
        mat.set_shader_parameter("steepness", target_steepness)
        mat.set_shader_parameter("curl_force", target_curl)
        
    # 同步應用到粒子系統
    var part_mat: ShaderMaterial = particles.process_material
    if part_mat:
        part_mat.set_shader_parameter("wave_height", target_height)
        part_mat.set_shader_parameter("steepness", target_steepness)
        part_mat.set_shader_parameter("curl_force", target_curl)
