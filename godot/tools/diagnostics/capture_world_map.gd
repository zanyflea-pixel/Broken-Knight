extends SceneTree


func _initialize()->void:
    call_deferred("_capture")


func _capture()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var world_map:=main.get_node("UI/WorldMap") as Control
    var player:=main.get_node("Player") as Node3D
    var x_raw:=OS.get_environment("BROKEN_KNIGHT_MAP_CAPTURE_X")
    var z_raw:=OS.get_environment("BROKEN_KNIGHT_MAP_CAPTURE_Z")
    if not x_raw.is_empty() and not z_raw.is_empty():
        var capture_point:=Vector2(float(x_raw),float(z_raw))
        player.global_position=main._sample_global_height(capture_point.x,capture_point.y)+Vector3.UP*.08
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    var requested_scale:=OS.get_environment("BROKEN_KNIGHT_MAP_CAPTURE_SCALE").strip_edges().to_lower()
    if requested_scale=="local":world_map.call("_set_map_scale",0)
    elif requested_scale=="world":world_map.call("_set_map_scale",2)
    else:world_map.call("_set_map_scale",1)
    world_map.visible=true
    # Let the asynchronous 512px terrain survey finish. Cached launches skip
    # this loop and make repeat visual inspections nearly immediate.
    var frames:=0
    while world_map.get("_terrain_texture")==null and frames<720:
        await process_frame
        frames+=1
    world_map.queue_redraw()
    for _frame in range(3):
        await process_frame
        await RenderingServer.frame_post_draw
    var output:=OS.get_environment("BROKEN_KNIGHT_MAP_CAPTURE_OUTPUT")
    if output.is_empty():output="user://complete-world-map.png"
    var error:=root.get_texture().get_image().save_png(output)
    var terrain_output:=OS.get_environment("BROKEN_KNIGHT_MAP_TERRAIN_OUTPUT")
    var terrain_error:=OK
    if not terrain_output.is_empty() and world_map.get("_terrain_texture")!=null:
        terrain_error=(world_map.get("_terrain_texture") as Texture2D).get_image().save_png(terrain_output)
    print("WORLD_MAP_CAPTURE|terrain=%s|features=%d|frames=%d|output=%s|error=%d"%[
        world_map.get("_terrain_texture")!=null,
        (world_map.get("_map_features") as Array).size(),
        frames,output,error,
    ])
    if not terrain_output.is_empty():
        print("WORLD_MAP_TERRAIN_BAKE|output=%s|error=%d"%[terrain_output,terrain_error])
    main.free()
    for _cleanup_frame in range(6):
        await process_frame
        if DisplayServer.get_name().to_lower()!="headless":await RenderingServer.frame_post_draw
    quit(0 if error==OK and terrain_error==OK else 1)
