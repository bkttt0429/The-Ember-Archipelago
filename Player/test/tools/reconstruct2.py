import os
import re

tmp_path = r"D:\Game\Ember_of_Star_Islands\Player\test\PlayerCapsuleTest.tscn19502825648.tmp"
out_path = r"D:\Game\Ember_of_Star_Islands\Player\test\PlayerCapsuleTest.tscn"

known_block_1 = """[sub_resource type="BoxShape3D" id="climb_box_medium_shape"]
size = Vector3(2, 2, 2)

[sub_resource type="StandardMaterial3D" id="climb_box_medium_mat"]
albedo_color = Color(0.3, 0.5, 0.7, 1)

[sub_resource type="BoxMesh" id="climb_box_medium_mesh"]
size = Vector3(2, 2, 2)

[sub_resource type="BoxShape3D" id="climb_box_high_shape"]
size = Vector3(2, 2.5, 2)

[sub_resource type="StandardMaterial3D" id="climb_box_high_mat"]
albedo_color = Color(0.7, 0.4, 0.3, 1)

[sub_resource type="BoxMesh" id="climb_box_high_mesh"]
size = Vector3(2, 2.5, 2)

[sub_resource type="Resource" id="Resource_cr6ff"]
script = ExtResource("11_lkcna")

[node name="CapsuleTest" type="Node3D" unique_id="1258081994"]

[node name="Player" type="CharacterBody3D" parent="." unique_id="924444324"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.1647551, 0.10643661, -6.597088)
script = ExtResource("1_script")
movement_data = ExtResource("15_movement_data")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Player" unique_id="1392737534"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.9, 0)
shape = SubResource("CapsuleShape3D_1")

[node name="CapsuleMesh" type="MeshInstance3D" parent="Player" unique_id="1432619223"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.9, 0)
visible = false
mesh = SubResource("CapsuleMesh_1")

[node name="GroundRay" type="RayCast3D" parent="Player" unique_id="1268555944"]
target_position = Vector3(0, -1.2, 0)
debug_shape_custom_color = Color(0, 1, 0, 1)

[node name="PlatformForwardRay" type="RayCast3D" parent="Player" unique_id="427369079"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0)
target_position = Vector3(0, 0, -1.5)
debug_shape_custom_color = Color(1, 0.5, 0, 1)

[node name="PlatformUpRay" type="RayCast3D" parent="Player" unique_id="1872484923"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.8, -1)
target_position = Vector3(0, 1.5, 0)
debug_shape_custom_color = Color(0, 0.5, 1, 1)

[node name="PlatformLandRay" type="RayCast3D" parent="Player" unique_id="1397292986"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3, -1)
target_position = Vector3(0, -3.5, 0)
debug_shape_custom_color = Color(1, 1, 0, 1)

[node name="RightFootShape" type="ShapeCast3D" parent="Player" unique_id="1611996191"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.12, 0.5, 0)
shape = SubResource("FootShapeCastShape")
target_position = Vector3(0, -1.5, 0)
debug_shape_custom_color = Color(1, 0, 0, 1)

[node name="RightFootTarget" type="Marker3D" parent="Player" unique_id="1510996191"]
transform = Transform3D(1.0000001, 0, 1.4901161e-08, 0, 1, 0, -1.4901161e-08, 0, 1.0000001, 0.122312546, -0.15001658, 0.071210384)
visible = false

[node name="DebugSphere" type="MeshInstance3D" parent="Player/RightFootTarget" unique_id="1629723156"]
mesh = SubResource("DebugSphereMesh")
surface_material_override/0 = SubResource("DebugSphereMaterial")

[node name="LeftFootShape" type="ShapeCast3D" parent="Player" unique_id="1711996191"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.12, 0.5, 0)
shape = SubResource("FootShapeCastShape")
target_position = Vector3(0, -1.5, 0)
debug_shape_custom_color = Color(0, 0, 1, 1)

[node name="LeftFootTarget" type="Marker3D" parent="Player" unique_id="310785886"]
transform = Transform3D(1.0000002, 0, 1.4901161e-08, 0, 1, 0, -1.4901161e-08, 0, 1.0000002, -0.123945236, 0.030956626, 0.020782828)
visible = false

[node name="DebugSphere" type="MeshInstance3D" parent="Player/LeftFootTarget" unique_id="986370254"]
mesh = SubResource("DebugSphereMesh")
surface_material_override/0 = SubResource("DebugSphereMaterial")

[node name="RightLookAtTarget" type="Marker3D" parent="Player" unique_id="2081944116]
visible = false

[node name="LeftLookAtTarget" type="Marker3D" parent="Player" unique_id="1459132207]
visible = false

[node name="RightKneePole" type="Marker3D" parent="Player" unique_id="58177491"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.15, 0.8, -0.5)

[node name="LeftKneePole" type="Marker3D" parent="Player" unique_id="1109245816"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.15, 0.8, -0.5)

[node name="Systems" type="Node3D" parent="Player" unique_id="1410444321"]

[node name="SimpleFootIK" type="Node3D" parent="Player/Systems" unique_id="1746405158" node_paths=PackedStringArray("skeleton", "left_target", "right_target", "left_ik", "right_ik", "left_lookat_target", "right_lookat_target", "left_lookat_modifier", "right_lookat_modifier")]
script = ExtResource("8_s1rgi")
skeleton = NodePath("../../Visuals/Human/Armature/GeneralSkeleton")
left_target = NodePath("../../LeftFootTarget")
right_target = NodePath("../../RightFootTarget")
left_ik = NodePath("../../Visuals/Human/Armature/GeneralSkeleton/Player_Visuals_Human_GeneralSkeleton#LeftLegIK")
right_ik = NodePath("../../Visuals/Human/Armature/GeneralSkeleton/Player_Visuals_Human_GeneralSkeleton#RightLegIK")
left_lookat_target = NodePath("../../LeftLookAtTarget")
right_lookat_target = NodePath("../../RightLookAtTarget")
left_lookat_modifier = NodePath("../../Visuals/Human/Armature/GeneralSkeleton/Player_Visuals_Human_GeneralSkeleton#LeftFootLookAt")
right_lookat_modifier = NodePath("../../Visuals/Human/Armature/GeneralSkeleton/Player_Visuals_Human_GeneralSkeleton#RightFootLookAt")
ray_length = 1.0

[node name="Visuals" type="Node3D" parent="Player" unique_id="1222742778"]

[node name="Human" parent="Player/Visuals" unique_id="682676425" instance=ExtResource("2_model")]
transform = Transform3D(-1, 0, -8.742278e-08, 0, 1, 0, 8.742278e-08, 0, -1, 0, 0, 0)

[node name="Player_Visuals_Human_GeneralSkeleton#RightLegIK" type="TwoBoneIK3D" parent="Player/Visuals/Human/Armature/GeneralSkeleton" parent_id_path=PackedInt32Array(682676425, 109460344) index="1" unique_id="294152057"]
transform = Transform3D(-1, 0, 8.742278e-08, 0, 1, 0, -8.742278e-08, 0, -1, 0.16475567, -0.49371564, -6.4179144)
influence = 0.0
setting_count = 1
settings/0/target_node = NodePath("../../../../../../RightFootTarget")
settings/0/pole_node = NodePath("../../../../../../RightKneePole")
settings/0/root_bone_name = "RightUpperLeg"
settings/0/root_bone = 60
settings/0/middle_bone_name = "RightLowerLeg"
settings/0/middle_bone = 61
settings/0/pole_direction = 0
settings/0/end_bone_name = "RightFoot"
settings/0/end_bone = 62
settings/0/use_virtual_end = false
settings/0/extend_end_bone = false

[node name="Player_Visuals_Human_GeneralSkeleton#LeftLegIK" type="TwoBoneIK3D" parent="Player/Visuals/Human/Armature/GeneralSkeleton" parent_id_path=PackedInt32Array(682676425, 109460344) index="2" unique_id="480109093"]
transform = Transform3D(-1, 0, 8.742278e-08, 0, 1, 0, -8.742278e-08, 0, -1, 0.16475567, -0.49371564, -6.4179144)
influence = 0.0
setting_count = 1
settings/0/target_node = NodePath("../../../../../../LeftFootTarget")
settings/0/pole_node = NodePath("../../../../../../LeftKneePole")
settings/0/root_bone_name = "LeftUpperLeg"
settings/0/root_bone = 55
settings/0/middle_bone_name = "LeftLowerLeg"
settings/0/middle_bone = 56
settings/0/pole_direction = 0
settings/0/end_bone_name = "LeftFoot"
settings/0/end_bone = 57
settings/0/use_virtual_end = false
settings/0/extend_end_bone = false

[node name="Player_Visuals_Human_GeneralSkeleton#RightFootLookAt" type="LookAtModifier3D" parent="Player/Visuals/Human/Armature/GeneralSkeleton" parent_id_path=PackedInt32Array(682676425, 109460344) index="3" unique_id="1849281747"]
influence = 0.0
target_node = NodePath("../../../../../../RightLookAtTarget")
bone_name = "RightFoot"
bone = 62
primary_axis = 4
use_secondary_axis = true
secondary_axis = 1

[node name="Player_Visuals_Human_GeneralSkeleton#LeftFootLookAt" type="LookAtModifier3D" parent="Player/Visuals/Human/Armature/GeneralSkeleton" parent_id_path=PackedInt32Array(682676425, 109460344) index="4" unique_id="2591038471"]
influence = 0.0
target_node = NodePath("../../../../../../LeftLookAtTarget")
bone_name = "LeftFoot"
bone = 57
primary_axis = 4
use_secondary_axis = true
secondary_axis = 1

[node name="AnimationTree" type="AnimationTree" parent="Player" unique_id="1963687889"]
root_node = NodePath("../Visuals/Human")
tree_root = SubResource("root_state_machine")
anim_player = NodePath("../AnimationPlayer")
parameters/conditions/falling = false
parameters/conditions/grounded = false
parameters/conditions/jump = false
parameters/conditions/landed = false
parameters/conditions/turn_left = false
parameters/conditions/turn_right = false
parameters/movement/Blend2/blend_amount = 0.0
parameters/movement/crouch/blend_position = Vector2(-0.002272725, -0.0019960403)
parameters/movement/stand/blend_position = Vector2(0, 0)
"""

