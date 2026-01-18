extends SceneTree

func _init():
	print("Starting Geopolitics Phase 5 Scene Runner...")
	var scene = load("res://Development/Scripts/Systems/Geopolitics/TestScene/GeopoliticsPhase5TestScene.tscn")
	if scene == null:
		print("FAILURE: Could not load Phase 5 test scene.")
		quit(1)
		return
	
	var instance = scene.instantiate()
	if instance == null:
		print("FAILURE: Could not instantiate Phase 5 test scene.")
		quit(1)
		return
	
	get_root().add_child(instance)
