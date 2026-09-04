extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _focus(main:Node,player:CharacterBody3D,at:Vector2)->void:
    player.global_position=main._sample_global_height(at.x,at.y)+Vector3.UP*.08
    main._update_region_visual_residency(at.x,at.y)
    main._prepare_gameplay_region_for_position(at.y,at.x)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    await _settle(12)


func _ground_view(camera:Camera3D,main:Node,eye:Vector2,target:Vector2,target_height:float)->void:
    camera.fov=67.0
    camera.global_position=main._sample_global_terrain_height(eye.x,eye.y)+Vector3.UP*2.15
    camera.look_at(main._sample_global_terrain_height(target.x,target.y)+Vector3.UP*target_height,Vector3.UP)


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_east_region_loaded()
    if str(main.get("_active_zone_id"))!="east_marches":
        main._activate_streamed_gameplay_region("east_marches")
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    player.visible=false
    main.get_node("UI").visible=false
    (main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D).current=false
    var camera:=Camera3D.new()
    camera.name="EasternCompositionReviewCamera"
    camera.current=true
    main.add_child(camera)

    var shots:=[
        {"name":"dawnford_arrival","eye":Vector2(4274,1084),"target":Vector2(4295,1058),"height":1.6},
        {"name":"amberfield_verge","eye":Vector2(6258,559),"target":Vector2(6270,532),"height":1.8},
        {"name":"march_keep_approach","eye":Vector2(8128,430),"target":Vector2(8128,400),"height":2.2},
        {"name":"saltwatch_yard","eye":Vector2(6807,2478),"target":Vector2(6815,2450),"height":1.7},
        {"name":"cinderwatch_survey","eye":Vector2(9420,-1681),"target":Vector2(9438,-1707),"height":1.8},
    ]
    var failures:=0
    for shot in shots:
        var eye:Vector2=shot.eye
        var target:Vector2=shot.target
        await _focus(main,player,eye)
        _ground_view(camera,main,eye,target,float(shot.height))
        await _settle(24)
        var error:=await _capture("res://artifacts/eastern_%s_v1.png"%str(shot.name))
        if error!=OK:failures+=1
    print("EASTERN_PLAYER_COMPOSITION_CAPTURE|shots=%d|failures=%d"%[shots.size(),failures])
    quit(0 if failures==0 else 1)
