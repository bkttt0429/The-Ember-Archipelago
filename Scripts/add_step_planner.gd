@tool
extends EditorScript

## 在 Player 場景中添加 StepPlanner 子節點
## 運行方式: 在編輯器中打開 Player.tscn，然後執行此腳本

func _run() -> void:
	var editor = get_editor_interface()
	var edited_scene = editor.get_edited_scene_root()
	
	if not edited_scene:
		printerr("請先打開 Player.tscn 場景!")
		return
	
	print("當前場景: ", edited_scene.name)
	
	# 檢查是否已存在 StepPlanner
	var existing = edited_scene.find_child("StepPlanner", false, false)
	if existing:
		print("StepPlanner 節點已存在!")
		return
	
	# 創建 StepPlanner 節點
	var step_planner = Node.new()
	step_planner.name = "StepPlanner"
	
	# 附加腳本
	var script_path = "res://Player/systems/StepPlanner.gd"
	var script = load(script_path)
	if script:
		step_planner.set_script(script)
		print("✓ 已載入腳本: ", script_path)
	else:
		printerr("找不到腳本: ", script_path)
		return
	
	# 添加到場景
	edited_scene.add_child(step_planner)
	step_planner.owner = edited_scene
	
	print("✓ 成功在 '%s' 中添加 StepPlanner 節點!" % edited_scene.name)
	print("請記得保存場景 (Ctrl+S)")
