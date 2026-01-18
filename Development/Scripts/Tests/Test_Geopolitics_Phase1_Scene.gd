extends SceneTree

func _init():
	print("Starting Geopolitics Phase 1 Scene Runner...")
	var scene_path = "res://Development/Scripts/Systems/Geopolitics/TestScene/GeopoliticsPhase1TestScene.tscn"
	print("Loading scene:", scene_path)
	var scene = load(scene_path)
	if scene == null:
		print("FAILURE: Could not load Phase 1 test scene.")
		quit(1)
		return
	
	var instance = scene.instantiate()
	if instance == null:
		print("FAILURE: Could not instantiate Phase 1 test scene.")
	else:
		print("Scene instantiated successfully.")
		quit(1)
		return
	
	get_root().add_child(instance)
