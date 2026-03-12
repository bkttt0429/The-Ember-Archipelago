@tool
extends EditorScript

## 加入 crouch input action

func _run() -> void:
	print("=== 加入 Crouch Input Action ===")
	
	# 檢查是否已存在
	if ProjectSettings.has_setting("input/crouch"):
		print("  ⚠️ 'crouch' action 已存在")
	else:
		# 創建新的 input action
		var action = {
			"deadzone": 0.5,
			"events": []
		}
		
		# 加入 Left Ctrl 按鍵
		var key_event = InputEventKey.new()
		key_event.keycode = KEY_CTRL
		key_event.physical_keycode = KEY_CTRL
		action.events.append(key_event)
		
		ProjectSettings.set_setting("input/crouch", action)
		print("  ✅ 已加入 'crouch' action (KEY_CTRL)")
	
	# 保存設定
	var err = ProjectSettings.save()
	if err == OK:
		print("  ✅ ProjectSettings 已保存")
	else:
		print("  ❌ 保存失敗: ", err)
	
	print("=== 完成！===")
