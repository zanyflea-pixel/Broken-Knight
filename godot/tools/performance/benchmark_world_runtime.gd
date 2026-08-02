extends SceneTree


const WARMUP_FRAMES:=45
const SAMPLE_FRAMES:=180


func _initialize()->void:
    call_deferred("_benchmark")


func _benchmark()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=0
    var started:=Time.get_ticks_usec()
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    var ready_ms:=float(Time.get_ticks_usec()-started)/1000.0
    var player:=main.get_node("Player") as CharacterBody3D
    var world_result:Dictionary=main.get("_world_result")
    var route:=OS.get_environment("BROKEN_KNIGHT_BENCHMARK_ROUTE").to_lower()
    if route.is_empty():route="riverwatch"
    var start:=Vector2(-420.0,70.0)
    var finish:=Vector2(260.0,220.0)
    if route=="crownspire":
        start=Vector2(250.0,-2180.0)
        finish=Vector2(250.0,-2575.0)
    for frame_index in range(WARMUP_FRAMES):
        _place_player(player,world_result,start.lerp(finish,float(frame_index)/float(WARMUP_FRAMES)))
        await process_frame
        await RenderingServer.frame_post_draw
    var samples:Array[float]=[]
    var sample_started:=Time.get_ticks_usec()
    for frame_index in range(SAMPLE_FRAMES):
        var progress:=float(frame_index)/float(SAMPLE_FRAMES-1)
        _place_player(player,world_result,start.lerp(finish,progress))
        var frame_started:=Time.get_ticks_usec()
        await process_frame
        await RenderingServer.frame_post_draw
        samples.append(float(Time.get_ticks_usec()-frame_started)/1000.0)
    var elapsed_ms:=float(Time.get_ticks_usec()-sample_started)/1000.0
    samples.sort()
    var average_ms:=elapsed_ms/float(SAMPLE_FRAMES)
    var p95_ms:float=samples[clampi(roundi(float(samples.size()-1)*.95),0,samples.size()-1)]
    var average_fps:=1000.0/maxf(.001,average_ms)
    print("WORLD_RUNTIME_BENCHMARK|route=%s|ready_ms=%.1f|average_fps=%.1f|average_ms=%.2f|p95_ms=%.2f|draw_calls=%d|objects=%d|vertices=%d"%[
        route,ready_ms,average_fps,average_ms,p95_ms,
        int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
    ])
    main.free()
    quit()


func _place_player(player:CharacterBody3D,world_result:Dictionary,point:Vector2)->void:
    var ground:Vector3=world_result.height_sampler.call(point.x,point.y)
    player.global_position=ground+Vector3.UP*.08
