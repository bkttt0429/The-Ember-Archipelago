@tool
extends EditorScript

func _run() -> void:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		print("ERROR: No scene open")
		return

	var at = root.get_node("Player/AnimationTree")
	if not at:
		print("ERROR: AnimationTree not found")
		return

	# Step 1: Create AnimationNodeBlendTree (standard Godot class)
	var blend_tree = AnimationNodeBlendTree.new()
	at.tree_root = blend_tree
	print("Step 1: AnimationNodeBlendTree created and set as tree_root")
	print("  tree_root class: ", at.tree_root.get_class() if at.tree_root else "NULL")

	if not at.tree_root:
		print("ERROR: tree_root assignment failed!")
		return

	# Step 2: Create MMAnimationNode via ClassDB
	if not ClassDB.can_instantiate(&"MMAnimationNode"):
		print("ERROR: Cannot instantiate MMAnimationNode - GDExtension not loaded?")
		return

	var mm_node = ClassDB.instantiate(&"MMAnimationNode")
	if not mm_node:
		print("ERROR: ClassDB.instantiate returned null")
		return

	print("Step 2: MMAnimationNode created, class: ", mm_node.get_class())

	# Step 3: Set library property
	mm_node.set(&"library", &"mm")
	print("Step 3: library set to 'mm'")

	# Step 4: Add to blend tree and connect
	blend_tree.add_node(&"MMAnimationNode", mm_node, Vector2(0, 140))
	print("Step 4: MMAnimationNode added to blend tree")

	blend_tree.connect_node(&"output", 0, &"MMAnimationNode")
	print("Step 5: MMAnimationNode connected to output")

	# Verify
	print("")
	print("=== VERIFICATION ===")
	print("tree_root: ", at.tree_root)
	print("tree_root class: ", at.tree_root.get_class())
	print("blend tree nodes: ", blend_tree.get_node_list())

	EditorInterface.mark_scene_as_unsaved()
	print("")
	print("DONE! Now press Ctrl+S to save the scene.")
