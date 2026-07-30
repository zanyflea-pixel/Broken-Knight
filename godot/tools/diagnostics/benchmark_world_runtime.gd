extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    if OS.get_environment("BROKEN_KNIGHT_BENCHMARK_UNCAPPED")=="1":
        DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
        Engine.max_fps=0
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var benchmark_location:=OS.get_environment("BROKEN_KNIGHT_BENCHMARK_LOCATION")
    if benchmark_location in ["castle","small_town"]:
        var world_result:Dictionary=main.get("_world_result")
        var target:=Vector2(250.0,-2450.0) if benchmark_location=="castle" else Vector2(-2500.0,-950.0)
        var ground:Vector3=world_result.height_sampler.call(target.x,target.y)
        main.get_node("Player").global_position=ground+Vector3.UP*.12
        await process_frame
    var town_geometry:=_count_geometry(main.get_node("WorldRoot/TownRoot"))
    var service_geometry:=_count_geometry(main.get_node("GameplayDirector"))
    var service_heavy:Array=[]
    for child in main.get_node("GameplayDirector").get_children():
        var child_geometry:=_count_geometry(child)
        if int(child_geometry.mesh)>=20:service_heavy.append({"name":child.name,"mesh":child_geometry.mesh,"multi":child_geometry.multi})
    service_heavy.sort_custom(func(a,b):return int(a.mesh)>int(b.mesh))
    if service_heavy.size()>12:service_heavy.resize(12)
    print("WORLD_GEOMETRY_HOTSPOTS|%s"%str(service_heavy))
    # Give shader compilation and world construction time to settle before the
    # walking-camera measurement. This benchmark reflects gameplay rendering,
    # not the one-time load spike.
    await create_timer(2.0).timeout
    var samples:Array[float]=[]
    var draw_samples:Array[int]=[]
    var primitive_samples:Array[int]=[]
    for _sample in range(12):
        await create_timer(0.25).timeout
        samples.append(float(Engine.get_frames_per_second()))
        draw_samples.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
        primitive_samples.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
    var fps_total:=0.0
    var draw_total:=0
    var primitive_total:=0
    for value in samples:fps_total+=value
    for value in draw_samples:draw_total+=value
    for value in primitive_samples:primitive_total+=value
    print("WORLD_BENCHMARK|avg_fps=%.1f|min_fps=%.1f|avg_draw_calls=%d|avg_primitives=%d|town_mesh=%d|town_multi=%d|service_mesh=%d"%[
        fps_total/maxf(1.0,float(samples.size())),
        samples.min() if not samples.is_empty() else 0.0,
        draw_total/maxi(1,draw_samples.size()),
        primitive_total/maxi(1,primitive_samples.size()),
        town_geometry.mesh,
        town_geometry.multi,
        service_geometry.mesh,
    ])
    main.free()
    quit()


func _count_geometry(root_node:Node)->Dictionary:
    var counts:={"mesh":0,"multi":0}
    var stack:Array[Node]=[root_node]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if node is MultiMeshInstance3D:counts.multi+=1
        elif node is MeshInstance3D:counts.mesh+=1
    return counts
