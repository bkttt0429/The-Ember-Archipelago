import re
import os

FILE_PATH = r"d:\Game\Ember_of_Star_Islands\Player\test\SimpleCapsuleMove.gd"

# Variables to replace mapped to their new object paths
REPLACEMENTS = {
    # GroundData (ground)
    "_was_on_floor": "ground.was_on_floor",
    "_step_down_snapped": "ground.step_down_snapped",
    "_snapped_to_stairs_last_frame": "ground.snapped_to_stairs_last_frame",
    "ground_info": "ground.info",

    # AirData (air)
    "_jump_phase": "air.jump_phase",
    "_jump_buffer_timer": "air.jump_buffer_timer",
    "_jump_hold_timer": "air.jump_hold_timer",
    "_jump_grace_timer": "air.jump_grace_timer",
    "_jump_start_timer": "air.jump_start_timer",
    "_is_ascending": "air.is_ascending",
    "_jump_to_type": "air.jump_to_type",
    "_air_time": "air.air_time",
    "_fall_velocity_peak": "air.fall_velocity_peak",
    "_landing_timer": "air.landing_timer",
    "_post_landing_blend_timer": "air.post_landing_blend_timer",
    "_coyote_timer": "air.coyote_timer",

    # StairData (stair)
    "_on_stairs": "stair.on_stairs",
    "_stairs_ascending": "stair.ascending",
    "_stair_grace_timer": "stair.grace_timer",
    "_stair_blend_weight": "stair.blend_weight",
    "_stair_anim_exit_timer": "stair.anim_exit_timer",
    "_stair_params_valid": "stair.params_valid",
    "_stair_step_height_measured": "stair.step_height_measured",
    "_stair_step_depth": "stair.step_depth",
    "_stair_base_pos": "stair.base_pos",
    "_stair_dir_xz": "stair.dir_xz",
    "_stair_root_motion_active": "stair.root_motion_active",
    "_stair_rm_velocity": "stair.rm_velocity",
    "_step_up_offset": "stair.step_up_offset",
    "_post_step_up_cooldown": "stair.post_step_up_cooldown",
    "_was_on_stairs_ascending": "stair.was_ascending",
    "_step_up_visual_debt": "stair.step_up_visual_debt",
    "_stair_dir_committed": "stair.dir_committed",
    "_stair_committed_ascending": "stair.committed_ascending",
    "_stair_dir_commit_timer": "stair.dir_commit_timer",

    # ClimbData (climb)
    "_climb_state": "climb.state",
    "_climb_grab_point": "climb.grab_point",
    "_climb_surface_normal": "climb.surface_normal",
    "_climb_ledge_height": "climb.ledge_height",
    "_mantle_root_motion_active": "climb.mantle_root_motion_active",
    "_mantle_start_pos": "climb.mantle_start_pos",
    "_mantle_target_y": "climb.mantle_target_y",
    "_mantle_height_compensation": "climb.mantle_height_compensation",
    "_mantle_elapsed": "climb.mantle_elapsed",
    "_mantle_duration": "climb.mantle_duration",
    "_mantle_wall_point": "climb.mantle_wall_point",
    "_mantle_rm_loaded": "climb.mantle_rm_loaded",
    "_climb_wall_point": "climb.wall_point",
    "_is_shimmying": "climb.is_shimmying",
    "_shimmy_direction": "climb.shimmy_direction",
    "_shimmy_target_pos": "climb.shimmy_target_pos",

    # AnimState (anim)
    "_gait": "anim.gait",
    "_motion_state": "anim.motion_state",
}

