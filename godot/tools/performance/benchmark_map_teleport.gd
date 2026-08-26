extends SceneTree


const TARGETS:Array[Vector2]=[
    Vector2(-420.0,145.0),
    # Authored settlement shelves inside the streamed regions.  These must
    # stay beyond the seamless seam bands so the benchmark actually measures
    # the region named by each alias rather than a neighboring starter tile.
    Vector2(-470.0,-9320.0), # Pinewatch, north_frontier
    Vector2(-4750.0,-180.0), # Oakrest, western_reaches
    Vector2(-360.0,-12300.0),
    Vector2(-7420.0,-7540.0),
    Vector2(-7920.0,-13980.0),
    Vector2(9400.0,-1685.0),
]


func _selected_targets()->Array[Vector2]:
    var selector:=OS.get_environment("BROKEN_KNIGHT_MAP_TELEPORT_TARGET").strip_edges().to_lower()
    if selector.is_empty() or selector=="all":return TARGETS.duplicate()
    var aliases:={
        "starter":0,"riverwatch":0,"northwood":1,"western":2,"glacial":3,
        "stormbreak":4,"skeld":5,"east":6,"cinderwatch":6,
    }
    if aliases.has(selector):return [TARGETS[int(aliases[selector])]]
    if selector.is_valid_int():
        var index:=clampi(selector.to_int(),0,TARGETS.size()-1)
        return [TARGETS[index]]
    push_warning("Unknown teleport benchmark target '%s'; running all targets."%selector)
    return TARGETS.duplicate()


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=60
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    # A few simulation frames are enough to drain deferred startup work. Do
    # not block on a headless post-draw signal here: on some Windows drivers it
    # can stall indefinitely before the test reaches its first sample.
    for _frame in range(5):
        await process_frame

    var worst_first_frame:=0.0
    var worst_protected:=0.0
    var targets:=_selected_targets()
    print("MAP_TELEPORT_SELECTION|targets=%d|selector=%s"%[
        targets.size(),OS.get_environment("BROKEN_KNIGHT_MAP_TELEPORT_TARGET"),
    ])
    for target in targets:
        main.call("_set_map_open",true)
        var map:Control=main.get_node("UI/WorldMap")
        print("MAP_TELEPORT_MAP_STATE|sample_row=%d|color_row=%d|texture=%s"%[
            int(map.get("_terrain_sample_row")),int(map.get("_terrain_color_row")),str(map.get("_terrain_texture")!=null),
        ])
        var started:=Time.get_ticks_usec()
        await main.call("_teleport_from_world_map",target)
        var protected_ms:=float(Time.get_ticks_usec()-started)/1000.0
        worst_protected=maxf(worst_protected,protected_ms)
        var first_frame_started:=Time.get_ticks_usec()
        await process_frame
        var first_frame_ms:=float(Time.get_ticks_usec()-first_frame_started)/1000.0
        worst_first_frame=maxf(worst_first_frame,first_frame_ms)
        var stream_diagnostics:Dictionary=main.get_node("GameplayDirector").get_stream_diagnostics()
        print("MAP_TELEPORT_SAMPLE|target=%.0f,%.0f|protected_ms=%.2f|first_unpaused_ms=%.2f|queue=%d"%[
            target.x,target.y,protected_ms,first_frame_ms,int(stream_diagnostics.get("queue",-1)),
        ])
        for _settle in range(4):
            await process_frame

    # Measure the first controllable main-loop frame. GPU frame timing belongs
    # in the in-engine performance overlay; frame_post_draw can stall forever
    # under the Windows headless driver and made this automated check flaky.
    var passed:=worst_first_frame<=34.0
    print("MAP_TELEPORT_BUDGET|%s|worst_protected_ms=%.2f|worst_first_unpaused_ms=%.2f|limit_ms=34.0"%[
        "PASS" if passed else "FAIL",worst_protected,worst_first_frame,
    ])
    main.free()
    quit(0 if passed else 1)
