extends SceneTree

# Roughly six times faster than the fastest 21 m/s horse at 60 FPS. This is
# still an aggressive streaming stress test, but it gives the kilometre-deep
# preload corridor time to behave as it does during actual continuous travel.
const STEP_METERS:=2.0


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    Engine.max_fps=0
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    var horses:=get_nodes_in_group("rideable_horse")
    if not horses.is_empty():player.mount_horse(horses[0])
    var route_id:=OS.get_environment("BROKEN_KNIGHT_STREAM_ROUTE").strip_edges().to_lower()
    if route_id.is_empty():route_id="north"
    var route:=_route_definition(route_id)
    for setup_zone_value in route.setup_regions:
        await main._ensure_streamed_region_loaded(str(setup_zone_value))
    var setup_active:=str(route.get("setup_active","starting_realm"))
    if setup_active!="starting_realm":
        await main._activate_streamed_gameplay_region(setup_active)
    var start:Vector2=route.start
    var direction:Vector2=route.direction
    var travel_frames:int=route.frames
    var expected_zone:=str(route.expected)
    var samples:Array[float]=[]
    var spikes:Array[String]=[]
    for frame_index in range(travel_frames):
        var point:=start+direction*STEP_METERS*float(frame_index)
        player.global_position=main._sample_global_height(point.x,point.y)+Vector3.UP*.08
        main.call("_update_region_streaming",.25)
        var started:=Time.get_ticks_usec()
        await process_frame
        var elapsed_ms:=float(Time.get_ticks_usec()-started)/1000.0
        samples.append(elapsed_ms)
        if elapsed_ms>=34.0:spikes.append("%d@z%.0f=%.2fms(%s)"%[frame_index,point.y,elapsed_ms,str(main.get("_region_stream_phase"))])
    while main._stream_region_loading(expected_zone) or not str(main.get("_region_stream_pipeline_zone")).is_empty() or bool(main.get("_region_gameplay_transition_busy")):
        var started:=Time.get_ticks_usec()
        await process_frame
        var elapsed_ms:=float(Time.get_ticks_usec()-started)/1000.0
        samples.append(elapsed_ms)
        if elapsed_ms>=34.0:spikes.append("settle=%.2fms(%s)"%[elapsed_ms,str(main.get("_region_stream_phase"))])
    samples.sort()
    var p95:float=samples[clampi(roundi(float(samples.size()-1)*.95),0,samples.size()-1)]
    var p99:float=samples[clampi(roundi(float(samples.size()-1)*.99),0,samples.size()-1)]
    print("NATURAL_REGION_STREAM|route=%s|expected=%s|ready=%s|active=%s|mounted=%s|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f|spikes=%d|frames=%s"%[
        route_id,expected_zone,str(main._stream_region_ready(expected_zone)),str(main.get("_active_zone_id")),str(player.is_mounted()),
        p95,p99,samples[-1],spikes.size(),",".join(spikes),
    ])
    main.free()
    for _cleanup in range(4):await process_frame
    quit()


func _route_definition(route_id:String)->Dictionary:
    match route_id:
        "west":return {"start":Vector2(-1650.0,360.0),"direction":Vector2.LEFT,"frames":1350,"expected":"western_reaches","setup_regions":[]}
        "east":return {"start":Vector2(1650.0,-360.0),"direction":Vector2.RIGHT,"frames":1350,"expected":"east_marches","setup_regions":[]}
        "glacial":return {"start":Vector2(360.0,-7450.0),"direction":Vector2.UP,"frames":1650,"expected":"glacial_range","setup_regions":["north_frontier"],"setup_active":"north_frontier"}
        "stormbreak":return {"start":Vector2(-5400.0,-1650.0),"direction":Vector2.UP,"frames":1050,"expected":"stormbreak_highlands","setup_regions":["western_reaches"],"setup_active":"western_reaches"}
        "skeld":return {"start":Vector2(-5400.0,-9000.0),"direction":Vector2.UP,"frames":900,"expected":"skeld_coast","setup_regions":["western_reaches","stormbreak_highlands"],"setup_active":"stormbreak_highlands"}
        _:return {"start":Vector2(360.0,-1650.0),"direction":Vector2.UP,"frames":1350,"expected":"north_frontier","setup_regions":[]}
