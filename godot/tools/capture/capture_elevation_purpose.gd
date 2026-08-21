extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await create_timer(.8).timeout
    main.get_node("UI").visible=false
    var camera:=Camera3D.new()
    camera.fov=55.0
    main.add_child(camera)
    camera.current=true
    var sampler:Callable=main.get("_world_result").terrain_height_sampler
    var views:Array=[
        ["starter_ridge",Vector2(-420.0,230.0),Vector2(-80.0,880.0),18.0,8.0],
        ["crownspire_pass",Vector2(-720.0,-840.0),Vector2(80.0,-1900.0),42.0,8.0],
        ["greywatch_fort",Vector2(-1700.0,1230.0),Vector2(-1700.0,1720.0),34.0,5.0],
        ["eastreach_boundary",Vector2(1180.0,720.0),Vector2(1540.0,1120.0),28.0,4.0],
        ["northwood_crossing",Vector2(-1030.0,1610.0),Vector2(-1223.0,1680.0),24.0,2.5],
    ]
    var output:=ProjectSettings.globalize_path("res://artifacts")
    for view in views:
        var camera_ground:Vector3=sampler.call(view[1].x,view[1].y)
        var target_ground:Vector3=sampler.call(view[2].x,view[2].y)
        camera.global_position=camera_ground+Vector3.UP*float(view[3])
        camera.look_at(target_ground+Vector3.UP*float(view[4]),Vector3.UP)
        await create_timer(.42).timeout
        await RenderingServer.frame_post_draw
        var path:=output.path_join("elevation_%s.png"%str(view[0]))
        var error:=root.get_viewport().get_texture().get_image().save_png(path)
        print("ELEVATION_CAPTURE|%s|error=%s"%[path,error])
    main.free()
    quit()
