extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _place_view(main:Node,camera:Camera3D,eye:Vector2,target:Vector2,eye_height:float,target_height:float)->void:
    camera.global_position=main._sample_global_terrain_height(eye.x,eye.y)+Vector3.UP*eye_height
    camera.look_at(main._sample_global_terrain_height(target.x,target.y)+Vector3.UP*target_height,Vector3.UP)


func _place_river_view(main:Node,camera:Camera3D,eye:Vector2,target:Vector2,eye_height:float)->void:
    var world_result:Dictionary=main.get("_world_result")
    var target_surface:Vector3=world_result.river_height_sampler.call(target.x,target.y)
    target_surface.y+=1.35
    camera.global_position=main._sample_global_terrain_height(eye.x,eye.y)+Vector3.UP*eye_height
    camera.look_at(target_surface+Vector3.UP*.08,Vector3.UP)


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    player.visible=false
    player.global_position=main._sample_global_height(-1040,390)+Vector3.UP*.1
    main.get_node("UI").visible=false
    (main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D).current=false
    var camera:=Camera3D.new()
    camera.name="WaterSurfaceReviewCamera"
    camera.fov=58.0
    camera.current=true
    main.add_child(camera)
    await _settle(20)

    var failures:=0
    _place_river_view(main,camera,Vector2(-1005,312),Vector2(-1120,292),2.05)
    await _settle(14)
    if await _capture("res://artifacts/water_kingsflow_current_a_v1.png")!=OK:failures+=1
    await create_timer(1.15).timeout
    if await _capture("res://artifacts/water_kingsflow_current_b_v1.png")!=OK:failures+=1

    _place_view(main,camera,Vector2(-1080,390),Vector2(-1160,300),5.4,1.0)
    await _settle(18)
    if await _capture("res://artifacts/water_westfall_foam_v1.png")!=OK:failures+=1

    _place_view(main,camera,Vector2(2140,430),Vector2(2040,330),4.0,.65)
    await _settle(18)
    if await _capture("res://artifacts/water_eastfall_depth_v1.png")!=OK:failures+=1
    print("WATER_SURFACE_CAPTURE|shots=4|failures=%d"%failures)
    quit(0 if failures==0 else 1)
