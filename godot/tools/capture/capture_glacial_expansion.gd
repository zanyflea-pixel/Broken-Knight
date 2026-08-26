extends SceneTree

const MAIN_SCENE=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_glacial_region_loaded()
    var player:Node3D=main.get_node("Player")
    player.global_position=main._sample_global_height(-360.0,-12300.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-15000.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    player.set_input_enabled(false)
    main.get_node("UI").visible=false
    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="GlacialReviewCamera"
    camera.fov=52.0
    camera.current=true
    main.add_child(camera)

    var glacier_target:Vector3=main._sample_global_terrain_height(500.0,-14920.0)+Vector3.UP*24.0
    camera.global_position=glacier_target+Vector3(420.0,145.0,560.0)
    camera.look_at(glacier_target+Vector3(-40,10,-110),Vector3.UP)
    for _frame in range(20):await process_frame
    var world_error:=await _capture("res://artifacts/glacial_range_v1.png")

    var troll_root:Node3D=null
    for enemy in main.get_node("GameplayDirector").get("minions"):
        if str(enemy.get("kind",""))=="rimecrawler":
            troll_root=enemy.get("node") as Node3D
            break
    var troll_error:=ERR_DOES_NOT_EXIST
    if is_instance_valid(troll_root):
        player.global_position=main._sample_global_height(troll_root.global_position.x+8.0,troll_root.global_position.z+7.0)+Vector3.UP*.08
        camera.global_position=troll_root.global_position+Vector3(6.6,3.8,7.7)
        camera.look_at(troll_root.global_position+Vector3.UP*1.65,Vector3.UP)
        for _frame in range(16):await process_frame
        troll_error=await _capture("res://artifacts/rimecrawler_in_world_v1.png")

    camera.current=false
    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    var world_map:=main.get_node("UI/WorldMap") as Control
    world_map.visible=true
    world_map.call("_set_map_scale",2)
    var map_frames:=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<900:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    for _frame in range(5):await process_frame
    var map_error:=await _capture("res://artifacts/world_atlas_3region_v1.png")

    player.global_position=main._sample_global_height(1190.0,-14270.0)+Vector3.UP*.08
    world_map.call("_set_map_scale",0)
    map_frames=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<900:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    for _frame in range(5):await process_frame
    var local_map_error:=await _capture("res://artifacts/glacial_local_map_v2.png")

    world_map.visible=false
    var minimap:=main.get_node("UI/Minimap") as Control
    minimap.visible=true
    minimap.call("_begin_terrain_refresh",Vector2(player.global_position.x,player.global_position.z))
    var minimap_frames:=0
    while (int(minimap.get("_pending_row"))>=0 or int(minimap.get("_pending_color_row"))>=0) and minimap_frames<900:
        await process_frame
        minimap_frames+=1
    gameplay_camera.current=true
    for _frame in range(6):await process_frame
    var minimap_error:=await _capture("res://artifacts/glacial_lair_minimap_v1.png")

    print("GLACIAL_CAPTURE|world=%d|enemy_closeup=%d|atlas=%d|local_map=%d|minimap=%d|map_frames=%d|minimap_frames=%d"%[world_error,troll_error,map_error,local_map_error,minimap_error,map_frames,minimap_frames])
    # The enemy close-up is opportunistic: regional streaming can correctly
    # cull the selected group before this camera pass. Map/world captures are
    # the required outputs of this review tool.
    quit(0 if world_error==OK and map_error==OK and local_map_error==OK and minimap_error==OK else 1)
