extends SceneTree


func _init()->void:
	call_deferred("_run")


func _run()->void:
	var main_scene:=load("res://scenes/Main.tscn") as PackedScene
	var main:=main_scene.instantiate()
	main.set("auto_boot_enabled",false)
	root.add_child(main)
	await main.boot_world(Callable(),false,true)
	var horses:=get_nodes_in_group("rideable_horse")
	var player:=root.find_child("Player",true,false)
	if horses.is_empty() or player==null:
		push_error("STARTER_MOUNT_CAPTURE|missing runtime nodes")
		quit(1)
		return
	var horse:=horses[1] as Node3D
	player.global_position=horse.global_position
	var visual:=player.get_node_or_null("Visual") as Node3D
	if visual:visual.rotation.y=0.0
	player.mount_horse(horse)
	player.set_input_enabled(false)
	var camera_pivot:=player.get_node_or_null("CameraPivot") as Node3D
	if camera_pivot:
		camera_pivot.rotation.y=-.78
		camera_pivot.rotation.x=-.16
	var ui:=main.get_node_or_null("UI") as CanvasLayer
	if ui:ui.visible=false
	for frame in range(36):await process_frame
	var image:=root.get_texture().get_image()
	var output_path:=ProjectSettings.globalize_path("res://test_output/starter_mount_three_quarter_preview.png")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error:=image.save_png(output_path)
	print("STARTER_MOUNT_CAPTURE|path=%s|error=%d"%[output_path,error])
	quit(0 if error==OK else 2)
