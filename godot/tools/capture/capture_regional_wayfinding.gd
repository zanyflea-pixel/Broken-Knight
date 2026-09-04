extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _settle(frames:int=20)->void:
    for _frame in range(frames):await process_frame


func _capture(path:String)->int:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _find_sign(settlement:String)->Node3D:
    for candidate in get_nodes_in_group("regional_travel_sign"):
        if candidate is Node3D and str(candidate.get_meta("settlement",""))==settlement:
            return candidate as Node3D
    return null


func _activate(main:Node,zone_id:String,position:Vector3)->void:
    if zone_id!="starting_realm":
        await main._ensure_streamed_region_loaded(zone_id)
    if str(main.get("_active_zone_id"))!=zone_id:
        main._activate_streamed_gameplay_region(zone_id)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    main._update_region_visual_residency(position.x,position.z)
    await _settle(16)


func _frame_sign(camera:Camera3D,sign:Node3D)->bool:
    var labels:=sign.find_children("*","Label3D",true,false)
    if labels.is_empty():return false
    var approach_2d:Vector2=sign.get_meta("observer_direction",Vector2(0,1))
    var approach:=Vector3(approach_2d.x,0,approach_2d.y).normalized()
    camera.fov=56.0
    camera.global_position=sign.global_position+approach*9.5+Vector3.UP*3.0
    camera.look_at(sign.global_position+Vector3.UP*2.7,Vector3.UP)
    return true


func _run()->void:
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    player.visible=false
    main.get_node("UI").visible=false
    (main.get_node("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D).current=false
    var camera:=Camera3D.new()
    camera.name="RegionalWayfindingReviewCamera"
    camera.current=true
    main.add_child(camera)

    var shots:=[
        {"zone":"starting_realm","settlement":"Riverwatch","file":"riverwatch"},
        {"zone":"western_reaches","settlement":"Rainhaven","file":"rainhaven"},
        {"zone":"glacial_range","settlement":"Icewatch Hold","file":"icewatch"},
        {"zone":"east_marches","settlement":"Dawnford","file":"dawnford"},
    ]
    var failures:=0
    for shot in shots:
        var zone_id:=str(shot.zone)
        if zone_id!="starting_realm":await main._ensure_streamed_region_loaded(zone_id)
        var sign:=_find_sign(str(shot.settlement))
        if sign==null:
            failures+=1
            continue
        player.global_position=sign.global_position+Vector3(0,.1,8)
        await _activate(main,zone_id,sign.global_position)
        camera.current=true
        if not _frame_sign(camera,sign):
            failures+=1
            continue
        print("WAYFINDING_SHOT|zone=%s|settlement=%s|sign=%s|camera=%s|active=%s|visible=%s"%[
            zone_id,str(shot.settlement),sign.global_position,camera.global_position,
            str(main.get("_active_zone_id")),sign.is_visible_in_tree(),
        ])
        await _settle(24)
        if await _capture("res://artifacts/wayfinding_%s_v1.png"%str(shot.file))!=OK:failures+=1
    print("REGIONAL_WAYFINDING_CAPTURE|shots=%d|failures=%d"%[shots.size(),failures])
    quit(0 if failures==0 else 1)
