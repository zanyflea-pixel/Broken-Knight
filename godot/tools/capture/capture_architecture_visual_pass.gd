extends SceneTree


func _init()->void:
    call_deferred("_run")


func _save(path:String)->void:
    await create_timer(.30).timeout
    await RenderingServer.frame_post_draw
    var error:=root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
    print("ARCHITECTURE_CAPTURE|path=%s|error=%d"%[path,error])


func _find_house(node:Node,family:int)->Node3D:
    if node is Node3D and int(node.get_meta("architecture_family",-1))==family:return node as Node3D
    for child in node.get_children():
        var found:=_find_house(child,family)
        if found!=null:return found
    return null


func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await process_frame
    await process_frame
    main.get_node("UI").visible=false
    var camera:=Camera3D.new();camera.fov=58.0;main.add_child(camera);camera.current=true
    var house:=_find_house(main.get_node("WorldRoot/TownRoot"),4)
    if house!=null:
        var width:=float(house.get_meta("architecture_width",14.0))
        var depth:=float(house.get_meta("architecture_depth",10.0))
        var height:=float(house.get_meta("architecture_height",8.8))
        for child in house.get_children():
            if child.is_in_group("interactive_house_door"):(child as Node3D).rotation.y=-1.62
        camera.global_position=house.to_global(Vector3(width*.95,height*.72,depth*1.35))
        camera.look_at(house.to_global(Vector3(0,height*.42,0)),Vector3.UP)
        await _save("res://artifacts/architecture_house_family_close.png")
        camera.global_position=house.to_global(Vector3(-width*.12,2.25,depth*.26))
        camera.look_at(house.to_global(Vector3(-width*.12,1.35,-depth*.28)),Vector3.UP)
        camera.fov=68.0
        await _save("res://artifacts/architecture_house_ground_floor.png")
        var upper_y:=float(house.get_meta("upper_floor_y",height*.5))
        camera.global_position=house.to_global(Vector3(-width*.08,upper_y+2.1,depth*.24))
        camera.look_at(house.to_global(Vector3(-width*.18,upper_y+1.3,-depth*.25)),Vector3.UP)
        camera.fov=70.0
        await _save("res://artifacts/architecture_house_upper_floor.png")
    var capital:Dictionary={}
    for site in main.get("_active_profile").get("town_sites",[]):
        if site.get("capital",false):capital=site;break
    var castle_center:Vector2=capital.get("position",Vector2.ZERO)+Vector2(0,-92)
    var terrain_result:Dictionary=main.get("_world_result")
    var ground:Vector3=terrain_result.height_sampler.call(castle_center.x,castle_center.y)
    var keep_center:=ground+Vector3(0,0,-8)
    camera.global_position=keep_center+Vector3(8,13.0,14);camera.look_at(keep_center+Vector3(-6,11.2,-4),Vector3.UP);camera.fov=65.0
    await _save("res://artifacts/architecture_castle_council_room.png")
    camera.global_position=keep_center+Vector3(8,21.0,14);camera.look_at(keep_center+Vector3(-6,19.2,-3),Vector3.UP)
    await _save("res://artifacts/architecture_castle_armory.png")
    camera.global_position=keep_center+Vector3(9,29.0,15);camera.look_at(keep_center+Vector3(-6,27.2,-4),Vector3.UP)
    await _save("res://artifacts/architecture_castle_royal_solar.png")
    main.free()
    quit(0)
