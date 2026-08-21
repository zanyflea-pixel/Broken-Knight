extends SceneTree


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var profile: Dictionary = main._active_profile
    var raw: Callable = main._world_result.terrain_height_sampler
    var river: Callable = main._world_result.river_height_sampler
    for corridor in profile.get("river_corridors", []):
        var points: Array = corridor.get("points", [])
        var half_water := float(corridor.get("width", 48.0)) * .66 * .5
        var exposed := 0
        var samples := 0
        var worst_clearance := INF
        for i in range(points.size() - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var length := a.distance_to(b)
            var steps := maxi(1, ceili(length / 14.0))
            var tangent := (b - a).normalized()
            var normal := Vector2(-tangent.y, tangent.x)
            for step in range(steps):
                var p := a.lerp(b, float(step) / float(steps))
                for fraction in [-.82, -.45, 0.0, .45, .82]:
                    var q := p + normal * half_water * float(fraction)
                    var water_y:float=river.call(q.x,q.y).y+float(main._profile.get("river_water_lift",1.35))
                    var terrain_y: float = raw.call(q.x, q.y).y
                    var clearance := water_y - terrain_y
                    worst_clearance = minf(worst_clearance, clearance)
                    if clearance < .025:
                        exposed += 1
                    samples += 1
        print("RIVER_AUDIT|%s|samples=%d|exposed=%d|worst_clearance=%.3f" % [corridor.get("name", "River"), samples, exposed, worst_clearance])

    for corridor in profile.get("trail_corridors", []):
        var points: Array = corridor.get("points", [])
        var worst_grade := 0.0
        var worst_index := -1
        var worst_delta := 0.0
        for i in range(points.size() - 1):
            var a: Vector2 = points[i]
            var b: Vector2 = points[i + 1]
            var distance := maxf(1.0, a.distance_to(b))
            var delta_y: float = raw.call(b.x, b.y).y - raw.call(a.x, a.y).y
            var grade := absf(delta_y) / distance
            if grade > worst_grade:
                worst_grade = grade
                worst_index = i
                worst_delta = delta_y
        print("TRAIL_AUDIT|%s|points=%d|max_grade=%.3f|segment=%d|rise=%.2f" % [corridor.get("name", "Trail"), points.size(), worst_grade, worst_index, worst_delta])

    print("WORLD_SIZE_AUDIT|nodes=%d|objects=%d" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))])
    main.free()
    quit()
