extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    await create_timer(.8).timeout
    var output:=ProjectSettings.globalize_path("res://artifacts")
    var hero:Node=main.get_node("Player")

    main.call("_set_hero_menu",true)
    await create_timer(.35).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_inventory_weapons.png"))

    hero.equip_item_id("traveler_torch")
    main.get_node("UI/HeroMenu").refresh()
    await create_timer(.25).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_inventory_torch.png"))

    hero.equip_item_id("starter_wood_axe")
    main.get_node("UI/HeroMenu").refresh()
    await create_timer(.25).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_inventory_axe.png"))

    hero.equip_item_id("starter_pickaxe")
    main.get_node("UI/HeroMenu").refresh()
    await create_timer(.25).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_inventory_pickaxe.png"))
    main.call("_set_hero_menu",false)

    main.get_node("UI").visible=false
    var camera:=Camera3D.new()
    camera.fov=58
    main.add_child(camera)
    camera.current=true
    var sampler:Callable=main.get("_world_result").terrain_height_sampler

    var hero_ground:Vector3=hero.global_position
    camera.global_position=hero_ground+Vector3(7,2.3,8)
    camera.look_at(hero_ground+Vector3(0,.35,0),Vector3.UP)
    await create_timer(.4).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_near_field_ground.png"))

    var junction:Vector3=sampler.call(-420.0,70.0)
    camera.global_position=junction+Vector3(22,7,20)
    camera.look_at(junction+Vector3.UP*.12,Vector3.UP)
    await create_timer(.4).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_path_connection.png"))

    var props:Node=main.get_node("WorldRoot/PropsRoot")
    var spawn:Vector2=main.get("_active_profile").spawn_site.position
    var nearest_bush:Dictionary={}
    var best:=INF
    for prop in props.get_meta("collision_prop_registry",[]):
        if prop.get("kind","")!="bush":continue
        var position:Vector3=prop.position
        var distance:=Vector2(position.x,position.z).distance_squared_to(spawn)
        if distance<best:
            best=distance
            nearest_bush=prop
    if not nearest_bush.is_empty():
        var bush_position:Vector3=nearest_bush.position
        camera.global_position=bush_position+Vector3(7,2.4,8)
        camera.look_at(bush_position+Vector3.UP*.45,Vector3.UP)
        await create_timer(.45).timeout
        await RenderingServer.frame_post_draw
        _save(output.path_join("optimization_grass_bushes.png"))

    camera.global_position=Vector3(-1200,15,335)
    camera.look_at(Vector3(-1200,1.8,250),Vector3.UP)
    await create_timer(.45).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_river_bank.png"))

    var river_center:=Vector3(-1000.0,1.4,250.0)
    camera.global_position=river_center+Vector3(0,82,0)
    camera.look_at(river_center,Vector3.FORWARD)
    await create_timer(.4).timeout
    await RenderingServer.frame_post_draw
    _save(output.path_join("optimization_river_bank_top.png"))

    main.free()
    quit()


func _save(path:String)->void:
    var error:=root.get_viewport().get_texture().get_image().save_png(path)
    print("OPTIMIZATION_CAPTURE|%s|error=%s"%[path,error])
