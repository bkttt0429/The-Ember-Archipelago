@tool
extends EditorScript

func _run() -> void:
    var scene_path = "res://Player/test/PlayerCapsuleTest.tscn"
    var p_scene = load(scene_path) as PackedScene
    if not p_scene:
        print("Failed to load scene")
        return
        
    var root = p_scene.instantiate()
    var player = root.get_node("Player")
    var skeleton = player.get_node("Visuals/Human/Armature/GeneralSkeleton")
    var systems = player.get_node("Systems")
    var foot_ik = systems.get_node("SimpleFootIK")
    
    # 增加 LookAt Targets
    var left_lookat = Marker3D.new()
    left_lookat.name = "LeftLookAtTarget"
    player.add_child(left_lookat)
    left_lookat.owner = root
    
    var right_lookat = Marker3D.new()
    right_lookat.name = "RightLookAtTarget"
    player.add_child(right_lookat)
    right_lookat.owner = root
    
    # 增加 LookAt Modifiers
    var left_mod = LookAtModifier3D.new()
    left_mod.name = "LeftFootLookAt"
    left_mod.bone_name = "LeftFoot"
    left_mod.target_node = skeleton.get_path_to(left_lookat)
    left_mod.use_secondary_axis = true
    left_mod.secondary_axis = Vector3.AXIS_Y
    left_mod.primary_axis = Vector3.AXIS_Z
    skeleton.add_child(left_mod)
    left_mod.owner = root
    
    var right_mod = LookAtModifier3D.new()
    right_mod.name = "RightFootLookAt"
    right_mod.bone_name = "RightFoot"
    right_mod.target_node = skeleton.get_path_to(right_lookat)
    right_mod.use_secondary_axis = true
    right_mod.secondary_axis = Vector3.AXIS_Y
    right_mod.primary_axis = Vector3.AXIS_Z
    skeleton.add_child(right_mod)
    right_mod.owner = root
    
    # 配接 SimpleFootIK
    foot_ik.left_lookat_target = left_lookat
    foot_ik.right_lookat_target = right_lookat
    foot_ik.left_lookat_modifier = left_mod
    foot_ik.right_lookat_modifier = right_mod
    
    var packed = PackedScene.new()
    packed.pack(root)
    ResourceSaver.save(packed, scene_path)
    print("Injected LookAt nodes successfully.")
