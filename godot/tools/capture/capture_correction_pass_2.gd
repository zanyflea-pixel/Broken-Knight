extends SceneTree


func _init()->void:call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame;await process_frame;await create_timer(.7).timeout
    var output:=ProjectSettings.globalize_path("res://artifacts")

    main.call("_set_hero_menu",true)
    await create_timer(.4).timeout;await RenderingServer.frame_post_draw
    _save(output.path_join("correction2_inventory.png"))
    main.call("_set_hero_menu",false)

    main.get_node("UI").visible=false
    var camera:=Camera3D.new();camera.fov=58.0;main.add_child(camera);camera.current=true
    var profile:Dictionary=main.get("_active_profile")
    var sampler:Callable=main.get("_world_result").terrain_height_sampler
    var spawn2:Vector2=profile.spawn_site.position
    var spawn3:Vector3=sampler.call(spawn2.x,spawn2.y)
    var views:=[
        ["starter_road",spawn3+Vector3(27,8,31),spawn3+Vector3(0,.25,0)],
        ["ground_breakup",spawn3+Vector3(62,3.2,-47),spawn3+Vector3(43,.15,-29)],
        ["river_shore",Vector3(-1200,13,330),Vector3(-1200,1.8,250)],
    ]
    for view in views:
        camera.global_position=view[1];camera.look_at(view[2],Vector3.UP)
        await create_timer(.45).timeout;await RenderingServer.frame_post_draw
        _save(output.path_join("correction2_%s.png"%view[0]))
    var dungeon:Node3D=main.find_child("RiverwatchWellDungeon",true,false) as Node3D
    var attempts:=0
    while not is_instance_valid(dungeon) and attempts<120:
        await create_timer(.1).timeout
        dungeon=main.find_child("RiverwatchWellDungeon",true,false) as Node3D
        attempts+=1
    if is_instance_valid(dungeon):
        var hero:Node3D=main.get_node("Player")
        hero.call("set_interior_mode",true)
        hero.global_position=dungeon.to_global(Vector3(0,.12,54))
        main.get_node("GameplayDirector").call("_stream_local_gameplay")
        await process_frame
        camera.global_position=dungeon.to_global(Vector3(1,3.15,57))
        camera.look_at(dungeon.to_global(Vector3(-13,2.1,33)),Vector3.UP)
        await create_timer(.55).timeout;await RenderingServer.frame_post_draw
        _save(output.path_join("correction2_imp_dungeon.png"))

    main.get_node("UI").visible=true
    main.get_node("UI/OldHud").visible=false
    main.get_node("UI/Minimap").visible=false
    main.get_node("UI/WorldMap").visible=true
    await create_timer(4.0).timeout;await RenderingServer.frame_post_draw
    _save(output.path_join("correction2_map.png"))
    main.free();quit()


func _save(path:String)->void:
    var error:=root.get_viewport().get_texture().get_image().save_png(path)
    print("CORRECTION2_CAPTURE|%s|error=%s"%[path,error])
