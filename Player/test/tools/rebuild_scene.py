"""
Generate a clean PlayerCapsuleTest.tscn from scratch.
Based on PlayerTest.tscn obstacle layout + SimpleCapsuleMove.gd requirements.
"""

# ============================================================
# The scene we are generating requires:
#   @onready var anim_tree: AnimationTree = $AnimationTree
#   @onready var anim_player: AnimationPlayer = $AnimationPlayer
#   @onready var ground_ray: RayCast3D = $GroundRay
#   @onready var visuals_node: Node3D = $Visuals/Human
#   @onready var platform_forward_ray: RayCast3D = $PlatformForwardRay
#   @onready var platform_up_ray: RayCast3D = $PlatformUpRay
#   @onready var platform_land_ray: RayCast3D = $PlatformLandRay
#
# IK child nodes under the Skeleton3D (injected via [editable]):
#   Player_Visuals_Human_Skeleton3D#RightLegIK  (TwoBoneIK3D)
#   Player_Visuals_Human_Skeleton3D#LeftLegIK   (TwoBoneIK3D)
#   Player_Visuals_Human_Skeleton3D#RightFootLookAt (LookAtModifier3D)
#   Player_Visuals_Human_Skeleton3D#LeftFootLookAt  (LookAtModifier3D)
#
# SimpleFootIK requires:
#   skeleton = NodePath("../../Visuals/Human/GeneralSkeleton")
#   left_target = NodePath("../../LeftFootTarget")
#   right_target = NodePath("../../RightFootTarget")
#   left_ik = NodePath("../../Visuals/Human/GeneralSkeleton/Player_Visuals_Human_Skeleton3D#LeftLegIK")
#   right_ik = NodePath("../../Visuals/Human/GeneralSkeleton/Player_Visuals_Human_Skeleton3D#RightLegIK")
# ============================================================

