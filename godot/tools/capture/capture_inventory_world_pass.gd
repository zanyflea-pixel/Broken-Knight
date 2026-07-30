extends SceneTree


func _init()->void:call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await create_timer(.6).timeout
    var output_dir:=ProjectSettings.globalize_path("res://artifacts")

    var hero_menu:Control=main.get_node("UI/HeroMenu")
    main.call("_set_hero_menu",true)
    await process_frame
    await create_timer(.45).timeout
    await RenderingServer.frame_post_draw
    _save(output_dir.path_join("inventory_world_pass.png"))
    main.call("_set_hero_menu",false)

    main.get_node("UI").visible=false
    var camera:=Camera3D.new()
    main.add_child(camera)
    camera.current=true
    camera.fov=60.0
    var spawn2:Vector2=main.get("_active_profile").get("spawn_site",{}).get("position",Vector2.ZERO)
    var sampler:Callable=main.get("_world_result").terrain_height_sampler
    var spawn_ground:Vector3=sampler.call(spawn2.x,spawn2.y)
    var views:=[
        ["spawn_ground",spawn_ground+Vector3(42,20,50),spawn_ground+Vector3(0,1,0)],
        ["ground_detail",spawn_ground+Vector3(7,3.1,8),spawn_ground+Vector3(0,.05,0)],
        ["house_windows",Vector3(-2490,11,-905),Vector3(-2500,3,-950)],
        ["capital_road_arch",Vector3(335,18,-2368),Vector3(250,5,-2372)],
    ]
    for view in views:
        camera.global_position=view[1]
        camera.look_at(view[2],Vector3.UP)
        await create_timer(.40).timeout
        await RenderingServer.frame_post_draw
        _save(output_dir.path_join("%s.png"%view[0]))

    var doors:=get_nodes_in_group("interactive_house_door")
    if not doors.is_empty():
        var door:=doors[0] as Node3D
        var door_data:Dictionary={}
        for interaction in main.get_node("GameplayDirector").get("_interactables"):
            if interaction.get("node")!=door:continue
            door_data=interaction
            break
        camera.global_position=door.global_position+door.global_basis*Vector3(4.2,2.4,5.2)
        camera.look_at(door.global_position+Vector3.UP*1.5,Vector3.UP)
        if not door_data.is_empty():main.get_node("GameplayDirector").call("_activate_interactable",door_data)
        await create_timer(.7).timeout
        await RenderingServer.frame_post_draw
        _save(output_dir.path_join("animated_open_door.png"))

    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    main.get_node("UI/WorldMap").visible=true
    await create_timer(4.0).timeout
    await RenderingServer.frame_post_draw
    _save(output_dir.path_join("professional_world_map.png"))
    main.free()
    quit()


func _save(path:String)->void:
    var error:=root.get_viewport().get_texture().get_image().save_png(path)
    print("PASS_CAPTURE|%s|error=%s"%[path,error])
