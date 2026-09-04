extends SceneTree


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=24)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:CharacterBody3D=main.get_node("Player")
    (main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D).current=false
    var camera:=Camera3D.new();camera.fov=58.0;camera.current=true;main.add_child(camera)
    var profile:Dictionary=main.get("_active_profile")
    var river:Dictionary=profile.get("river_corridors",[])[0]
    var points:Array=river.get("points",[])
    var river_point:=Vector2(points[points.size()/2])
    var river_state:Dictionary=main._sample_global_water_state(river_point.x,river_point.y)
    player.global_position=Vector3(river_point.x,float(river_state.surface_y)-float(river_state.depth)+.06,river_point.y)
    await _settle(32)
    camera.global_position=player.global_position+Vector3(7.2,3.6,7.8)
    camera.look_at(player.global_position+Vector3.UP*.75,Vector3.UP)
    await _settle(18)
    var failures:=0
    if not player.is_swimming():failures+=1
    if await _capture("res://artifacts/river_swimming_v1.png")!=OK:failures+=1

    await main._ensure_skeld_region_loaded()
    main._activate_streamed_gameplay_region("skeld_coast")
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    var skeld_context:Dictionary=main.get("_region_contexts").get("skeld_coast",{})
    var basin:Dictionary=skeld_context.get("local_profile",{}).get("ocean_basins",[])[0]
    var local_z:=650.0
    var coast_x:float=main._coast_x_at_z(local_z,basin.get("coast_points",[]))
    var offset:Vector2=skeld_context.get("offset",Vector2.ZERO)
    var ocean_point:=offset+Vector2(coast_x-280.0,local_z)
    var ocean_state:Dictionary=main._sample_global_water_state(ocean_point.x,ocean_point.y)
    player.global_position=Vector3(ocean_point.x,float(ocean_state.surface_y)-float(ocean_state.depth)+.06,ocean_point.y)
    main._update_region_visual_residency(ocean_point.x,ocean_point.y)
    await _settle(36)
    camera.global_position=player.global_position+Vector3(-8.0,3.8,8.5)
    camera.look_at(player.global_position+Vector3.UP*.78,Vector3.UP)
    await _settle(18)
    if not player.is_swimming():failures+=1
    if await _capture("res://artifacts/grey_sea_swimming_v1.png")!=OK:failures+=1
    print("WATER_TRAVERSAL_CAPTURE|shots=2|failures=%d"%failures)
    quit(0 if failures==0 else 1)
