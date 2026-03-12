extends Node

var player

func _ready():
	set_process(true)
	# Find player node
	player = get_node("/root").find_child("Player", true, false)

func _process(delta):
	if player and player.is_on_floor():
		var n = player.get_floor_normal()
		if n.dot(Vector3.UP) < 0.95:
			var l_foot = player.get_node_or_null("Visuals/Human/GeneralSkeleton/LeftFootTarget")
			var phys_y = player.global_position.y
			var vis_node = player.get_node_or_null("Visuals")
			var vis_y = vis_node.global_position.y if vis_node else 0.0
			var l_y = l_foot.global_position.y if l_foot else 0.0
			print(">>> [SLOPE DEBUG] phys_y=%.3f vis_y=%.3f diff=%.3f IK_L_Y=%.3f" % [phys_y, vis_y, vis_y - phys_y, l_y])
