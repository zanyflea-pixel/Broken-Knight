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
    camera.fov=56.0
    main.add_child(camera)
    camera.current=true
    var sampler:Callable=main.get("_world_result").terrain_height_sampler
    var views:Array=[
        ["starter_bank",Vector2(-1040.0,390.0),Vector2(-1000.0,250.0),18.0,1.0],
        ["eastreach_source",Vector2(3290.0,2460.0),Vector2(3560.0,2830.0),52.0,2.0],
        ["redstone_source",Vector2(3220.0,-3280.0),Vector2(3560.0,-3520.0),52.0,2.0],
        ["eastfall",Vector2(2230.0,520.0),Vector2(2040.0,330.0),34.0,2.0],
        ["northwood_bank",Vector2(-1080.0,2020.0),Vector2(-1180.0,1820.0),7.0,.5],
        ["westfall_bank",Vector2(-1030.0,390.0),Vector2(-1160.0,300.0),7.0,.5],
    ]
    var output:=ProjectSettings.globalize_path("res://artifacts")
    for view in views:
        var camera_ground:Vector3=sampler.call(view[1].x,view[1].y)
        var target_ground:Vector3=sampler.call(view[2].x,view[2].y)
        camera.global_position=camera_ground+Vector3.UP*float(view[3])
        camera.look_at(target_ground+Vector3.UP*float(view[4]),Vector3.UP)
        await create_timer(.42).timeout
        await RenderingServer.frame_post_draw
        var path:=output.path_join("river_repair_%s.png"%str(view[0]))
        var error:=root.get_viewport().get_texture().get_image().save_png(path)
        print("RIVER_REPAIR_CAPTURE|%s|error=%s"%[path,error])
    main.free()
    quit()
