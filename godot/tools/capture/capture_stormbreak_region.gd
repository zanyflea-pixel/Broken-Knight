extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


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
    await main._ensure_western_region_loaded()
    await main._ensure_north_region_loaded()
    await main._ensure_stormbreak_region_loaded()
    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    player.global_position=main._sample_global_height(-7200,-7200)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-7200,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    player.visible=false
    main.get_node("UI").visible=false
    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="StormbreakReviewCamera"
    camera.fov=54.0
    camera.current=true
    main.add_child(camera)

    var results:Array[int]=[]
    var region_target:Vector3=main._sample_global_terrain_height(-7420,-7540)+Vector3.UP*18.0
    camera.global_position=region_target+Vector3(390,155,540)
    camera.look_at(region_target+Vector3(70,4,-40),Vector3.UP)
    for _frame in range(28):await process_frame
    results.append(await _capture("res://artifacts/stormbreak_region_aerial_v1.png"))

    var hold_ground:Vector3=main._sample_global_terrain_height(-7420,-7540)
    camera.fov=58.0
    camera.global_position=hold_ground+Vector3(90,18,92)
    camera.look_at(hold_ground+Vector3(0,5,-8),Vector3.UP)
    for _frame in range(20):await process_frame
    results.append(await _capture("res://artifacts/stormbreak_hold_street_v1.png"))

    var storm_context:Dictionary=main.get("_region_contexts").get("stormbreak_highlands",{})
    var storm_root:Node3D=storm_context.get("root")
    var deck:=storm_root.find_child("ContinuousBridgeDeck",true,false) as MeshInstance3D
    var bridge_ground:=Vector3(-6420,main._sample_global_terrain_height(-6420,-7500).y,-7500)
    if is_instance_valid(deck):bridge_ground=deck.global_transform*deck.get_aabb().get_center()
    print("STORMBREAK_BRIDGE_CAPTURE_TARGET|%s|ford=%s"%[bridge_ground,Vector3(-6420,main._sample_global_terrain_height(-6420,-7500).y,-7500)])
    camera.global_position=bridge_ground+Vector3(105,72,95)
    camera.look_at(bridge_ground+Vector3(-10,3,-2),Vector3.UP)
    for _frame in range(18):await process_frame
    results.append(await _capture("res://artifacts/galehorn_crossing_v1.png"))

    var tarn_ground:Vector3=main._sample_global_terrain_height(-8520,-10120)
    camera.fov=55.0
    camera.global_position=tarn_ground+Vector3(150,52,170)
    camera.look_at(tarn_ground+Vector3(0,2,15),Vector3.UP)
    for _frame in range(18):await process_frame
    results.append(await _capture("res://artifacts/blacktarn_headwater_v1.png"))

    var beacon_ground:Vector3=main._sample_global_terrain_height(-9680,-8370)
    camera.global_position=beacon_ground+Vector3(78,30,92)
    camera.look_at(beacon_ground+Vector3(0,8,0),Vector3.UP)
    for _frame in range(16):await process_frame
    results.append(await _capture("res://artifacts/stormscar_beacon_v1.png"))

    var choir_ground:Vector3=main._sample_global_terrain_height(-10060,-5170)
    camera.global_position=choir_ground+Vector3(105,28,118)
    camera.look_at(choir_ground+Vector3(0,5,0),Vector3.UP)
    for _frame in range(16):await process_frame
    results.append(await _capture("res://artifacts/shattered_choir_v1.png"))

    camera.current=false
    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    var world_map:=main.get_node("UI/WorldMap") as Control
    world_map.visible=true
    world_map.call("_set_map_scale",2)
    var map_frames:=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<1000:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    for _frame in range(6):await process_frame
    results.append(await _capture("res://artifacts/world_atlas_5region_v1.png"))

    player.global_position=main._sample_global_height(-7200,-7200)+Vector3.UP*.08
    world_map.call("_set_map_scale",0)
    map_frames=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<1000:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    for _frame in range(6):await process_frame
    results.append(await _capture("res://artifacts/stormbreak_local_map_v1.png"))

    var failures:=results.filter(func(error:int)->bool:return error!=OK).size()
    print("STORMBREAK_CAPTURE|vista=%d|hold=%d|bridge=%d|headwater=%d|beacon=%d|choir=%d|atlas=%d|local_map=%d|map_frames=%d|failures=%d"%[
        results[0],results[1],results[2],results[3],results[4],results[5],results[6],results[7],map_frames,failures,
    ])
    quit(0 if failures==0 else 1)
