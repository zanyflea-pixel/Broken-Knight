extends SceneTree


const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 240
const ROUTE_START := Vector2(-420.0, 145.0)
const MAX_P95_MS:=21.5
const MAX_P99_MS:=27.0
const MAX_OVER_20_MS:=12


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var diagnostics:=OS.get_environment("BROKEN_KNIGHT_WALK_DIAGNOSTICS")=="1"
    if diagnostics:OS.set_environment("BROKEN_KNIGHT_PROFILE_MINIMAP","1")
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 60
    var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled", false)
    root.add_child(main)
    await main.boot_world(Callable(), false, true)

    var player := main.get_node("Player") as CharacterBody3D
    var visual := player.get_node("Visual")
    var director := main.get_node("GameplayDirector")
    var minimap := main.get_node("UI/Minimap")
    player.sprint_speed = 12.0

    var sampler_totals := {
        "height_us": 0,
        "height_calls": 0,
        "walkable_us": 0,
        "walkable_calls": 0,
        "structure_us": 0,
        "structure_calls": 0,
    }
    var height_sampler: Callable = player.get("_height_sampler")
    var walkable_sampler: Callable = player.get("_walkable_sampler")
    var structure_sampler: Callable = player.get("_structure_height_sampler")
    player.set("_height_sampler", func(x: float, z: float) -> Vector3:
        var started := Time.get_ticks_usec()
        var result: Vector3 = height_sampler.call(x, z)
        sampler_totals.height_us += Time.get_ticks_usec() - started
        sampler_totals.height_calls += 1
        return result
    )
    player.set("_walkable_sampler", func(x: float, z: float) -> bool:
        var started := Time.get_ticks_usec()
        var result: bool = walkable_sampler.call(x, z)
        sampler_totals.walkable_us += Time.get_ticks_usec() - started
        sampler_totals.walkable_calls += 1
        return result
    )
    player.set("_structure_height_sampler", func(x: float, z: float, y: float) -> float:
        var started := Time.get_ticks_usec()
        var result: float = structure_sampler.call(x, z, y)
        sampler_totals.structure_us += Time.get_ticks_usec() - started
        sampler_totals.structure_calls += 1
        return result
    )

    var baseline:Dictionary=await _measure_case("baseline",player,visual,director,minimap,sampler_totals,true,true,true)
    if diagnostics:
        await _measure_case("no_hero_visual",player,visual,director,minimap,sampler_totals,false,true,true)
        await _measure_case("no_gameplay_stream",player,visual,director,minimap,sampler_totals,true,false,true)
        await _measure_case("no_minimap",player,visual,director,minimap,sampler_totals,true,true,false)

    _send_key(KEY_UP, false)
    _send_key(KEY_SHIFT, false)
    main.free()
    var passed:bool=float(baseline.p95_ms)<=MAX_P95_MS and float(baseline.p99_ms)<=MAX_P99_MS and int(baseline.over20)<=MAX_OVER_20_MS and float(baseline.distance)>=40.0
    print("ACTUAL_WALK_BUDGET|%s|p95_limit_ms=%.1f|p99_limit_ms=%.1f|over20_limit=%d"%["PASS" if passed else "FAIL",MAX_P95_MS,MAX_P99_MS,MAX_OVER_20_MS])
    quit(0 if passed else 1)


func _measure_case(
    label: String,
    player: CharacterBody3D,
    visual: Node,
    director: Node,
    minimap: CanvasItem,
    sampler_totals: Dictionary,
    visual_enabled: bool,
    director_enabled: bool,
    minimap_enabled: bool
) -> Dictionary:
    visual.process_mode = Node.PROCESS_MODE_INHERIT if visual_enabled else Node.PROCESS_MODE_DISABLED
    director.process_mode = Node.PROCESS_MODE_INHERIT if director_enabled else Node.PROCESS_MODE_DISABLED
    minimap.process_mode = Node.PROCESS_MODE_INHERIT if minimap_enabled else Node.PROCESS_MODE_DISABLED
    var ground: Vector3 = player.get("_height_sampler").call(ROUTE_START.x, ROUTE_START.y)
    player.global_position = ground + Vector3.UP * player.hover_height
    player.set("_current_move_speed", 0.0)
    sampler_totals.height_us = 0
    sampler_totals.height_calls = 0
    sampler_totals.walkable_us = 0
    sampler_totals.walkable_calls = 0
    sampler_totals.structure_us = 0
    sampler_totals.structure_calls = 0
    if minimap.has_method("reset_draw_profile"):
        minimap.reset_draw_profile()
    # Arrow input is the desktop regression path: unlike W it also enters
    # Godot's UI navigation unless the player controller consumes the event.
    _send_key(KEY_UP, true)
    _send_key(KEY_SHIFT, true)
    for frame_index in WARMUP_FRAMES:
        await process_frame
        await RenderingServer.frame_post_draw

    var start_position := player.global_position
    var samples: Array[float] = []
    for frame_index in SAMPLE_FRAMES:
        var started := Time.get_ticks_usec()
        await process_frame
        await RenderingServer.frame_post_draw
        samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
    _send_key(KEY_UP, false)
    _send_key(KEY_SHIFT, false)
    samples.sort()
    var average := float(samples.reduce(func(total: float, value: float) -> float: return total + value, 0.0)) / float(samples.size())
    var p95: float = samples[roundi(float(samples.size() - 1) * 0.95)]
    var p99: float = samples[roundi(float(samples.size() - 1) * 0.99)]
    var over_budget := samples.filter(func(value: float) -> bool: return value > 20.0).size()
    print("ACTUAL_WALK_BENCHMARK|case=%s|avg_ms=%.2f|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f|over20=%d|distance=%.1f|height_avg_us=%.1f|walkable_avg_us=%.1f|structure_avg_us=%.1f|draw_calls=%d|objects=%d" % [
        label,
        average,
        p95,
        p99,
        samples[-1],
        over_budget,
        Vector2(player.global_position.x - start_position.x, player.global_position.z - start_position.z).length(),
        _average_sampler_usec(sampler_totals.height_us, sampler_totals.height_calls),
        _average_sampler_usec(sampler_totals.walkable_us, sampler_totals.walkable_calls),
        _average_sampler_usec(sampler_totals.structure_us, sampler_totals.structure_calls),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
    ])
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_MINIMAP")=="1" and minimap.has_method("get_draw_profile"):
        print("MINIMAP_DRAW_PROFILE|case=%s|average_us=%s"%[label,str(minimap.get_draw_profile())])
    return {
        "p95_ms":p95,
        "p99_ms":p99,
        "over20":over_budget,
        "distance":Vector2(player.global_position.x-start_position.x,player.global_position.z-start_position.z).length(),
    }


func _average_sampler_usec(total: int, calls: int) -> float:
    return float(total) / float(maxi(1, calls))


func _send_key(keycode: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    Input.parse_input_event(event)
