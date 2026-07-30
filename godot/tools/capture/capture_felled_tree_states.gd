extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _shot(path:String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("FELLED_TREE_CAPTURE|%s" % path)


func _run() -> void:
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	await process_frame
	await process_frame
	main.get_node("UI").visible = false

	var director := main.get_node("GameplayDirector")
	var player := main.get_node("Player") as CharacterBody3D
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.current = true
	camera.fov = 48.0

	var target:Dictionary = director._forest_trees[0] if not director._forest_trees.is_empty() else {}
	if target.is_empty():
		push_error("No choppable tree available for capture")
		quit(1)
		return

	var position:Vector3 = target.position
	player.equip_item_id("starter_wood_axe")
	player.global_position = position + Vector3(0.0, 0.1, 2.0)
	camera.global_position = position + Vector3(9.5, 4.6, 10.5)
	camera.look_at(position + Vector3.UP * 1.15, Vector3.UP)
	director._activate_world_tree(target)
	director._activate_world_tree(target)
	director._activate_world_tree(target)
	await create_timer(1.05).timeout
	await _shot("res://artifacts/tree_felled_with_logs.png")
	await create_timer(4.15).timeout
	await _shot("res://artifacts/tree_despawned_logs_remain.png")
	main.free()
	quit()
