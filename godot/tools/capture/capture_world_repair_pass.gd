extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    main.get_node("UI").visible=false
    var camera:=Camera3D.new()
    main.add_child(camera)
    camera.current=true
    camera.fov=58.0
    var reviews:=[
        ["river_confluence",Vector3(-1550,72,500),Vector3(-1550,1.8,420)],
        ["west_cavern_path",Vector3(-2550,105,1370),Vector3(-2640,18,1570)],
        ["castle_throne",Vector3(250,16.4,-2457),Vector3(250,15.0,-2475)],
        ["westmere_fences",Vector3(-2500,58,-820),Vector3(-2500,5,-950)],
    ]
    var output_dir:=ProjectSettings.globalize_path("res://artifacts")
    var requested_review:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_TARGET")
    for review in reviews:
        if not requested_review.is_empty() and str(review[0])!=requested_review:
            continue
        camera.global_position=review[1]
        camera.look_at(review[2],Vector3.UP)
        await create_timer(.35).timeout
        await RenderingServer.frame_post_draw
        var image:=root.get_viewport().get_texture().get_image()
        var path:=output_dir.path_join("repair_%s.png"%review[0])
        var error:=image.save_png(path)
        print("REPAIR_CAPTURE|%s|error=%s|fps=%d|draw_calls=%d|primitives=%d"%[path,error,Engine.get_frames_per_second(),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
    main.free()
    quit()