# The class definitions to inject
CLASSES_DEF = """# ==================== State Structs (Phase 2 Data Driven) ====================
class GroundData:
	var info: Dictionary = {"is_grounded": false, "surface_normal": Vector3.UP, "collision_point": Vector3.ZERO, "distance": 0.0, "collider": null}
	var was_on_floor: bool = true
	var step_down_snapped: bool = false
	var snapped_to_stairs_last_frame: bool = false

class AirData:
	var air_time: float = 0.0
	var fall_velocity_peak: float = 0.0
	var landing_timer: float = 0.0
	var post_landing_blend_timer: float = 0.0
	var coyote_timer: float = 0.0
	var jump_grace_timer: float = 0.0
	var jump_buffer_timer: float = 0.0
	var jump_hold_timer: float = 0.0
	var jump_start_timer: float = 0.0
	var jump_phase: int = 0
	var is_ascending: bool = false
	var jump_to_type: int = 0

class StairData:
	var on_stairs: bool = false
	var ascending: bool = true
	var grace_timer: float = 0.0
	var blend_weight: float = 0.0
	var anim_exit_timer: float = 0.0
	var params_valid: bool = false
	var step_height_measured: float = 0.25
	var step_depth: float = 0.3
	var base_pos: Vector3 = Vector3.ZERO
	var dir_xz: Vector2 = Vector2.ZERO
	var root_motion_active: bool = false
	var rm_velocity: Vector3 = Vector3.ZERO
	var step_up_offset: float = 0.0
	var post_step_up_cooldown: int = 0
	var step_up_visual_debt: float = 0.0
	var was_ascending: bool = false
	var dir_committed: bool = false
	var committed_ascending: bool = true
	var dir_commit_timer: float = 0.0

class ClimbData:
	var state: int = 0
	var grab_point: Vector3 = Vector3.ZERO
	var surface_normal: Vector3 = Vector3.FORWARD
	var ledge_height: float = 0.0
	var mantle_root_motion_active: bool = false
	var mantle_start_pos: Vector3 = Vector3.ZERO
	var mantle_target_y: float = 0.0
	var mantle_height_compensation: float = 0.0
	var mantle_elapsed: float = 0.0
	var mantle_duration: float = 1.0
	var mantle_wall_point: Vector3 = Vector3.ZERO
	var mantle_rm_loaded: bool = false
	var wall_point: Vector3 = Vector3.ZERO
	var is_shimmying: bool = false
	var shimmy_direction: int = 0
	var shimmy_target_pos: Vector3 = Vector3.ZERO

class AnimState:
	var gait: int = 0
	var motion_state: int = 0

var ground := GroundData.new()
var air := AirData.new()
var stair := StairData.new()
var climb := ClimbData.new()
var anim := AnimState.new()
# =============================================================================
"""

def main():
    with open(FILE_PATH, 'r', encoding='utf8') as f:
        lines = f.readlines()

    # We need to drop the original declarations from the lines.
    # To do this safely, we will just comment out lines that start with `var ` and the variable name matches one of our replacements.
    new_lines = []
    
    # Sort replacements by length descending to replace longer names first (prevent partial match bugs)
    sorted_replacements = sorted(REPLACEMENTS.keys(), key=len, reverse=True)
    
    injected = False
    for i, line in enumerate(lines):
        # Inject our class definitions right after the `var skeleton` var near line ~46
        if not injected and "var ground_info: Dictionary = {" in line:
            new_lines.append(CLASSES_DEF + "\n")
            injected = True
            
        is_declaration = False
        for old_var in sorted_replacements:
            if line.startswith(f"var {old_var}") or line.startswith(f"var {old_var}:") or line.startswith(f"var {old_var} "):
                new_lines.append(f"# REMOVED_BY_REFACTOR: {line}")
                is_declaration = True
                break
                
        # Handle the dictionary initialization of ground_info which takes 7 lines
        if "ground_info: Dictionary = {" in line and "REMOVED" not in new_lines[-1] if len(new_lines)>0 else "":
            new_lines.append(f"# REMOVED_BY_REFACTOR: {line}")
            is_declaration = True
        elif is_declaration == False and "is_grounded" in line and "surface_normal" not in line and "REMOVED" in (new_lines[-1] if len(new_lines)>0 else ""): # skip dictionary lines
            # This is a bit hacky, better to just let it be commented if it's the dictionary block
            pass 
            
        if not is_declaration:
            # We don't want to replace inside strings or comments ideally, but GDScript has a lot of variable usages.
            # A simple regex \bvar_name\b will suffice.
            
            # Special manual skip for the dictionary block of ground_info
            if i >= 47 and i <= 53 and "ground_info" not in line and not injected:
                new_lines.append(f"# REMOVED_BY_REFACTOR: {line}")
                continue
            elif i >= 47 and i <= 53 and injected and "var ground_info" not in new_lines[-1] and "var" not in line:
                 new_lines.append(f"# REMOVED_BY_REFACTOR: {line}")
                 continue

            mod_line = line
            for old_var in sorted_replacements:
                new_var = REPLACEMENTS[old_var]
                mod_line = re.sub(r'\b' + old_var + r'\b', new_var, mod_line)
            new_lines.append(mod_line)

    with open(FILE_PATH, 'w', encoding='utf8') as f:
        f.writelines(new_lines)
    
    print("Refactoring complete.")

if __name__ == "__main__":
    main()
