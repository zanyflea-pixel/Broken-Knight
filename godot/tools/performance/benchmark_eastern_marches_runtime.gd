extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")
const SAMPLE_FRAMES:=90
const WARMUP_FRAMES:=120
const HITCH_MS:=25.0


func _initialize()->void:
    call_deferred("_run")


func _percentile(values:Array[float],fraction:float)->float:
    if values.is_empty():return 0.0
    return values[clampi(roundi(float(values.size()-1)*fraction),0,values.size()-1)]


func _send_key(keycode:Key,pressed:bool)->void:
    var event:=InputEventKey.new()
    event.keycode=keycode
    event.physical_keycode=keycode
    event.pressed=pressed
    Input.parse_input_event(event)


func _focus(main:Node,player:CharacterBody3D,point:Vector2)->float:
    var started:=Time.get_ticks_usec()
    player.global_position=main._sample_global_height(point.x,point.y)+Vector3.UP*.08
    if OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_DISABLE_GAMEPLAY").strip_edges()!="1":
        main._prepare_gameplay_region_for_position(point.y,point.x)
        while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    var warmup_frames:=WARMUP_FRAMES
    var warmup_override:=OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_WARMUP_FRAMES").strip_edges()
    if not warmup_override.is_empty():warmup_frames=maxi(0,int(warmup_override))
    for _frame in range(warmup_frames):
        await process_frame
    return float(Time.get_ticks_usec()-started)/1000.0


func _sample_site(main:Node,player:CharacterBody3D,site:Dictionary)->Dictionary:
    print("EASTERN_PERFORMANCE_STAGE|site=%s|stage=focus_begin"%str(site.name))
    if OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_DISABLE_MINIMAP").strip_edges()=="1":
        var minimap:=main.get_node_or_null("UI/Minimap")
        if is_instance_valid(minimap):
            minimap.visible=false
            minimap.process_mode=Node.PROCESS_MODE_DISABLED
    if OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_DISABLE_GAMEPLAY").strip_edges()=="1":
        var director:=main.get_node_or_null("GameplayDirector")
        if is_instance_valid(director):
            director.visible=false
            director.process_mode=Node.PROCESS_MODE_DISABLED
        # Keep Main processing so the renderer continues producing frames, but
        # prevent its proximity poll from scheduling the gameplay handoff that
        # this visual-only isolation deliberately excludes.
        main.set("_active_zone_id","east_marches")
    var hidden_roots:=OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_HIDE_ROOTS").strip_edges()
    if not hidden_roots.is_empty():
        var east_context:Dictionary=main.get("_region_contexts").get("east_marches",{})
        var east_root:Node3D=east_context.get("root")
        if is_instance_valid(east_root):
            for root_name in hidden_roots.split(",",false):
                var visual_root:=east_root.get_node_or_null(str(root_name).strip_edges())
                if is_instance_valid(visual_root):visual_root.visible=false
    var transition_ms:=await _focus(main,player,site.position)
    print("EASTERN_PERFORMANCE_STAGE|site=%s|stage=focus_ready|transition_ms=%.2f"%[str(site.name),transition_ms])
    player.set("_yaw",float(site.get("yaw",0.0)))
    player.get_node("CameraPivot").rotation.y=float(site.get("yaw",0.0))
    var static_sample:=OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_STATIC").strip_edges()=="1"
    if not static_sample:
        _send_key(KEY_W,true)
        _send_key(KEY_SHIFT,true)
    var samples:Array[float]=[]
    var hitches:=0
    var hitch_frames:Array[int]=[]
    for _frame in range(SAMPLE_FRAMES):
        var started:=Time.get_ticks_usec()
        await process_frame
        # frame_post_draw can stop emitting in headless isolation runs when a
        # hidden root leaves the viewport unchanged. force_sync still includes
        # queued render work and makes the benchmark deterministic.
        RenderingServer.force_sync()
        var elapsed:=float(Time.get_ticks_usec()-started)/1000.0
        samples.append(elapsed)
        if elapsed>=HITCH_MS:
            hitches+=1
            hitch_frames.append(_frame)
    if not static_sample:
        _send_key(KEY_W,false)
        _send_key(KEY_SHIFT,false)
    samples.sort()
    print("EASTERN_PERFORMANCE_SITE|name=%s|transition_ms=%.2f|p50=%.2f|p95=%.2f|p99=%.2f|max=%.2f|hitches=%d|hitch_frames=%s|draw_calls=%d|objects=%d"%[
        str(site.name),transition_ms,_percentile(samples,.50),_percentile(samples,.95),_percentile(samples,.99),samples[-1],hitches,
        str(hitch_frames),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
    ])
    return {"samples":samples,"hitches":hitches,"transition_ms":transition_ms}


func _run()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=0
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    print("EASTERN_PERFORMANCE_STAGE|stage=boot_begin")
    await main.boot_world(Callable(),false,true)
    print("EASTERN_PERFORMANCE_STAGE|stage=boot_ready")
    await main._ensure_east_region_loaded()
    print("EASTERN_PERFORMANCE_STAGE|stage=east_ready")
    var player:=main.get_node("Player") as CharacterBody3D
    var sites:Array[Dictionary]=[
        {"name":"Dawnford","position":Vector2(4440,1110),"yaw":0.0},
        {"name":"Amberfield","position":Vector2(6150,340),"yaw":2.35},
        {"name":"Ember Span","position":Vector2(7240,-160),"yaw":2.5},
        {"name":"March Keep","position":Vector2(8100,455),"yaw":2.45},
        {"name":"Cinderwatch","position":Vector2(9400,-1685),"yaw":2.35},
        {"name":"Glassmere","position":Vector2(8810,2340),"yaw":2.1},
        {"name":"Saltwatch","position":Vector2(6815,2215),"yaw":2.3},
    ]
    var requested_site:=OS.get_environment("BROKEN_KNIGHT_EAST_BENCH_SITE").strip_edges().to_lower()
    if not requested_site.is_empty():
        sites=sites.filter(func(site:Dictionary)->bool:return str(site.name).to_lower()==requested_site)
    var all_samples:Array[float]=[]
    var total_hitches:=0
    var worst_transition:=0.0
    for site in sites:
        var result:Dictionary=await _sample_site(main,player,site)
        all_samples.append_array(result.samples)
        total_hitches+=int(result.hitches)
        worst_transition=maxf(worst_transition,float(result.transition_ms))
    all_samples.sort()
    var p95:=_percentile(all_samples,.95)
    var p99:=_percentile(all_samples,.99)
    var target_met:=p95<=16.67 and p99<=25.0 and total_hitches<=maxi(2,sites.size())
    print("EASTERN_PERFORMANCE_SUMMARY|sites=%d|frames=%d|p50=%.2f|p95=%.2f|p99=%.2f|max=%.2f|hitches_over_25=%d|worst_transition_ms=%.2f|target_60fps=%s"%[
        sites.size(),all_samples.size(),_percentile(all_samples,.50),p95,p99,all_samples[-1],total_hitches,worst_transition,str(target_met).to_lower(),
    ])
    main.queue_free()
    await process_frame
    quit(0)
