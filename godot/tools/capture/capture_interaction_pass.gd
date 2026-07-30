extends SceneTree


func _init() -> void:
    call_deferred("_run")


func _capture(path: String) -> void:
    await create_timer(0.45).timeout
    await RenderingServer.frame_post_draw
    var image := root.get_viewport().get_texture().get_image()
    var error := image.save_png(ProjectSettings.globalize_path(path))
    print("INTERACTION_CAPTURE|%s|error=%s|fps=%d" % [path, error, Engine.get_frames_per_second()])


func _run() -> void:
    var main: Node3D = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    var player: CharacterBody3D = main.get_node("Player")
    var ui: CanvasLayer = main.get_node("UI")
    var camera := Camera3D.new()
    main.add_child(camera)
    camera.current = true
    camera.fov = 61.0
    var target := OS.get_environment("BROKEN_KNIGHT_CAPTURE_TARGET")
    if OS.get_environment("BROKEN_KNIGHT_CAPTURE_NO_SHADOW") == "1":
        (main.get_node("Sun") as DirectionalLight3D).shadow_enabled = false

    # The revised well dungeon: alternating corridors, branches, a dead end,
    # a cracked secret wall and a final chamber instead of repeated key rooms.
    if target.is_empty() or target == "dungeon":
        ui.visible = false
        player.global_position = Vector3(8000.0, -82.0, 58.0)
        camera.global_position = Vector3(8000.0, -78.0, 61.0)
        camera.look_at(Vector3(8000.0, -80.0, 43.0), Vector3.UP)
        await _capture("res://artifacts/interaction_dungeon.png")

    # The inventory portrait must show the actual equipped Blender tool.
    var hero_menu: Control = ui.get_node("HeroMenu")
    if target.is_empty() or target == "inventory":
        ui.visible = true
        player.equip_item_id("starter_wood_axe")
        hero_menu.visible = true
        hero_menu.refresh()
        await _capture("res://artifacts/interaction_inventory_axe.png")

    if target.is_empty() or target == "town":
        hero_menu.visible = false
        ui.visible = false
        player.global_position = Vector3(-2500.0, 8.0, -950.0)
        camera.global_position = Vector3(-2415.0, 58.0, -855.0)
        camera.look_at(Vector3(-2500.0, 4.0, -950.0), Vector3.UP)
        await _capture("res://artifacts/interaction_town_terrain.png")

    main.free()
    quit()
