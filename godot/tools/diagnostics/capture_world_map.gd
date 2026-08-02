extends SceneTree


func _initialize()->void:
    call_deferred("_capture")


func _capture()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    var world_map:=main.get_node("UI/WorldMap") as Control
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    world_map.visible=true
    # Let the asynchronous 512px terrain survey finish. Cached launches skip
    # this loop and make repeat visual inspections nearly immediate.
    var frames:=0
    while world_map.get("_terrain_texture")==null and frames<180:
        await process_frame
        frames+=1
    world_map.queue_redraw()
    for _frame in range(3):
        await process_frame
        await RenderingServer.frame_post_draw
    var output:=OS.get_environment("BROKEN_KNIGHT_MAP_CAPTURE_OUTPUT")
    if output.is_empty():output="user://complete-world-map.png"
    var error:=root.get_texture().get_image().save_png(output)
    print("WORLD_MAP_CAPTURE|terrain=%s|features=%d|frames=%d|output=%s|error=%d"%[
        world_map.get("_terrain_texture")!=null,
        (world_map.get("_map_features") as Array).size(),
        frames,output,error,
    ])
    main.free()
    quit(0 if error==OK else 1)
