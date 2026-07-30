extends SceneTree


func _init()->void:
    call_deferred("_run")


func _shot(path:String)->void:
    await create_timer(.45).timeout
    await RenderingServer.frame_post_draw
    root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
    print("TREE_CAPTURE|%s"%path)


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    main.get_node("UI").visible=false
    var director:Node=main.get_node("GameplayDirector")
    var player:CharacterBody3D=main.get_node("Player")
    var camera:=Camera3D.new();main.add_child(camera);camera.current=true;camera.fov=54.0

    var world_tree:Dictionary=director._forest_trees[0]
    var world_position:Vector3=world_tree.position
    player.global_position=world_position+Vector3(0,.1,2)
    camera.global_position=world_position+Vector3(11,6.8,12)
    camera.look_at(world_position+Vector3.UP*3.8,Vector3.UP)
    await _shot("res://artifacts/tree_standing_world.png")

    main.free()
    quit()
