extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=18)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _focus(main:Node,player:CharacterBody3D,x:float,z:float)->void:
    player.global_position=main._sample_global_height(x,z)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(z,x)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(12)


func _ground_view(camera:Camera3D,main:Node,from_x:float,from_z:float,target_x:float,target_z:float,target_height:float)->void:
    camera.fov=68.0
    camera.global_position=main._sample_global_terrain_height(from_x,from_z)+Vector3.UP*2.25
    camera.look_at(main._sample_global_terrain_height(target_x,target_z)+Vector3.UP*target_height,Vector3.UP)


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_east_region_loaded()
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    player.visible=false
    main.get_node("UI").visible=false
    var gameplay_camera:=main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    gameplay_camera.current=false
    var camera:=Camera3D.new()
    camera.name="EasternCorrectionCamera"
    camera.current=true
    main.add_child(camera)
    var results:Array[int]=[]

    await _focus(main,player,4500,1115)
    _ground_view(camera,main,4500,1115,4500,895,5.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_dawnford_player_v2.png"))

    await _focus(main,player,9400,-1685)
    _ground_view(camera,main,9400,-1685,9560,-1840,10.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_cinderwatch_player_v2.png"))

    await _focus(main,player,8810,2340)
    _ground_view(camera,main,8810,2340,8980,2460,1.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_glassmere_player_v2.png"))
    var mere:Vector3=main._sample_global_terrain_height(8980,2460)
    camera.fov=56.0
    camera.global_position=mere+Vector3(-180,62,158)
    camera.look_at(mere+Vector3(0,-1,0),Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_glassmere_v2.png"))

    await _focus(main,player,9920,-2450)
    _ground_view(camera,main,9920,-2450,10120,-2640,12.0)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_embercrag_player_v1.png"))
    var crown:Vector3=main._sample_global_terrain_height(10120,-2640)
    camera.fov=54.0
    camera.global_position=crown+Vector3(-190,92,180)
    camera.look_at(crown+Vector3.UP*5.0,Vector3.UP)
    await _settle(22)
    results.append(await _capture("res://artifacts/eastern_embercrag_v1.png"))

    var failures:=results.filter(func(error:int)->bool:return error!=OK).size()
    print("EASTERN_VISUAL_CORRECTION_CAPTURE|dawnford=%d|cinderwatch=%d|glassmere_player=%d|glassmere=%d|embercrag_player=%d|embercrag=%d|failures=%d"%[
        results[0],results[1],results[2],results[3],results[4],results[5],failures,
    ])
    quit(0 if failures==0 else 1)
