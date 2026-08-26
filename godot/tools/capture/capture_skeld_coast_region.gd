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


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_western_region_loaded()
    await main._ensure_north_region_loaded()
    await main._ensure_stormbreak_region_loaded()
    await main._ensure_skeld_region_loaded()
    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    player.global_position=main._sample_global_height(-7920,-13980)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-13980,-7920)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    player.visible=false
    main.get_node("UI").visible=false
    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="SkeldReviewCamera"
    camera.fov=54.0
    camera.current=true
    main.add_child(camera)

    var results:Array[int]=[]
    var region_target:Vector3=main._sample_global_terrain_height(-7920,-14200)+Vector3.UP*24.0
    camera.global_position=region_target+Vector3(760,290,880)
    camera.look_at(region_target+Vector3(-220,2,-130),Vector3.UP)
    await _settle(30)
    results.append(await _capture("res://artifacts/skeld_coast_aerial_v1.png"))

    var harbor_ground:Vector3=main._sample_global_terrain_height(-8000,-13980)
    await _focus_site(main,player,-8000,-13980)
    camera.fov=58.0
    camera.global_position=harbor_ground+Vector3(105,25,128)
    camera.look_at(harbor_ground+Vector3(-26,4,8),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/frostharbor_street_v1.png"))

    var dock_ground:Vector3=Vector3(-8480,-.60,-13900)
    await _focus_site(main,player,-8440,-13900)
    camera.global_position=dock_ground+Vector3(130,40,122)
    camera.look_at(dock_ground+Vector3(0,5,0),Vector3.UP)
    await _settle()
    results.append(await _capture("res://artifacts/frostharbor_dock_v1.png"))

    var skeld_context:Dictionary=main.get("_region_contexts").get("skeld_coast",{})
    var skeld_root:Node3D=skeld_context.get("root")
    var deck:=skeld_root.find_child("ContinuousBridgeDeck",true,false) as MeshInstance3D
    var bridge_ground:=Vector3(-7920,main._sample_global_terrain_height(-7920,-13619).y,-13619)
    await _focus_site(main,player,-7920,-13619)
    if is_instance_valid(deck):bridge_ground=deck.global_transform*deck.get_aabb().get_center()
    camera.global_position=bridge_ground+Vector3(96,48,118)
    camera.look_at(bridge_ground+Vector3(-8,2,-3),Vector3.UP)
    await _settle()
    results.append(await _capture("res://artifacts/skeld_bridge_v1.png"))

    var headwater_ground:Vector3=main._sample_global_terrain_height(-4780,-16870)
    await _focus_site(main,player,-4780,-16870)
    camera.fov=55.0
    camera.global_position=headwater_ground+Vector3(150,58,165)
    camera.look_at(headwater_ground+Vector3(-34,-1,32),Vector3.UP)
    await _settle()
    results.append(await _capture("res://artifacts/rimeglass_headwater_v1.png"))

    var lighthouse_ground:Vector3=main._sample_global_terrain_height(-8710,-16710)
    await _focus_site(main,player,-8710,-16710)
    camera.global_position=lighthouse_ground+Vector3(112,38,126)
    camera.look_at(lighthouse_ground+Vector3(0,12,0),Vector3.UP)
    await _settle()
    results.append(await _capture("res://artifacts/cape_keld_lighthouse_v1.png"))

    var chapel_ground:Vector3=main._sample_global_terrain_height(-9050,-12660)
    await _focus_site(main,player,-9050,-12660)
    camera.global_position=chapel_ground+Vector3(98,30,116)
    camera.look_at(chapel_ground+Vector3(0,5,0),Vector3.UP)
    await _settle()
    results.append(await _capture("res://artifacts/whalebone_chapel_v1.png"))

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
    results.append(await _capture("res://artifacts/world_atlas_6region_v1.png"))

    player.global_position=main._sample_global_height(-7920,-13980)+Vector3.UP*.08
    world_map.call("_set_map_scale",0)
    map_frames=0
    while (world_map.get("_terrain_texture")==null or int(world_map.get("_terrain_sample_row"))>=0 or int(world_map.get("_terrain_color_row"))>=0) and map_frames<1200:
        await process_frame
        map_frames+=1
    world_map.queue_redraw()
    await _settle(8)
    results.append(await _capture("res://artifacts/skeld_coast_local_map_v1.png"))

    var failures:=results.filter(func(error:int)->bool:return error!=OK).size()
    print("SKELD_CAPTURE|aerial=%d|harbor=%d|dock=%d|bridge=%d|headwater=%d|lighthouse=%d|chapel=%d|atlas=%d|local_map=%d|map_frames=%d|failures=%d"%[
        results[0],results[1],results[2],results[3],results[4],results[5],results[6],results[7],results[8],map_frames,failures,
    ])
    quit(0 if failures==0 else 1)
