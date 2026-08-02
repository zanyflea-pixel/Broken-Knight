extends SceneTree


func _initialize()->void:
    call_deferred("_capture")


func _capture()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    var player:=main.get_node("Player") as Node3D
    var minimap:=main.get_node("UI/Minimap") as Control
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/WorldMap").visible=false
    player.global_position=Vector3(250.0,20.0,-2450.0)
    minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
    minimap.position=Vector2(390,100)
    minimap.size=Vector2(500,500)
    minimap.visible=true
    minimap.call("_begin_terrain_refresh",Vector2(250.0,-2450.0))
    var frames:=0
    while int(minimap.get("_pending_row"))>=0 and frames<100:
        await process_frame
        frames+=1
    minimap.queue_redraw()
    for _frame in range(3):
        await process_frame
        await RenderingServer.frame_post_draw
    var output:=OS.get_environment("BROKEN_KNIGHT_MINIMAP_CAPTURE_OUTPUT")
    if output.is_empty():output="user://minimap-detail.png"
    var error:=root.get_texture().get_image().save_png(output)
    print("MINIMAP_CAPTURE|terrain=%s|frames=%d|output=%s|error=%d"%[
        minimap.get("_terrain_texture")!=null,frames,output,error,
    ])
    main.free()
    quit(0 if error==OK else 1)
