@tool
extends EditorScript

func _run() -> void:
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("ERROR: No scene open")
		return

	var ap = root.get_node("Player/AnimationPlayer")
	if not ap:
		print("ERROR: AnimationPlayer not found")
		return

	# Rename the default library from "" to "mm"
	var libs = ap.get_animation_library_list()
	print("Current libraries: ", libs)

	if libs.has(&""):
		ap.rename_animation_library(&"", &"mm")
		print("Renamed library '' -> 'mm'")
	elif libs.has(&"mm"):
		print("Library 'mm' already exists, skipping rename")
	else:
		print("WARNING: No default library found! Libraries: ", libs)

	# Verify
	print("Libraries after rename: ", ap.get_animation_library_list())

	# Now set up MMAnimationNode as tree_root
	var at = root.get_node("Player/AnimationTree")
	if at:
		var mm_node = ClassDB.instantiate(&"MMAnimationNode")
		if mm_node:
			mm_node.set(&"library", &"mm")
			mm_node.set(&"query_frequency", 2.0)
			at.tree_root = mm_node
			print("tree_root set to MMAnimationNode with library='mm'")
			print("tree_root class: ", at.tree_root.get_class() if at.tree_root else "NULL")
		else:
			print("ERROR: Could not instantiate MMAnimationNode")
	else:
		print("ERROR: AnimationTree not found")

	# Mark scene as modified
	get_editor_interface().mark_scene_as_unsaved()
	print("DONE! Please save the scene (Ctrl+S)")