known_block_2 = """[node name="AnimationPlayer" type="AnimationPlayer" parent="Player" unique_id="1683661270"]
root_node = NodePath("../Visuals/Human")
libraries/movement = ExtResource("3_anim_lib")

[node name="CameraMount" type="Node3D" parent="Player" unique_id="363283514"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, 0)

[node name="SpringArm3D" type="SpringArm3D" parent="Player/CameraMount" unique_id="1955353752"]
transform = Transform3D(1, 0, 0, 0, 0.965926, 0.258819, 0, -0.258819, 0.965926, 0, 0, 0)
spring_length = 5.0
margin = 0.4

[node name="Camera3D" type="Camera3D" parent="Player/CameraMount/SpringArm3D" unique_id="1827793139"]
current = true
fov = 55.0

"""

with open(tmp_path, "r", encoding="utf-8") as f:
    text = f.read()

ext_11 = '[ext_resource type="Script" uid="uid://cx62ylh3okxqw" path="res://Player/test/movement_data.gd" id="11_lkcna"]'
ext_15 = '[ext_resource type="Resource" uid="uid://cy8jqu0l7l2bx" path="res://Player/test/default_movement.tres" id="15_movement_data"]'
ext_8 = '[ext_resource type="Script" uid="uid://cc1y0gysu2k0r" path="res://Player/systems/SimpleFootIK.gd" id="8_s1rgi"]'

