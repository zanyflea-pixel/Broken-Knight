extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=0
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await create_timer(2.0).timeout
    var player:=main.get_node("Player") as Node3D
    var world_result:Dictionary=main.get("_world_result")
    var sample_height:Callable=world_result.terrain_height_sampler
    var start:=Vector2(player.global_position.x,player.global_position.z)
    var destination:=Vector2(250.0,-2450.0)
    var frame_times:=PackedFloat32Array()
    var draw_total:=0
    var previous_usec:=Time.get_ticks_usec()
    for frame_index in range(480):
        var progress:=float(frame_index)/479.0
        var point:=start.lerp(destination,progress)
        var ground:Vector3=sample_height.call(point.x,point.y)
        player.global_position=ground+Vector3.UP*.12
        await process_frame
        var now_usec:=Time.get_ticks_usec()
        frame_times.append(float(now_usec-previous_usec)/1000.0)
        previous_usec=now_usec
        draw_total+=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
    frame_times.sort()
    var total:=0.0
    var over_budget:=0
    for frame_ms in frame_times:
        total+=frame_ms
        if frame_ms>16.67:over_budget+=1
    print("TRAVERSAL_BENCHMARK|avg_ms=%.2f|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f|over_16_7=%d|avg_draw_calls=%d"%[
        total/maxf(1.0,float(frame_times.size())),
        _percentile(frame_times,.95),
        _percentile(frame_times,.99),
        frame_times[-1] if not frame_times.is_empty() else 0.0,
        over_budget,
        draw_total/maxi(1,frame_times.size()),
    ])
    main.free()
    quit()


func _percentile(values:PackedFloat32Array,percent:float)->float:
    if values.is_empty():return 0.0
    return values[clampi(roundi(float(values.size()-1)*percent),0,values.size()-1)]
