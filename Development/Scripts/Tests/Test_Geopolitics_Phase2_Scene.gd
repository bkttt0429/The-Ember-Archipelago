extends SceneTree

func _init():
	print("Starting Geopolitics Phase 2 Scene Runner...")
	var scene = load("res://Development/Scripts/Systems/Geopolitics/TestScene/GeopoliticsPhase2TestScene.tscn")
	if scene == null:
		print("FAILURE: Could not load Phase 2 test scene.")
		quit(1)
		return
	
	var instance = scene.instantiate()
	if instance == null:
		print("FAILURE: Could not instantiate Phase 2 test scene.")
		quit(1)
		return
	
	get_root().add_child(instance)
