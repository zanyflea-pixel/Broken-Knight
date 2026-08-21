extends SceneTree


const DEFAULT_SAMPLE_FRAMES_PER_REGION := 150
const DEFAULT_SETTLE_FRAMES := 12
const HITCH_MS := 20.0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    # Match the desktop shortcut instead of the uncapped microbenchmarks.
    var pacing_mode := OS.get_environment("BROKEN_KNIGHT_DESKTOP_PACING").strip_edges().to_lower()
    if pacing_mode == "smooth":
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        Engine.max_fps = 120
    else:
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
        Engine.max_fps = 0
    var boot := (load("res://scenes/Boot.tscn") as PackedScene).instantiate()
    root.add_child(boot)
    var main: Node3D
    while not is_instance_valid(main):
        main = boot.get_node_or_null("Main") as Node3D
        await process_frame
    while bool(main.get("_world_streaming")) or main.get("_world_result").is_empty():
        await process_frame
    var boot_panel := boot.get_node("Overlay/Panel") as CanvasItem
    while boot_panel.visible:
        await process_frame
    await create_timer(0.1).timeout

    var player := main.get_node("Player") as CharacterBody3D
    var world_result: Dictionary = main.get("_world_result")
    var profile: Dictionary = main.get("_active_profile")
    var regions: Array[Dictionary] = []
    var spawn_site: Dictionary = profile.get("spawn_site", {})
    regions.append({"name": str(spawn_site.get("name", "Riverwatch")), "position": spawn_site.get("position", Vector2.ZERO)})
    for site_value in profile.get("town_sites", []):
        if site_value is Dictionary:
            var site: Dictionary = site_value
            regions.append({"name": str(site.get("name", "Town")), "position": site.get("position", Vector2.ZERO)})
    var requested_region := OS.get_environment("BROKEN_KNIGHT_DESKTOP_WALK_REGION").strip_edges().to_lower()
    if not requested_region.is_empty():
        regions = regions.filter(func(region: Dictionary) -> bool:
            return str(region.name).to_lower() == requested_region
        )

    var all_samples: Array[float] = []
    var total_hitches := 0
    for region in regions:
        var result := await _measure_region(player, world_result, region, main.get_node("GameplayDirector"))
        all_samples.append_array(result.samples)
        total_hitches += int(result.hitches)

    all_samples.sort()
    var p95 := _percentile(all_samples, 0.95)
    var p99 := _percentile(all_samples, 0.99)
    var max_ms := all_samples[-1] if not all_samples.is_empty() else 0.0
    print("DESKTOP_WALK_SUMMARY|refresh_hz=%.1f|regions=%d|frames=%d|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f|hitches_over_20=%d" % [
        DisplayServer.screen_get_refresh_rate(),
        regions.size(),
        all_samples.size(),
        p95,
        p99,
        max_ms,
        total_hitches,
    ])
    _send_key(KEY_W, false)
    _send_key(KEY_SHIFT, false)
    boot.queue_free()
    await process_frame
    await process_frame
    call_deferred("quit", 0 if total_hitches == 0 else 1)


func _measure_region(player: CharacterBody3D, world_result: Dictionary, region: Dictionary, gameplay_director: Node) -> Dictionary:
    var settle_frames := _environment_int("BROKEN_KNIGHT_DESKTOP_SETTLE_FRAMES", DEFAULT_SETTLE_FRAMES)
    var sample_frames := _environment_int("BROKEN_KNIGHT_DESKTOP_SAMPLE_FRAMES", DEFAULT_SAMPLE_FRAMES_PER_REGION)
    var center: Vector2 = region.position
    # The desktop opens at Riverwatch's authored spawn. Other regions begin on
    # an approach so their settlement visibility transitions are exercised.
    var start := center if str(region.name).to_lower() == "riverwatch" else center + Vector2(0.0, 42.0)
    if str(region.name).to_lower() != "riverwatch":
        var ground: Vector3 = world_result.height_sampler.call(start.x, start.y)
        player.global_position = ground + Vector3.UP * player.hover_height
        player.set("_yaw", 0.0)
        player.get_node("CameraPivot").rotation.y = 0.0
    player.set("_current_move_speed", 0.0)

    # Only a handful of settling frames are intentional: this catches visual
    # resources that first become visible as the player reaches a settlement.
    for frame_index in settle_frames:
        await process_frame
        await RenderingServer.frame_post_draw

    _send_key(KEY_W, true)
    _send_key(KEY_SHIFT, true)
    var samples: Array[float] = []
    var hitch_frames: Array[String] = []
    for frame_index in sample_frames:
        var started := Time.get_ticks_usec()
        await process_frame
        await RenderingServer.frame_post_draw
        var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
        samples.append(elapsed_ms)
        if elapsed_ms >= HITCH_MS:
            var stream_diagnostics:Dictionary=gameplay_director.get_stream_diagnostics() if gameplay_director.has_method("get_stream_diagnostics") else {}
            hitch_frames.append("%d:%.2f:%s" % [frame_index, elapsed_ms, JSON.stringify(stream_diagnostics)])
    _send_key(KEY_W, false)
    _send_key(KEY_SHIFT, false)
    samples.sort()
    print("DESKTOP_WALK_REGION|name=%s|p95_ms=%.2f|p99_ms=%.2f|max_ms=%.2f|hitches=%d|draw_calls=%d|objects=%d|hitch_frames=%s" % [
        str(region.name),
        _percentile(samples, 0.95),
        _percentile(samples, 0.99),
        samples[-1],
        hitch_frames.size(),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
        ",".join(hitch_frames),
    ])
    return {"samples": samples, "hitches": hitch_frames.size()}


func _percentile(values: Array[float], percentile: float) -> float:
    if values.is_empty():
        return 0.0
    return values[clampi(roundi(float(values.size() - 1) * percentile), 0, values.size() - 1)]


func _environment_int(name: String, fallback: int) -> int:
    var value := OS.get_environment(name).strip_edges()
    return maxi(1, int(value)) if value.is_valid_int() else fallback


func _send_key(keycode: Key, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = pressed
    Input.parse_input_event(event)
