extends SceneTree


const WARMUP_FRAMES:=90
const SAMPLE_FRAMES:=480


func _initialize()->void:
    call_deferred("_benchmark")


func _benchmark()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=0
    var started:=Time.get_ticks_usec()
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    main.get_node("UI").visible=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var ready_ms:=float(Time.get_ticks_usec()-started)/1000.0
    var player:=main.get_node("Player") as CharacterBody3D
    player.set_input_enabled(false)
    var world_result:Dictionary=main.get("_world_result")
    if world_result.is_empty() or not world_result.get("height_sampler",Callable()).is_valid():
        push_error("World benchmark could not obtain a valid height sampler")
        main.free()
        quit(1)
        return
    var route:=OS.get_environment("BROKEN_KNIGHT_BENCHMARK_ROUTE").to_lower()
    if route.is_empty():route="riverwatch"
    var start:=Vector2(-420.0,70.0)
    var finish:=Vector2(260.0,220.0)
    if route=="starter":
        # Main-street acceptance route: town crossroads, river approach,
        # Riverwatch Bridge and the first destination at Ferrywatch Post.
        start=Vector2(-420.0,145.0)
        finish=Vector2(-300.0,-285.0)
    elif route=="crownspire":
        start=Vector2(250.0,-2180.0)
        finish=Vector2(250.0,-2575.0)
    elif route=="glacial":
        await main._ensure_glacial_region_loaded()
        main._prepare_gameplay_region_for_position(-12300.0)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
        start=Vector2(-360.0,-12300.0)
        finish=Vector2(-470.0,-12760.0)
    elif route=="western":
        await main._ensure_western_region_loaded()
        main._prepare_gameplay_region_for_position(-420.0,-4100.0)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
        start=Vector2(-3880.0,-430.0)
        finish=Vector2(-4480.0,-500.0)
    elif route=="stormbreak":
        await main._ensure_stormbreak_region_loaded()
        main._prepare_gameplay_region_for_position(-7540.0,-7420.0)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
        # Stormbreak Hold's main street toward Galehorn Crossing exercises the
        # densest highland town, its vegetation chunks, and the major road.
        start=Vector2(-7560.0,-7540.0)
        finish=Vector2(-6420.0,-7500.0)
    elif route=="skeld":
        await main._ensure_skeld_region_loaded()
        main._prepare_gameplay_region_for_position(-13980.0,-7920.0)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
        # Frostharbor market through the river approach exercises the densest
        # coastal settlement, ocean mesh, regional props, and Skeld Bridge.
        start=Vector2(-7920.0,-13980.0)
        finish=Vector2(-7920.0,-13619.0)
    elif route=="eastern":
        await main._ensure_east_region_loaded()
        main._prepare_gameplay_region_for_position(-1685.0,9400.0)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
        # Cinderwatch's beacon, signal yard, encounter ground and volcanic
        # vegetation are the most demanding completed Eastern composition.
        start=Vector2(9360.0,-1660.0)
        finish=Vector2(9660.0,-1940.0)
    # Use a real walking cadence (roughly 12 m/s at 60 fps), not teleport-sized
    # per-frame steps. This still crosses a minimap refresh boundary during the
    # sample and exercises local gameplay/collision streaming.
    var route_vector:Vector2=(finish-start).normalized()
    for frame_index in range(WARMUP_FRAMES):
        _place_player(player,main,start+route_vector*float(frame_index)*.20)
        await process_frame
        await RenderingServer.frame_post_draw
    var samples:Array[float]=[]
    var spike_frames:Array[String]=[]
    var spike_diagnostics:Array[String]=[]
    var worst_frame_index:=-1
    var worst_frame_ms:=0.0
    var sample_started:=Time.get_ticks_usec()
    var trace_visibility:=OS.get_environment("BROKEN_KNIGHT_BENCHMARK_TRACE")=="1"
    var previous_draw_calls:=int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
    for frame_index in range(SAMPLE_FRAMES):
        _place_player(player,main,start+route_vector*float(WARMUP_FRAMES+frame_index)*.20)
        var frame_started:=Time.get_ticks_usec()
        await process_frame
        await RenderingServer.frame_post_draw
        var frame_ms:=float(Time.get_ticks_usec()-frame_started)/1000.0
        var current_draw_calls:=int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
        if trace_visibility and absi(current_draw_calls-previous_draw_calls)>=3:
            var trace_point:=start+route_vector*float(WARMUP_FRAMES+frame_index)*.20
            print("WORLD_RUNTIME_VISIBILITY|frame=%d|point=%.1f,%.1f|draw_calls=%d|delta=%+d|frame_ms=%.2f"%[
                frame_index,trace_point.x,trace_point.y,current_draw_calls,current_draw_calls-previous_draw_calls,frame_ms,
            ])
        previous_draw_calls=current_draw_calls
        samples.append(frame_ms)
        if frame_ms>worst_frame_ms:
            worst_frame_ms=frame_ms
            worst_frame_index=frame_index
        if frame_ms>=25.0:
            var frame_point:=start+route_vector*float(WARMUP_FRAMES+frame_index)*.20
            spike_frames.append("%d@%.1f,%.1f=%.2fms"%[frame_index,frame_point.x,frame_point.y,frame_ms])
            var diagnostics:Dictionary=main.get_node("GameplayDirector").get_stream_diagnostics()
            var collision:Dictionary=diagnostics.get("collision",{})
            spike_diagnostics.append("%d:c%d/p%d/%.2fms/q%d/d%d/o%d"%[
                frame_index,int(collision.get("candidates",0)),int(collision.get("physics_changes",0)),
                float(collision.get("apply_ms",0.0)),int(diagnostics.get("queue",0)),
                int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
                int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
            ])
    var elapsed_ms:=float(Time.get_ticks_usec()-sample_started)/1000.0
    samples.sort()
    var average_ms:=elapsed_ms/float(SAMPLE_FRAMES)
    var p50_ms:float=samples[clampi(roundi(float(samples.size()-1)*.50),0,samples.size()-1)]
    var p95_ms:float=samples[clampi(roundi(float(samples.size()-1)*.95),0,samples.size()-1)]
    var p99_ms:float=samples[clampi(roundi(float(samples.size()-1)*.99),0,samples.size()-1)]
    var max_ms:float=samples[-1]
    var average_fps:=1000.0/maxf(.001,average_ms)
    print("WORLD_RUNTIME_BENCHMARK|route=%s|ready_ms=%.1f|average_fps=%.1f|average_ms=%.2f|p50_ms=%.2f|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f|max_frame=%d|draw_calls=%d|objects=%d|vertices=%d"%[
        route,ready_ms,average_fps,average_ms,p50_ms,p95_ms,p99_ms,max_ms,worst_frame_index,
        int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
    ])
    print("WORLD_RUNTIME_SPIKES|route=%s|count=%d|frames=%s"%[route,spike_frames.size(),",".join(spike_frames)])
    print("WORLD_RUNTIME_SPIKE_DIAGNOSTICS|route=%s|%s"%[route,",".join(spike_diagnostics)])
    var minimap:=main.get_node_or_null("UI/Minimap")
    if minimap!=null and minimap.has_method("get_draw_profile"):
        print("WORLD_RUNTIME_MINIMAP_PROFILE|%s"%JSON.stringify(minimap.get_draw_profile()))
    main.free()
    quit()


func _place_player(player:CharacterBody3D,main:Node3D,point:Vector2)->void:
    var ground:Vector3=main._sample_global_height(point.x,point.y)
    player.global_position=ground+Vector3.UP*.08
