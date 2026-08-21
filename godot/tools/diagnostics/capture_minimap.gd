extends SceneTree


func _initialize()->void:
    call_deferred("_capture")


func _capture()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as Node3D
    var minimap:=main.get_node("UI/Minimap") as Control
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/WorldMap").visible=false
    var x_raw:=OS.get_environment("BROKEN_KNIGHT_MINIMAP_X")
    var z_raw:=OS.get_environment("BROKEN_KNIGHT_MINIMAP_Z")
    var capture_x:=250.0 if x_raw.is_empty() else float(x_raw)
    var capture_z:=-2450.0 if z_raw.is_empty() else float(z_raw)
    var world_result:Dictionary=main.get("_world_result")
    player.global_position=world_result.height_sampler.call(capture_x,capture_z)+Vector3.UP*.08
    minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
    minimap.position=Vector2(390,100)
    minimap.size=Vector2(500,500)
    minimap.visible=true
    minimap.call("_begin_terrain_refresh",Vector2(capture_x,capture_z))
    var frames:=0
    while (int(minimap.get("_pending_row"))>=0 or int(minimap.get("_pending_color_row"))>=0 or minimap.get("_terrain_texture")==null) and frames<180:
        await process_frame
        frames+=1
    minimap.queue_redraw()
    for _frame in range(3):
        await process_frame
        await RenderingServer.frame_post_draw
    var output:=OS.get_environment("BROKEN_KNIGHT_MINIMAP_CAPTURE_OUTPUT")
    if output.is_empty():output="user://minimap-detail.png"
    var error:=root.get_texture().get_image().save_png(output)
    print("MINIMAP_CAPTURE|x=%.1f|z=%.1f|terrain=%s|frames=%d|output=%s|error=%d"%[
        capture_x,capture_z,minimap.get("_terrain_texture")!=null,frames,output,error,
    ])
    main.free()
    quit(0 if error==OK else 1)
