extends SceneTree

const STREAMED_ZONES:=["north_frontier","glacial_range","western_reaches","east_marches","stormbreak_highlands","skeld_coast"]


func _initialize()->void:call_deferred("_run")


func _run()->void:
    Engine.max_fps=0
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    var horses:=get_nodes_in_group("rideable_horse")
    if not horses.is_empty():player.mount_horse(horses[0])
    # Model a player who has explored the complete current atlas. Preparation
    # stays beneath a paused map; the measured section begins only after play
    # resumes at Skeld's centre.
    main.set("_map_open",true)
    paused=true
    for zone_id in STREAMED_ZONES:await main._ensure_streamed_region_loaded(zone_id)
    var destination:=Vector2(-7200.0,-14400.0)
    player.global_position=main._sample_global_height(destination.x,destination.y)+Vector3.UP*.08
    await main._activate_streamed_gameplay_region("skeld_coast")
    main.set("_map_open",false)
    paused=false
    main._update_region_visual_residency(destination.x,destination.y)
    for _warm in range(20):await process_frame
    var samples:Array[float]=[]
    for frame_index in range(360):
        var point:=destination+Vector2(sin(float(frame_index)*.031)*80.0,cos(float(frame_index)*.027)*80.0)
        player.global_position=main._sample_global_height(point.x,point.y)+Vector3.UP*.08
        main._update_region_streaming(.25)
        var started:=Time.get_ticks_usec()
        await process_frame
        samples.append(float(Time.get_ticks_usec()-started)/1000.0)
    samples.sort()
    var visible_zones:Array[String]=[]
    var sleeping_zones:Array[String]=[]
    for zone_id in STREAMED_ZONES:
        var region:=main.get_node("WorldRoot/StreamedRegions/%s"%zone_id.to_pascal_case()) as Node3D
        if region.visible:visible_zones.append(zone_id)
        else:sleeping_zones.append(zone_id)
    var starter_visible:bool=(main.get_node("WorldRoot/TownRoot") as Node3D).visible
    var p95:float=samples[clampi(roundi(float(samples.size()-1)*.95),0,samples.size()-1)]
    var p99:float=samples[clampi(roundi(float(samples.size()-1)*.99),0,samples.size()-1)]
    print("FULL_ATLAS_RESIDENCY|loaded=%d|visible=%s|sleeping=%s|starter_visible=%s|mounted=%s|active=%s|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f"%[
        STREAMED_ZONES.size(),",".join(visible_zones),",".join(sleeping_zones),str(starter_visible),str(player.is_mounted()),str(main.get("_active_zone_id")),p95,p99,samples[-1],
    ])
    main.free()
    for _cleanup in range(4):await process_frame
    quit()
