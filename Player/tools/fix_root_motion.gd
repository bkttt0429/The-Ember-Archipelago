@tool
extends EditorScript
## 將 UAL 動畫整合到 movement.res
## 使用方式：Script > Run

const UAL_DIR = "res://Player/assets/characters/player/motion/Universal Animation Library[Standard]/Unreal-Godot/"
const TARGET_LIBRARY_PATH = "res://Player/animations/movement.res"

# 要匯入的動畫列表 (檔名 -> 目標名稱)
# 使用 "ual_" 前綴來區分
const ANIMATIONS = {
	"Idle.res": "ual_Idle",
	"Walk.res": "ual_Walk",
	"Walk_Formal.res": "ual_Walk_Formal",
	"Jog_Fwd.res": "ual_Jog_Fwd",
	"Sprint.res": "ual_Sprint",
	"Crouch_Idle.res": "ual_Crouch_Idle",
	"Crouch_Fwd.res": "ual_Crouch_Fwd",
	"Jump.res": "ual_Jump",
	"Jump_Start.res": "ual_Jump_Start",
	"Jump_Land.res": "ual_Jump_Land",
	"Roll.res": "ual_Roll",
	"Dance.res": "ual_Dance",
	"Death01.res": "ual_Death",
	"Hit_Chest.res": "ual_Hit_Chest",
	"Hit_Head.res": "ual_Hit_Head",
	"Interact.res": "ual_Interact",
	"Push.res": "ual_Push",
	"Punch_Jab.res": "ual_Punch_Jab",
	"Punch_Cross.res": "ual_Punch_Cross",
	"Sword_Idle.res": "ual_Sword_Idle",
	"Sword_Attack.res": "ual_Sword_Attack",
	"Pistol_Idle.res": "ual_Pistol_Idle",
	"Pistol_Aim_Neutral.res": "ual_Pistol_Aim",
	"Pistol_Shoot.res": "ual_Pistol_Shoot",
	"Pistol_Reload.res": "ual_Pistol_Reload",
	"Swim_Idle.res": "ual_Swim_Idle",
	"Swim_Fwd.res": "ual_Swim_Fwd",
	"Sitting_Idle.res": "ual_Sitting_Idle",
	"Sitting_Enter.res": "ual_Sitting_Enter",
	"Sitting_Exit.res": "ual_Sitting_Exit",
	"Spell_Simple_Idle.res": "ual_Spell_Idle",
	"Spell_Simple_Enter.res": "ual_Spell_Enter",
	"Spell_Simple_Shoot.res": "ual_Spell_Shoot",
	"Idle_Talking.res": "ual_Idle_Talking",
	"Idle_Torch.res": "ual_Idle_Torch",
	"Driving.res": "ual_Driving",
}

func _run() -> void:
	print("=== 整合 UAL 動畫到 movement.res ===")
	
	# 載入目標動畫庫
	var lib = load(TARGET_LIBRARY_PATH) as AnimationLibrary
	if not lib:
		lib = AnimationLibrary.new()
		print("建立新的動畫庫")
	
	var success_count = 0
	var fail_count = 0
	
	for file_name in ANIMATIONS.keys():
		var anim_path = UAL_DIR + file_name
		var target_name = ANIMATIONS[file_name]
		
		var anim = load(anim_path) as Animation
		if not anim:
			print("✗ 無法載入: ", file_name)
			fail_count += 1
			continue
		
		# 判斷是否循環
		var should_loop = _should_loop(target_name)
		if should_loop:
			anim.loop_mode = Animation.LOOP_LINEAR
		
		# 加入/替換
		if lib.has_animation(target_name):
			lib.remove_animation(target_name)
		lib.add_animation(target_name, anim)
		
		print("✓ ", target_name, " (", "loop" if should_loop else "once", ")")
		success_count += 1
	
	# 儲存
	var err = ResourceSaver.save(lib, TARGET_LIBRARY_PATH)
	if err == OK:
		print("\n=== 完成！成功: ", success_count, ", 失敗: ", fail_count, " ===")
		print("請重新載入場景")
	else:
		push_error("儲存失敗")

func _should_loop(anim_name: String) -> bool:
	var lower = anim_name.to_lower()
	var loop_words = ["walk", "idle", "jog", "sprint", "swim", "crouch", "sit", "driving", "torch"]
	var no_loop = ["jump", "land", "start", "exit", "enter", "attack", "shoot", "death", "hit", "roll", "punch", "reload", "interact", "push"]
	
	for w in no_loop:
		if w in lower:
			return false
	for w in loop_words:
		if w in lower:
			return true
	return false
