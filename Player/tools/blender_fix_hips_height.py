# Blender Python 腳本 - 修正 Hips 高度
# 使用方法：
# 1. 打開 Blender
# 2. 進入 Scripting 工作區
# 3. 新建文字檔，貼上此代碼
# 4. 點擊 "Run Script"

import bpy
import os

# FBX 檔案路徑（正確路徑）
FBX_FILES = [
    r"D:\Game\Ember_of_Star_Islands\Player\assets\characters\player\motion\mx\Idle\Run To Stop.fbx",
    r"D:\Game\Ember_of_Star_Islands\Player\assets\characters\player\motion\mx\Idle\Stop Walking.fbx",
]

# 目標 Hips Y 位置（設為 0）
TARGET_HIPS_Y = 0.0

def fix_hips_height(fbx_path: str, target_y: float) -> bool:
    """修正單個 FBX 的 Hips Y 值"""
    
    # 清空場景
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    # 導入 FBX
    if not os.path.exists(fbx_path):
        print(f"ERROR: File not found: {fbx_path}")
        return False
    
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    print(f"\n=== Processing: {os.path.basename(fbx_path)} ===")
    
    # 找到 Armature
    armature = None
    for obj in bpy.data.objects:
        if obj.type == 'ARMATURE':
            armature = obj
            break
    
    if not armature or not armature.animation_data or not armature.animation_data.action:
        print("ERROR: No armature or animation found")
        return False
    
    action = armature.animation_data.action
    
    # 找到 Hips 的 Location Y 曲線
    hips_y_curve = None
    for fcurve in action.fcurves:
        if "Hips" in fcurve.data_path and "location" in fcurve.data_path and fcurve.array_index == 1:
            hips_y_curve = fcurve
            break
    
    if not hips_y_curve:
        print("ERROR: Hips location Y curve not found")
        return False
    
    # 計算偏移量（第一幀的 Y 值與目標的差異）
    first_y = hips_y_curve.keyframe_points[0].co[1]
    offset = target_y - first_y
    
    print(f"  First frame Y: {first_y:.4f}")
    print(f"  Target Y: {target_y:.4f}")
    print(f"  Offset: {offset:.4f}")
    
    # 應用偏移到所有 keyframes
    for kp in hips_y_curve.keyframe_points:
        kp.co[1] += offset
    
    print(f"  Applied offset to {len(hips_y_curve.keyframe_points)} keyframes")
    
    # 備份原檔案
    backup_path = fbx_path.replace(".fbx", "_backup.fbx")
    if not os.path.exists(backup_path):
        import shutil
        shutil.copy2(fbx_path, backup_path)
        print(f"  Backup: {os.path.basename(backup_path)}")
    
    # 選擇 Armature
    bpy.ops.object.select_all(action='DESELECT')
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    
    # 導出
    bpy.ops.export_scene.fbx(
        filepath=fbx_path,
        use_selection=True,
        bake_anim=True,
        bake_anim_use_all_actions=False,
        bake_anim_use_nla_strips=False,
        add_leaf_bones=False,
    )
    
    print(f"  Exported: {os.path.basename(fbx_path)}")
    return True

# 主程序
print("\n" + "="*50)
print("Blender Hips Height Fix Script")
print("="*50)

success_count = 0
for fbx_path in FBX_FILES:
    if fix_hips_height(fbx_path, TARGET_HIPS_Y):
        success_count += 1

print("\n" + "="*50)
print(f"Done! Fixed {success_count}/{len(FBX_FILES)} files")
print("="*50)
