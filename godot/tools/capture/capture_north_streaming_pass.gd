extends SceneTree

const MAIN_SCENE=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_capture")


func _capture()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_north_region_loaded()
    main.get_node("UI").visible=false
    var target:Vector3=main._sample_global_terrain_height(360.0,-3600.0)
    var camera:=main.get_node("AdminCamera") as Camera3D
    camera.projection=Camera3D.PROJECTION_PERSPECTIVE
    camera.fov=58.0
    camera.global_position=target+Vector3(250.0,125.0,-300.0)
    camera.look_at(target+Vector3(0,8,170),Vector3.UP)
    camera.current=true
    for _frame in range(12):
        await process_frame
        await RenderingServer.frame_post_draw
    var seam_output:="user://north_streaming_seam.png"
    var seam_error:=root.get_texture().get_image().save_png(seam_output)

    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    var world_map:=main.get_node("UI/WorldMap") as Control
    world_map.visible=true
    var frames:=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and frames<900:
        await process_frame
        frames+=1
    world_map.queue_redraw()
    for _frame in range(4):
        await process_frame
        await RenderingServer.frame_post_draw
    var map_output:="user://north_streaming_atlas.png"
    var map_error:=root.get_texture().get_image().save_png(map_output)
    print("NORTH_STREAM_CAPTURE|seam=%s|map=%s|map_frames=%d|errors=%d,%d"%[
        seam_output,map_output,frames,seam_error,map_error,
    ])
    quit(0 if seam_error==OK and map_error==OK else 1)
