extends SceneTree


func _initialize()->void:
    call_deferred("_capture_site")


func _capture_site()->void:
    var main_scene:PackedScene=load("res://scenes/Main.tscn")
    var main:Node3D=main_scene.instantiate()
    root.add_child(main)
    await process_frame

    var capture_x:=float(OS.get_environment("BROKEN_KNIGHT_CAPTURE_X"))
    var capture_z:=float(OS.get_environment("BROKEN_KNIGHT_CAPTURE_Z"))
    var capture_yaw:=float(OS.get_environment("BROKEN_KNIGHT_CAPTURE_YAW"))
    var output:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_OUTPUT")
    if output.is_empty():output="user://world-site-capture.png"

    var world_result:Dictionary=main.get("_world_result")
    var player:=main.get_node("Player") as CharacterBody3D
    var ground:Vector3=world_result.height_sampler.call(capture_x,capture_z)
    player.global_position=ground+Vector3.UP*.08
    player.rotation.y=capture_yaw
    # HeroController owns the camera yaw separately from the body transform.
    # Keep diagnostic site captures aimed in the requested direction.
    player.set("_yaw",capture_yaw)
    player.get_node("CameraPivot").rotation.y=capture_yaw
    main.get_node("UI").visible=false

    var target_x_raw:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_TARGET_X")
    var target_z_raw:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_TARGET_Z")
    if not target_x_raw.is_empty() and not target_z_raw.is_empty():
        var target_ground:Vector3=world_result.height_sampler.call(float(target_x_raw),float(target_z_raw))
        var admin_camera:=main.get_node("AdminCamera") as Camera3D
        var target_distance_raw:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_TARGET_DISTANCE")
        var target_height_raw:=OS.get_environment("BROKEN_KNIGHT_CAPTURE_TARGET_HEIGHT")
        var target_distance:=8.5 if target_distance_raw.is_empty() else float(target_distance_raw)
        var target_height:=5.2 if target_height_raw.is_empty() else float(target_height_raw)
        admin_camera.projection=Camera3D.PROJECTION_PERSPECTIVE
        admin_camera.fov=52.0
        admin_camera.global_position=target_ground+Vector3(target_distance,target_height,target_distance)
        admin_camera.look_at(target_ground+Vector3.UP*.9,Vector3.UP)
        admin_camera.current=true

    # Give culling, materials and the third-person camera a few rendered
    # frames to settle after the teleport.
    for _frame in range(8):
        await process_frame
        await RenderingServer.frame_post_draw
    var image:=root.get_texture().get_image()
    var error:=image.save_png(output)
    var props:=main.get_node("WorldRoot/PropsRoot")
    var cairn_transforms:Array=props.get_meta("roadside_cairn_transforms",[])
    var cairn_debug:Vector3=Vector3.ZERO if cairn_transforms.is_empty() else (cairn_transforms[0] as Transform3D).origin
    var verge_transforms:Array=props.get_meta("roadside_verge_transforms",[])
    var verge_debug:Vector3=Vector3.ZERO if verge_transforms.is_empty() else (verge_transforms[0] as Transform3D).origin
    var camera:=player.get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    var cairn_view_dot:=(-camera.global_transform.basis.z).dot(camera.global_position.direction_to(cairn_debug))
    print("WORLD_SITE_CAPTURE|x=%.1f|z=%.1f|bracken=%d|wetland=%d|walls=%d|cover=%d|cairns=%d|verges=%d|outcrops=%d|outcrop_bracken=%d|first_cairn=%s|first_verge=%s|cairn_view_dot=%.3f|output=%s|error=%d"%[
        capture_x,capture_z,
        int(props.get_meta("bracken_patch_count",0)),
        int(props.get_meta("wetland_cluster_count",0)),
        int(props.get_meta("field_wall_segment_count",0)),
        int(props.get_meta("regional_cover_count",0)),
        int(props.get_meta("roadside_cairn_count",0)),
        int(props.get_meta("roadside_verge_cluster_count",0)),
        int(props.get_meta("highland_outcrop_count",0)),
        int(props.get_meta("outcrop_bracken_count",0)),
        str(cairn_debug),
        str(verge_debug),
        cairn_view_dot,
        output,error,
    ])
    main.free()
    quit(0 if error==OK else 1)
