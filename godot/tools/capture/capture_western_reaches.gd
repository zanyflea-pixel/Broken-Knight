extends SceneTree

const MAIN_SCENE=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_western_region_loaded()
    var player:Node3D=main.get_node("Player")
    player.global_position=main._sample_global_height(-6080.0,-40.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-40.0,-6080.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    player.set_input_enabled(false)
    player.visible=false
    main.get_node("UI").visible=false
    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="WesternReviewCamera"
    camera.fov=52.0
    camera.current=true
    main.add_child(camera)

    var overview_target:Vector3=main._sample_global_terrain_height(-7200.0,150.0)+Vector3.UP*20.0
    camera.global_position=overview_target+Vector3(820.0,430.0,760.0)
    camera.look_at(overview_target+Vector3(-260.0,0.0,40.0),Vector3.UP)
    await _settle(28)
    var overview_error:=await _capture("res://artifacts/western_reaches_overview_v1.png")

    var bridge_target:Vector3=main._sample_global_height(-6080.0,-40.0)+Vector3.UP*2.2
    camera.global_position=bridge_target+Vector3(42.0,15.0,46.0)
    camera.look_at(bridge_target+Vector3(-7.0,0.0,-2.0),Vector3.UP)
    await _settle(24)
    var bridge_error:=await _capture("res://artifacts/western_wardens_span_v1.png")

    var oakrest_target:Vector3=main._sample_global_height(-4750.0,-180.0)+Vector3.UP*4.0
    camera.global_position=oakrest_target+Vector3(118.0,54.0,104.0)
    camera.look_at(oakrest_target+Vector3(-8.0,3.0,0.0),Vector3.UP)
    await _settle(24)
    var oakrest_error:=await _capture("res://artifacts/western_oakrest_v1.png")

    var abbey_target:Vector3=main._sample_global_height(-9550.0,-720.0)+Vector3.UP*5.0
    camera.global_position=abbey_target+Vector3(82.0,35.0,92.0)
    camera.look_at(abbey_target+Vector3(0.0,5.0,0.0),Vector3.UP)
    await _settle(24)
    var abbey_error:=await _capture("res://artifacts/western_rainward_abbey_v1.png")

    # Player-height review angles catch buried roads, floating water, blocked
    # entrances and unreadable settlement silhouettes that aerial shots hide.
    player.global_position=main._sample_global_height(-4900.0,-180.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-180.0,-4900.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(18)
    var oakrest_street:Vector3=main._sample_global_height(-4900.0,-180.0)+Vector3.UP*2.15
    camera.global_position=oakrest_street
    camera.look_at(main._sample_global_height(-4730.0,-180.0)+Vector3.UP*2.1,Vector3.UP)
    await _settle(20)
    var oakrest_street_error:=await _capture("res://artifacts/western_oakrest_street_v1.png")

    player.global_position=main._sample_global_height(-5980.0,20.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(20.0,-5980.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(18)
    var bridge_road:Vector3=main._sample_global_height(-5980.0,20.0)+Vector3.UP*2.15
    camera.global_position=bridge_road
    camera.look_at(main._sample_global_height(-6080.0,-40.0)+Vector3.UP*1.8,Vector3.UP)
    await _settle(20)
    var bridge_road_error:=await _capture("res://artifacts/western_wardens_span_road_v1.png")

    player.global_position=main._sample_global_height(-8140.0,380.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(380.0,-8140.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(18)
    var rainhaven_street:Vector3=main._sample_global_height(-8140.0,380.0)+Vector3.UP*2.15
    camera.global_position=rainhaven_street
    camera.look_at(main._sample_global_height(-8290.0,380.0)+Vector3.UP*2.0,Vector3.UP)
    await _settle(20)
    var rainhaven_street_error:=await _capture("res://artifacts/western_rainhaven_street_v1.png")

    player.global_position=main._sample_global_height(-9450.0,-650.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-650.0,-9450.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(18)
    var abbey_road:Vector3=main._sample_global_height(-9450.0,-650.0)+Vector3.UP*2.15
    camera.global_position=abbey_road
    camera.look_at(main._sample_global_height(-9550.0,-720.0)+Vector3.UP*3.0,Vector3.UP)
    await _settle(20)
    var abbey_road_error:=await _capture("res://artifacts/western_rainward_abbey_road_v1.png")

    camera.current=false
    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    var world_map:=main.get_node("UI/WorldMap") as Control
    world_map.visible=true
    world_map.call("_set_map_scale",1)
    var map_frames:=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<900:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    await _settle(6)
    var map_error:=await _capture("res://artifacts/western_reaches_map_v1.png")

    print("WESTERN_CAPTURE|overview=%d|bridge=%d|oakrest=%d|abbey=%d|oakrest_street=%d|bridge_road=%d|rainhaven=%d|abbey_road=%d|map=%d|map_frames=%d"%[
        overview_error,bridge_error,oakrest_error,abbey_error,oakrest_street_error,
        bridge_road_error,rainhaven_street_error,abbey_road_error,map_error,map_frames,
    ])
    quit(0 if overview_error==OK and bridge_error==OK and oakrest_error==OK and abbey_error==OK and oakrest_street_error==OK and bridge_road_error==OK and rainhaven_street_error==OK and abbey_road_error==OK and map_error==OK else 1)
