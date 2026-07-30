extends SceneTree


func _init() -> void:
    call_deferred("_run")


func _run() -> void:
    var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var player: Node3D = main.get_node("Player")
    var site: Dictionary = main._terrain_builder._bridge_sites_cache[0]
    var center: Vector2 = site.position
    var direction: Vector2 = site.direction
    var road_width: float = site.road_width
    var river_width: float = site.river_width
    var deck_half := maxf(river_width + 10.0, road_width * 2.15) * .5
    var approach := center - direction * (deck_half + 16.0)
    var ground: Vector3 = main._world_result.height_sampler.call(approach.x, approach.y)
    player.global_position = ground + Vector3.UP * .06
    player._yaw = atan2(direction.x, direction.y)
    player.get_node("CameraPivot").rotation.y = player._yaw
    var review_camera := Camera3D.new()
    main.add_child(review_camera)
    var target: Vector3 = main._world_result.height_sampler.call(center.x, center.y) + Vector3.UP * 1.4
    review_camera.global_position = target - Vector3(direction.x, 0.0, direction.y) * 54.0 + Vector3.UP * 28.0
    review_camera.look_at(target, Vector3.UP)
    review_camera.fov = 55.0
    review_camera.current = true
    await create_timer(.45).timeout
    await RenderingServer.frame_post_draw
    var image := root.get_viewport().get_texture().get_image()
    var path := ProjectSettings.globalize_path("res://artifacts/bridge_gameplay_pass.png")
    var err := image.save_png(path)
    print("BRIDGE_CAPTURE|%s|%s" % [path, err])
    main.free()
    quit(0 if err == OK else 14)