sub_resources_missing = """[sub_resource type="SphereMesh" id="DebugSphereMesh"]
radius = 0.05
height = 0.1

[sub_resource type="StandardMaterial3D" id="DebugSphereMaterial"]
albedo_color = Color(1, 0, 1, 1)
disable_receive_shadows = true

[sub_resource type="SphereShape3D" id="FootShapeCastShape"]
radius = 0.1

"""

regex_header = re.compile(r'(.*?)(?=\[node name="CapsuleTest" type="Node3D" unique_id="\d+"\]|\[node name="CapsuleTest" type="Node3D" unique_id=\d+\])', re.DOTALL)
header_match = regex_header.search(text)
header = header_match.group(1) if header_match else ""

regex_map = re.compile(r'(\[node name="Floor".*)', re.DOTALL)
map_match = regex_map.search(text)
map_nodes = map_match.group(1) if map_match else ""

lines = header.splitlines()
ext_idx = 1
for i, line in enumerate(lines):
    if line.startswith('[ext_resource'):
        ext_idx = i + 1

lines.insert(ext_idx, ext_8)
lines.insert(ext_idx, ext_15)
lines.insert(ext_idx, ext_11)

new_header = "\\n".join(lines) + "\\n\\n" + sub_resources_missing

full_text = new_header + known_block_1 + "\\n" + known_block_2 + map_nodes + "\\n"

# Remove duplicate quotes in unique_id
full_text = re.sub(r'unique_id="(\d+)"', r'unique_id=\\1', full_text)

with open(out_path, "w", encoding="utf-8") as f:
    f.write(full_text)

print(f"Reconstructed {len(full_text.splitlines())} lines into {out_path}.")
