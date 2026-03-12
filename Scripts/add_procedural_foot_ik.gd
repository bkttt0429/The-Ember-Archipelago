@tool
extends EditorScript

## 在 Player 場景中添加 ProceduralFootIK 子節點
## 運行方式: 在編輯器中打開 Player.tscn，然後執行此腳本

func _run() -> void:
	var edited_scene = EditorInterface.get_edited_scene_root()
	
	if not edited_scene:
		printerr("請先打開 Player.tscn 場景!")
		return
	
	print("當前場景: ", edited_scene.name)
	
	# 檢查是否已存在 ProceduralFootIK
	var existing = edited_scene.find_child("ProceduralFootIK", false, false)
	if existing:
		print("ProceduralFootIK 節點已存在!")
		return
	
	# 創建 ProceduralFootIK 節點 (Node3D)
	var proc_ik = Node3D.new()
	proc_ik.name = "ProceduralFootIK"
	
	# 附加腳本
	var script_path = "res://Player/systems/ProceduralFootIK.gd"
	var script = load(script_path)
	if script:
		proc_ik.set_script(script)
		print("✓ 已載入腳本: ", script_path)
	else:
		printerr("找不到腳本: ", script_path)
		return
	
	# 添加到場景
	edited_scene.add_child(proc_ik)
	proc_ik.owner = edited_scene
	
	# 嘗試設置參照
	var left_target = edited_scene.find_child("LeftFootTarget", true, false)
	var right_target = edited_scene.find_child("RightFootTarget", true, false)
	var skeleton = edited_scene.find_child("GeneralSkeleton", true, false)
	
	if left_target:
		proc_ik.left_target = left_target
		print("✓ 設置 left_target: ", left_target.name)
	if right_target:
		proc_ik.right_target = right_target
		print("✓ 設置 right_target: ", right_target.name)
	if skeleton:
		proc_ik.skeleton = skeleton
		print("✓ 設置 skeleton: ", skeleton.name)
	
	print("✓ 成功在 '%s' 中添加 ProceduralFootIK 節點!" % edited_scene.name)
	print("請記得保存場景 (Ctrl+S)")
