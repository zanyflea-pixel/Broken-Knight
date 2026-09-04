extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _capture(path: String) -> Error:
    await RenderingServer.frame_post_draw
    return root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))


func _run() -> void:
    var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.auto_boot_enabled = false
    root.add_child(main)
    await main.boot_world(Callable(), false, true)
    main.get_node("UI").visible = false
    var director: Node = main.get_node("GameplayDirector")
    var hero: Node = main.get_node("Player")
    var target: Dictionary = {}
    for rock_value in director.get("_mineable_rocks"):
        if not rock_value is Dictionary:
            continue
        var rock: Dictionary = rock_value
        var scale_value := float(rock.get("scale", 1.0))
        if str(rock.get("ore_id", "")) == "iron" and scale_value >= 0.85 and scale_value <= 1.22:
            target = rock
            break
    if target.is_empty():
        push_error("No review-sized iron outcrop was found")
        quit(1)
        return
    var ground: Vector3 = target.get("ground_position", Vector3.ZERO)
    var camera := Camera3D.new()
    camera.current = true
    camera.fov = 55.0
    main.add_child(camera)
    camera.global_position = ground + Vector3(7.6, 4.3, 7.8)
    camera.look_at(ground + Vector3.UP * 0.70, Vector3.UP)
    for _frame in range(24):
        await process_frame
    var failures := 0
    if await _capture("res://artifacts/mineable_iron_intact_world_v1.png") != OK:
        failures += 1
    hero.equip_item_id("starter_pickaxe")
    director.call("_activate_world_rock", target)
    director.call("_activate_world_rock", target)
    director.call("_activate_world_rock", target)
    # Let the short impact fragments clear so the acceptance frame judges the
    # persistent authored remnant rather than the mining burst.
    for _frame in range(100):
        await process_frame
    if await _capture("res://artifacts/mineable_iron_depleted_world_v1.png") != OK:
        failures += 1
    print("MINEABLE_GEOLOGY_WORLD_CAPTURE|ore=%s|scale=%.2f|shots=2|failures=%d" % [
        str(target.get("ore_id", "")), float(target.get("scale", 0.0)), failures,
    ])
    main.free()
    await process_frame
    quit(0 if failures == 0 else 1)