scene_content = r"""[gd_scene format=3 uid="uid://bplayercapsuletest"]

[ext_resource type="Script" uid="uid://b37lb8joo25hw" path="res://Player/test/SimpleCapsuleMove.gd" id="1_script"]
[ext_resource type="PackedScene" uid="uid://s7dri8iysrrc" path="res://Assets/3D/Characters/Player/Human.fbx" id="2_model"]
[ext_resource type="AnimationLibrary" uid="uid://bmit6ovhoatey" path="res://Player/animations/movement.res" id="3_anim_lib"]
[ext_resource type="Script" uid="uid://cflryku53lafx" path="res://Player/systems/SimpleFootIK.gd" id="8_s1rgi"]
[ext_resource type="Resource" path="res://Player/test/default_movement.tres" id="15_movement_data"]

[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_sky"]

[sub_resource type="Sky" id="Sky_main"]
sky_material = SubResource("ProceduralSkyMaterial_sky")

[sub_resource type="Environment" id="Environment_main"]
background_mode = 2
sky = SubResource("Sky_main")
ambient_light_source = 3
ambient_light_energy = 0.5
tonemap_mode = 2
glow_enabled = true

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_player"]
radius = 0.4
height = 1.8

[sub_resource type="WorldBoundaryShape3D" id="WorldBoundaryShape3D_floor"]

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_floor"]
albedo_color = Color(0.35, 0.35, 0.35, 1)
metallic = 0.0
roughness = 0.9

[sub_resource type="PlaneMesh" id="PlaneMesh_floor"]
size = Vector2(100, 100)
material = SubResource("StandardMaterial3D_floor")

[sub_resource type="BoxShape3D" id="BoxShape3D_obstacle"]
size = Vector3(1, 1, 1)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_blue"]
albedo_color = Color(0.18, 0.44, 0.78, 1)

[sub_resource type="BoxMesh" id="BoxMesh_obstacle"]
size = Vector3(1, 1, 1)
material = SubResource("StandardMaterial3D_blue")

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_orange"]
albedo_color = Color(0.87, 0.42, 0.12, 1)

[sub_resource type="BoxMesh" id="BoxMesh_obstacle_tall"]
size = Vector3(2, 1.5, 2)
material = SubResource("StandardMaterial3D_orange")

[sub_resource type="BoxShape3D" id="BoxShape3D_obstacle_tall"]
size = Vector3(2, 1.5, 2)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_green"]
albedo_color = Color(0.22, 0.68, 0.3, 1)

[sub_resource type="BoxMesh" id="BoxMesh_stair"]
size = Vector3(2.5, 0.25, 0.5)
material = SubResource("StandardMaterial3D_green")

[sub_resource type="BoxShape3D" id="BoxShape3D_stair"]
size = Vector3(2.5, 0.25, 0.5)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_ramp"]
albedo_color = Color(0.75, 0.72, 0.22, 1)

[sub_resource type="BoxMesh" id="BoxMesh_ramp"]
size = Vector3(3, 0.25, 4)
material = SubResource("StandardMaterial3D_ramp")

[sub_resource type="BoxShape3D" id="BoxShape3D_ramp"]
size = Vector3(3, 0.25, 4)

[sub_resource type="SphereShape3D" id="SphereShape3D_foot"]
radius = 0.1

[sub_resource type="SphereMesh" id="SphereMesh_debug"]
radius = 0.05
height = 0.1

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_debug"]
albedo_color = Color(1, 0, 1, 1)
disable_receive_shadows = true

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_idle"]
animation = &"movement/ual_Crouch_Idle"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_fwd"]
animation = &"movement/Crouch_Walk_Forward"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_bwd"]
animation = &"movement/Crouch_Walk_Backward"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_left"]
animation = &"movement/Crouch_Walk_Left"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_right"]
animation = &"movement/Crouch_Walk_Right"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_fwd_left"]
animation = &"movement/Crouch_Walk_Forward_Left"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_fwd_right"]
animation = &"movement/Crouch_Walk_Forward_Right"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_bwd_left"]
animation = &"movement/Crouch_Walk_Backward_Left"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_bwd_right"]
animation = &"movement/Crouch_Walk_Backward_Right"

[sub_resource type="AnimationNodeAnimation" id="anim_idle"]
animation = &"movement/ual_Idle"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_f"]
animation = &"movement/ual_WalkForward"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_b"]
animation = &"movement/ual_WalkBackward"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_l"]
animation = &"movement/ual_WalkLeft"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_r"]
animation = &"movement/ual_WalkRight"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_fl"]
animation = &"movement/ual_WalkForwardLeft"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_fr"]
animation = &"movement/ual_WalkForwardRight"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_bl"]
animation = &"movement/ual_WalkBackwardLeft"

[sub_resource type="AnimationNodeAnimation" id="anim_walk_br"]
animation = &"movement/ual_WalkBackwardRight"

[sub_resource type="AnimationNodeAnimation" id="anim_run_f"]
animation = &"movement/ual_RunForward"

[sub_resource type="AnimationNodeAnimation" id="anim_run_b"]
animation = &"movement/ual_RunBackward"

[sub_resource type="AnimationNodeAnimation" id="anim_run_l"]
animation = &"movement/ual_RunLeft"

[sub_resource type="AnimationNodeAnimation" id="anim_run_r"]
animation = &"movement/ual_RunRight"

[sub_resource type="AnimationNodeAnimation" id="anim_run_fl"]
animation = &"movement/ual_RunForwardLeft"

[sub_resource type="AnimationNodeAnimation" id="anim_run_fr"]
animation = &"movement/ual_RunForwardRight"

[sub_resource type="AnimationNodeAnimation" id="anim_run_bl"]
animation = &"movement/ual_RunBackwardLeft"

[sub_resource type="AnimationNodeAnimation" id="anim_run_br"]
animation = &"movement/ual_RunBackwardRight"

[sub_resource type="AnimationNodeBlend2" id="blend2_stance"]

[sub_resource type="AnimationNodeBlendSpace2D" id="blendspace_crouch_movement"]
blend_mode = 2
triangles = PackedInt32Array(6, 0, 1, 0, 6, 7, 1, 2, 6, 2, 3, 6, 3, 4, 6, 4, 5, 6, 5, 6, 7, 6, 7, 8)
points = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(0, 0)]
values/0 = SubResource("anim_crouch_bwd_left")
values/1 = SubResource("anim_crouch_bwd")
values/2 = SubResource("anim_crouch_bwd_right")
values/3 = SubResource("anim_crouch_right")
values/4 = SubResource("anim_crouch_fwd_right")
values/5 = SubResource("anim_crouch_fwd")
values/6 = SubResource("anim_crouch_fwd_left")
values/7 = SubResource("anim_crouch_left")
values/8 = SubResource("anim_crouch_idle")

[sub_resource type="AnimationNodeBlendSpace2D" id="blendspace_stand_movement"]
blend_mode = 2
triangles = PackedInt32Array(6, 0, 1, 0, 6, 7, 1, 2, 6, 2, 3, 6, 3, 4, 6, 4, 5, 6, 5, 6, 7, 6, 7, 8)
points = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(0, 0)]
values/0 = SubResource("anim_walk_bl")
values/1 = SubResource("anim_walk_b")
values/2 = SubResource("anim_walk_br")
values/3 = SubResource("anim_walk_r")
values/4 = SubResource("anim_walk_fr")
values/5 = SubResource("anim_walk_f")
values/6 = SubResource("anim_walk_fl")
values/7 = SubResource("anim_walk_l")
values/8 = SubResource("anim_idle")

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_turn_left"]
animation = &"movement/Crouch_Turn_Left"

[sub_resource type="AnimationNodeAnimation" id="anim_crouch_turn_right"]
animation = &"movement/Crouch_Turn_Right"

[sub_resource type="AnimationNodeAnimation" id="anim_jump_backward"]
animation = &"movement/Jump_Backward"

[sub_resource type="AnimationNodeAnimation" id="anim_jump_land"]
animation = &"movement/ual_Jump_Land"

[sub_resource type="AnimationNodeAnimation" id="anim_jump_loop"]
animation = &"movement/ual_Jump"

[sub_resource type="AnimationNodeAnimation" id="anim_jump_standing"]
animation = &"movement/Jump_Standing"

[sub_resource type="AnimationNodeAnimation" id="anim_jump_standing_alt"]
animation = &"movement/Jump_Standing_Alt"

[sub_resource type="AnimationNodeAnimation" id="anim_jump_start"]
animation = &"movement/ual_Jump_Start"

[sub_resource type="AnimationNodeBlendTree" id="blendtree_locomotion"]
graph_offset = Vector2(-1262.4, -131.27)
nodes/crouch/node = SubResource("blend2_stance")
nodes/crouch/position = Vector2(-420, -20)
nodes/crouch/size = Vector2(140, 56)
nodes/movement/node = SubResource("blendspace_stand_movement")
nodes/movement/position = Vector2(-420, 120)
nodes/movement/size = Vector2(140, 56)
nodes/output/position = Vector2(-20, 0)
nodes/Blend2/node = SubResource("blend2_stance")
nodes/Blend2/position = Vector2(-220, 0)
node_connections = [&"output", 0, &"Blend2", &"Blend2", 0, &"movement", &"Blend2", 1, &"blendspace_crouch_movement"]

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_start"]
xfade_time = 0.1
priority = 0

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_jump"]
switch_mode = 1
xfade_time = 0.2

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_jump_oneshot"]
switch_mode = 1
advance_condition = &"jump"
xfade_time = 0.15

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_fall"]
switch_mode = 1
advance_condition = &"falling"
xfade_time = 0.3

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_land"]
switch_mode = 1
advance_condition = &"landed"
xfade_time = 0.1

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_ground"]
switch_mode = 1
advance_condition = &"grounded"
xfade_time = 0.2

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_oneshot_to_ground"]
switch_mode = 1
advance_condition = &"grounded"
xfade_time = 0.3

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_turn_left"]
switch_mode = 1
advance_condition = &"turn_left"
xfade_time = 0.1

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_turn_right"]
switch_mode = 1
advance_condition = &"turn_right"
xfade_time = 0.1

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_turn_to_movement"]
xfade_time = 0.2

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_backward_to_ground"]
switch_mode = 1
advance_condition = &"grounded"
xfade_time = 0.25

[sub_resource type="AnimationNodeStateMachineTransition" id="trans_to_jump_backward"]
switch_mode = 1
advance_condition = &"falling"
xfade_time = 0.15

[sub_resource type="AnimationNodeStateMachine" id="root_state_machine"]
states/movement/node = SubResource("blendtree_locomotion")
states/movement/position = Vector2(-100, 0)
states/jump_start/node = SubResource("anim_jump_start")
states/jump_start/position = Vector2(200, -200)
states/jump_oneshot/node = SubResource("anim_jump_standing")
states/jump_oneshot/position = Vector2(200, -350)
states/jump_loop/node = SubResource("anim_jump_loop")
states/jump_loop/position = Vector2(400, -200)
states/jump_land/node = SubResource("anim_jump_land")
states/jump_land/position = Vector2(600, -200)
states/jump_backward/node = SubResource("anim_jump_backward")
states/jump_backward/position = Vector2(200, -500)
states/turn_left/node = SubResource("anim_crouch_turn_left")
states/turn_left/position = Vector2(-100, 200)
states/turn_right/node = SubResource("anim_crouch_turn_right")
states/turn_right/position = Vector2(-100, 350)
transitions = [&"Start", &"movement", SubResource("trans_start"), &"movement", &"jump_start", SubResource("trans_to_jump"), &"movement", &"jump_oneshot", SubResource("trans_to_jump_oneshot"), &"movement", &"jump_loop", SubResource("trans_to_fall"), &"movement", &"jump_backward", SubResource("trans_to_jump_backward"), &"jump_start", &"jump_loop", SubResource("trans_to_jump"), &"jump_loop", &"jump_land", SubResource("trans_to_land"), &"jump_land", &"movement", SubResource("trans_to_ground"), &"jump_oneshot", &"movement", SubResource("trans_oneshot_to_ground"), &"jump_backward", &"movement", SubResource("trans_backward_to_ground"), &"movement", &"turn_left", SubResource("trans_to_turn_left"), &"movement", &"turn_right", SubResource("trans_to_turn_right"), &"turn_left", &"movement", SubResource("trans_turn_to_movement"), &"turn_right", &"movement", SubResource("trans_turn_to_movement")]
start_node = &"movement"

[node name="CapsuleTest" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_main")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(-0.866025, -0.433013, 0.25, 0, 0.5, 0.866025, -0.5, 0.75, -0.433013, 0, 8, 0)
shadow_enabled = true
directional_shadow_mode = 2

[node name="Floor" type="StaticBody3D" parent="."]

[node name="FloorCollision" type="CollisionShape3D" parent="Floor"]
shape = SubResource("WorldBoundaryShape3D_floor")

[node name="FloorMesh" type="MeshInstance3D" parent="Floor"]
mesh = SubResource("PlaneMesh_floor")

[node name="Obstacles" type="Node3D" parent="."]

[node name="StepLow" type="StaticBody3D" parent="Obstacles"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0.25, 0)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/StepLow"]
mesh = SubResource("BoxMesh_obstacle")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/StepLow"]
shape = SubResource("BoxShape3D_obstacle")

[node name="StepMed" type="StaticBody3D" parent="Obstacles"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0.5, -3)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/StepMed"]
mesh = SubResource("BoxMesh_obstacle")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/StepMed"]
shape = SubResource("BoxShape3D_obstacle")

[node name="StepHigh" type="StaticBody3D" parent="Obstacles"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 0.75, -6)
scale = Vector3(2, 1.5, 2)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/StepHigh"]
mesh = SubResource("BoxMesh_obstacle_tall")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/StepHigh"]
shape = SubResource("BoxShape3D_obstacle_tall")

[node name="Ramp" type="StaticBody3D" parent="Obstacles"]
transform = Transform3D(-0.9993619, -0.017859668, 0.030933836, 0, 0.8660251, 0.50000006, -0.03571934, 0.499681, -0.86547244, -4.5, 0, 0)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/Ramp"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
mesh = SubResource("BoxMesh_ramp")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/Ramp"]
shape = SubResource("BoxShape3D_ramp")

[node name="Stairs" type="Node3D" parent="Obstacles"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 3)

[node name="Step1" type="StaticBody3D" parent="Obstacles/Stairs"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, 0)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/Stairs/Step1"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
mesh = SubResource("BoxMesh_stair")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/Stairs/Step1"]
shape = SubResource("BoxShape3D_stair")

[node name="Step2" type="StaticBody3D" parent="Obstacles/Stairs"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.3, -0.5)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/Stairs/Step2"]
mesh = SubResource("BoxMesh_stair")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/Stairs/Step2"]
shape = SubResource("BoxShape3D_stair")

[node name="Step3" type="StaticBody3D" parent="Obstacles/Stairs"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, -1)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/Stairs/Step3"]
mesh = SubResource("BoxMesh_stair")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/Stairs/Step3"]
shape = SubResource("BoxShape3D_stair")

[node name="Step4" type="StaticBody3D" parent="Obstacles/Stairs"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.7, -1.5)

[node name="Mesh" type="MeshInstance3D" parent="Obstacles/Stairs/Step4"]
mesh = SubResource("BoxMesh_stair")

[node name="Collision" type="CollisionShape3D" parent="Obstacles/Stairs/Step4"]
shape = SubResource("BoxShape3D_stair")

[node name="Player" type="CharacterBody3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, 0)
script = ExtResource("1_script")
movement_data = ExtResource("15_movement_data")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.9, 0)
shape = SubResource("CapsuleShape3D_player")

[node name="GroundRay" type="RayCast3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, 0)
target_position = Vector3(0, -1.5, 0)

[node name="PlatformForwardRay" type="RayCast3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, -0.5)
target_position = Vector3(0, 0, -1.5)
debug_shape_custom_color = Color(1, 0.5, 0, 1)

[node name="PlatformUpRay" type="RayCast3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.8, -1)
target_position = Vector3(0, 1.5, 0)
debug_shape_custom_color = Color(0, 0.5, 1, 1)

[node name="PlatformLandRay" type="RayCast3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3, -1)
target_position = Vector3(0, -3.5, 0)
debug_shape_custom_color = Color(1, 1, 0, 1)

[node name="RightFootShape" type="ShapeCast3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.12, 0.5, 0)
shape = SubResource("SphereShape3D_foot")
target_position = Vector3(0, -1.5, 0)
debug_shape_custom_color = Color(1, 0, 0, 1)

[node name="LeftFootShape" type="ShapeCast3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.12, 0.5, 0)
shape = SubResource("SphereShape3D_foot")
target_position = Vector3(0, -1.5, 0)
debug_shape_custom_color = Color(0, 1, 0, 1)

[node name="RightFootTarget" type="Marker3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.12, 0, 0)
visible = false

[node name="DebugSphereR" type="MeshInstance3D" parent="Player/RightFootTarget"]
mesh = SubResource("SphereMesh_debug")
surface_material_override/0 = SubResource("StandardMaterial3D_debug")

[node name="LeftFootTarget" type="Marker3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.12, 0, 0)
visible = false

[node name="DebugSphereL" type="MeshInstance3D" parent="Player/LeftFootTarget"]
mesh = SubResource("SphereMesh_debug")
surface_material_override/0 = SubResource("StandardMaterial3D_debug")

[node name="RightLookAtTarget" type="Marker3D" parent="Player"]
visible = false

[node name="LeftLookAtTarget" type="Marker3D" parent="Player"]
visible = false

[node name="RightKneePole" type="Marker3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.15, 0.9, -0.5)

[node name="LeftKneePole" type="Marker3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.15, 0.9, -0.5)

[node name="Systems" type="Node3D" parent="Player"]

[node name="SimpleFootIK" type="Node3D" parent="Player/Systems" node_paths=PackedStringArray("skeleton", "left_target", "right_target", "left_ik", "right_ik", "left_lookat_target", "right_lookat_target", "left_lookat_modifier", "right_lookat_modifier")]
script = ExtResource("8_s1rgi")
skeleton = NodePath("../../Visuals/Human/GeneralSkeleton")
left_target = NodePath("../../LeftFootTarget")
right_target = NodePath("../../RightFootTarget")
left_ik = NodePath("../../Visuals/Human/GeneralSkeleton/Player_Visuals_Human_Skeleton3D#LeftLegIK")
right_ik = NodePath("../../Visuals/Human/GeneralSkeleton/Player_Visuals_Human_Skeleton3D#RightLegIK")
left_lookat_target = NodePath("../../LeftLookAtTarget")
right_lookat_target = NodePath("../../RightLookAtTarget")
left_lookat_modifier = NodePath("../../Visuals/Human/GeneralSkeleton/Player_Visuals_Human_Skeleton3D#LeftFootLookAt")
right_lookat_modifier = NodePath("../../Visuals/Human/GeneralSkeleton/Player_Visuals_Human_Skeleton3D#RightFootLookAt")
enable_foot_rotation = false
debug_draw = false

[node name="Visuals" type="Node3D" parent="Player"]

[node name="Human" parent="Player/Visuals" instance=ExtResource("2_model")]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)

[node name="Player_Visuals_Human_Skeleton3D#RightLegIK" type="TwoBoneIK3D" parent="Player/Visuals/Human/GeneralSkeleton" parent_id_path=PackedInt32Array(934956750, 96331150) index="1"]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, -0.18778086, 0)
setting_count = 1
settings/0/target_node = NodePath("../../../../RightFootTarget")
settings/0/pole_node = NodePath("../../../../RightKneePole")
settings/0/root_bone_name = "RightUpperLeg"
settings/0/root_bone = 60
settings/0/middle_bone_name = "RightLowerLeg"
settings/0/middle_bone = 61
settings/0/pole_direction = 0
settings/0/end_bone_name = "RightFoot"
settings/0/end_bone = 62
settings/0/use_virtual_end = false
settings/0/extend_end_bone = false

[node name="Player_Visuals_Human_Skeleton3D#LeftLegIK" type="TwoBoneIK3D" parent="Player/Visuals/Human/GeneralSkeleton" parent_id_path=PackedInt32Array(934956750, 96331150) index="2"]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, -0.18778086, 0)
setting_count = 1
settings/0/target_node = NodePath("../../../../LeftFootTarget")
settings/0/pole_node = NodePath("../../../../LeftKneePole")
settings/0/root_bone_name = "LeftUpperLeg"
settings/0/root_bone = 55
settings/0/middle_bone_name = "LeftLowerLeg"
settings/0/middle_bone = 56
settings/0/pole_direction = 0
settings/0/end_bone_name = "LeftFoot"
settings/0/end_bone = 57
settings/0/use_virtual_end = false
settings/0/extend_end_bone = false

[node name="Player_Visuals_Human_Skeleton3D#RightFootLookAt" type="LookAtModifier3D" parent="Player/Visuals/Human/GeneralSkeleton" parent_id_path=PackedInt32Array(934956750, 96331150) index="3"]
influence = 0.0
target_node = NodePath("../../../../RightLookAtTarget")
bone_name = "RightFoot"
bone = 62

[node name="Player_Visuals_Human_Skeleton3D#LeftFootLookAt" type="LookAtModifier3D" parent="Player/Visuals/Human/GeneralSkeleton" parent_id_path=PackedInt32Array(934956750, 96331150) index="4"]
influence = 0.0
target_node = NodePath("../../../../LeftLookAtTarget")
bone_name = "LeftFoot"
bone = 57

[node name="AnimationTree" type="AnimationTree" parent="Player"]
root_node = NodePath("../Visuals/Human")
tree_root = SubResource("root_state_machine")
anim_player = NodePath("../AnimationPlayer")
active = true
parameters/conditions/falling = false
parameters/conditions/grounded = false
parameters/conditions/jump = false
parameters/conditions/landed = false
parameters/conditions/turn_left = false
parameters/conditions/turn_right = false
parameters/playback = AnimationNodeStateMachinePlayback.new()

[node name="AnimationPlayer" type="AnimationPlayer" parent="Player"]
root_node = NodePath("../Visuals/Human")
libraries/movement = ExtResource("3_anim_lib")

[node name="CameraMount" type="Node3D" parent="Player"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, 0)

[node name="SpringArm3D" type="SpringArm3D" parent="Player/CameraMount"]
transform = Transform3D(1, 0, 0, 0, 0.965926, 0.258819, 0, -0.258819, 0.965926, 0, 0, 0)
spring_length = 5.0
margin = 0.4

[node name="Camera3D" type="Camera3D" parent="Player/CameraMount/SpringArm3D"]
current = true
fov = 55.0

[editable path="Player/Visuals/Human"]
"""

output_path = r"D:\Game\Ember_of_Star_Islands\Player\test\PlayerCapsuleTest.tscn"

with open(output_path, "w", encoding="utf-8", newline="\n") as f:
    f.write(scene_content.lstrip("\n"))

print(f"✅ Scene generated successfully: {output_path}")
print(f"   Lines: {len(scene_content.splitlines())}")
