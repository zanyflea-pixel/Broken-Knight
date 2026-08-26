extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _settle(frames:int=18)->void:
    for _frame in range(frames):await process_frame


func _focus_site(main:Node,player:CharacterBody3D,x:float,z:float)->void:
    player.global_position=main._sample_global_height(x,z)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(z,x)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(12)


func _place_ground_camera(camera:Camera3D,main:Node,from_x:float,from_z:float,target_x:float,target_z:float,target_height:float=5.0)->void:
    var eye_ground:Vector3=main._sample_global_terrain_height(from_x,from_z)
    var target_ground:Vector3=main._sample_global_terrain_height(target_x,target_z)
    camera.fov=68.0
    camera.global_position=eye_ground+Vector3.UP*2.25
    camera.look_at(target_ground+Vector3.UP*target_height,Vector3.UP)


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_east_region_loaded()
    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    await _focus_site(main,player,4500,1000)
    player.visible=false
    main.get_node("UI").visible=false
    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="EasternMarchesReviewCamera"
    camera.fov=54.0
    camera.current=true
    main.add_child(camera)

    var results:Array[int]=[]
    var region_target:Vector3=main._sample_global_terrain_height(7600,200)+Vector3.UP*26.0
    camera.global_position=region_target+Vector3(-920,440,920)
    camera.look_at(region_target+Vector3(360,8,-160),Vector3.UP)
    await _settle(30)
    results.append(await _capture("res://artifacts/eastern_marches_aerial_v1.png"))

    var dawnford_ground:Vector3=main._sample_global_terrain_height(4500,1000)
    await _focus_site(main,player,4380,1000)
    camera.fov=58.0
    camera.global_position=dawnford_ground+Vector3(-130,34,120)
    camera.look_at(dawnford_ground+Vector3(18,4,-4),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_dawnford_v1.png"))

    var ember_ground:Vector3=main._sample_global_terrain_height(7320,-70)
    await _focus_site(main,player,7240,-160)
    camera.global_position=ember_ground+Vector3(-102,42,116)
    camera.look_at(ember_ground+Vector3(10,1,0),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_ember_span_v1.png"))

    var march_keep_ground:Vector3=main._sample_global_terrain_height(8180,420)
    await _focus_site(main,player,8040,330)
    camera.global_position=march_keep_ground+Vector3(-148,48,126)
    camera.look_at(march_keep_ground+Vector3(0,6,0),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_march_keep_v1.png"))

    var cinder_ground:Vector3=main._sample_global_terrain_height(9560,-1840)
    await _focus_site(main,player,9440,-1760)
    camera.fov=55.0
    camera.global_position=cinder_ground+Vector3(-150,54,138)
    camera.look_at(cinder_ground+Vector3(12,10,-10),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_cinderwatch_v1.png"))

    var glassmere_ground:Vector3=main._sample_global_terrain_height(8980,2460)
    await _focus_site(main,player,8840,2350)
    camera.global_position=glassmere_ground+Vector3(-180,62,158)
    camera.look_at(glassmere_ground+Vector3(0,-1,0),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_glassmere_v1.png"))

    var salt_bridge_ground:Vector3=main._sample_global_terrain_height(5751,1527)
    await _focus_site(main,player,5660,1460)
    camera.global_position=salt_bridge_ground+Vector3(-84,30,98)
    camera.look_at(salt_bridge_ground+Vector3(0,1,0),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_saltmeadow_bridge_v1.png"))

    # Ground-level acceptance frames expose bad landings, floating props, weak
    # silhouettes, and unreadable approaches that aerial review can hide.
    await _focus_site(main,player,4500,1115)
    _place_ground_camera(camera,main,4500,1115,4500,895,5.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_dawnford_player_v1.png"))

    await _focus_site(main,player,8100,455)
    _place_ground_camera(camera,main,8100,455,8240,350,8.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_march_keep_player_v1.png"))

    await _focus_site(main,player,9400,-1685)
    _place_ground_camera(camera,main,9400,-1685,9560,-1840,10.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_cinderwatch_player_v1.png"))

    await _focus_site(main,player,8810,2340)
    _place_ground_camera(camera,main,8810,2340,8980,2460,1.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_glassmere_player_v1.png"))

    await _focus_site(main,player,6150,340)
    _place_ground_camera(camera,main,6150,340,5980,512,11.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_amberfield_player_v1.png"))

    await _focus_site(main,player,6815,2215)
    _place_ground_camera(camera,main,6815,2215,6632,2382,7.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_saltwatch_player_v1.png"))

    camera.current=false
    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    var world_map:=main.get_node("UI/WorldMap") as Control
    world_map.visible=true
    world_map.call("_set_map_scale",2)
    var map_frames:=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<1200:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    await _settle(8)
    results.append(await _capture("res://artifacts/world_atlas_7region_v1.png"))

    player.global_position=main._sample_global_height(7320,-70)+Vector3.UP*.08
    world_map.call("_set_map_scale",0)
    map_frames=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<1200:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    await _settle(8)
    results.append(await _capture("res://artifacts/eastern_marches_local_map_v1.png"))

    var failures:=results.filter(func(error:int)->bool:return error!=OK).size()
    print("EASTERN_CAPTURE|aerial=%d|dawnford=%d|ember_span=%d|march_keep=%d|cinderwatch=%d|glassmere=%d|salt_bridge=%d|dawnford_player=%d|march_keep_player=%d|cinderwatch_player=%d|glassmere_player=%d|amberfield_player=%d|saltwatch_player=%d|atlas=%d|local_map=%d|map_frames=%d|failures=%d"%[
        results[0],results[1],results[2],results[3],results[4],results[5],results[6],results[7],results[8],results[9],results[10],results[11],results[12],results[13],results[14],map_frames,failures,
    ])
    quit(0 if failures==0 else 1)
