@tool
extends EditorScenePostImport


func set_animation_loops(node: Node) -> void:
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		for animation_name in [&"Idle", &"Walk", &"TorchIdle", &"TorchWalk", &"StaffIdle", &"StaffWalk", &"WarriorIdle", &"WarriorWalk"]:
			if player.has_animation(animation_name):
				player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
		for animation_name in [&"Jump", &"Land", &"Roll", &"Death", &"Spark", &"Nova", &"Blink", &"Orb", &"StaffSpark", &"StaffNova", &"StaffBlink", &"StaffOrb", &"SwordSlash", &"ShieldBash"]:
			if player.has_animation(animation_name):
				player.get_animation(animation_name).loop_mode = Animation.LOOP_NONE
	for child in node.get_children():
		set_animation_loops(child)


func _post_import(scene: Node) -> Object:
	set_animation_loops(scene)
	return scene
