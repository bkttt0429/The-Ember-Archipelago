extends SceneTree

func _init():
	print("Starting Geopolitics Phase 4 Scene Runner...")
	var scene = load("res://Development/Scripts/Systems/Geopolitics/TestScene/GeopoliticsPhase4TestScene.tscn")
	if scene == null:
		print("FAILURE: Could not load Phase 4 test scene.")
		quit(1)
		return
	
	var instance = scene.instantiate()
	if instance == null:
		print("FAILURE: Could not instantiate Phase 4 test scene.")
		quit(1)
		return
	
	get_root().add_child(instance)
