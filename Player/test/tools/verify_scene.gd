@tool
extends EditorScript

func _run():
    var scene = load("res://Player/test/PlayerCapsuleTest.tscn")
    if scene:
        print("SCENE LOADED SUCCESSFULLY")
    else:
        print("SCENE LOAD FAILED")
    get_editor_interface().get_selection().clear()
