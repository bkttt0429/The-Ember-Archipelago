# Player Mixamo Animation Guide (Stride8)

## 1. Folder Layout

```
res://assets/characters/player/motion/mx/stride8/
```

## 2. File Naming

Format:

```
pc_mx_stride8_{dir}_{speed}.fbx
```

Direction tokens:

- f
- b
- l
- r
- fl
- fr
- bl
- br

Speed tokens:

- walk
- run

Example files:

- pc_mx_stride8_f_walk.fbx
- pc_mx_stride8_fr_walk.fbx
- pc_mx_stride8_bl_run.fbx

If you only have one speed tier, use:

```
pc_mx_stride8_{dir}_move.fbx
```

## 3. BlendTree2D Node Names

Recommended node naming for the BlendTree2D:

- locomotion_f
- locomotion_b
- locomotion_l
- locomotion_r
- locomotion_fl
- locomotion_fr
- locomotion_bl
- locomotion_br

If you use separate trees for walk/run, append suffixes:

- locomotion_f_walk
- locomotion_f_run

## 4. BlendTree2D Position Map

Use blend_position as:

- X: left (-1) to right (+1)
- Y: back (-1) to forward (+1)

Positions:

- f  -> (0, 1)
- b  -> (0, -1)
- l  -> (-1, 0)
- r  -> (1, 0)
- fl -> (-1, 1)
- fr -> (1, 1)
- bl -> (-1, -1)
- br -> (1, -1)

## 5. ECS Parameters (Minimal)

- move_vector (Vector2) -> BlendTree2D.blend_position
- speed (float) -> walk/run blend or playback speed
- is_combat (bool) -> StateMachine switch (Locomotion/Combat)
- is_airborne (bool) -> StateMachine switch (Air)
