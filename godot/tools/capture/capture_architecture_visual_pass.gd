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
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    main.get_node("UI").visible=false
    var camera:=Camera3D.new();camera.fov=58.0;main.add_child(camera);camera.current=true
    for family_index in range(6):
        var family_house:=_find_house(main.get_node("WorldRoot/TownRoot"),family_index)
        if family_house==null:continue
        var family_width:=float(family_house.get_meta("architecture_width",14.0))
        var family_depth:=float(family_house.get_meta("architecture_depth",10.0))
        var family_height:=float(family_house.get_meta("architecture_height",6.0))
        camera.global_position=family_house.to_global(Vector3(family_width*.95,family_height*.78,family_depth*1.35))
        camera.look_at(family_house.to_global(Vector3(0,family_height*.48,0)),Vector3.UP)
        await _save("res://artifacts/architecture_house_family_%d.png"%family_index)
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
        var stair_x:=float(house.get_meta("stair_x",width*.22))
        var stair_start_z:=float(house.get_meta("stair_start_z",depth*.33))
        var stair_end_z:=float(house.get_meta("stair_end_z",-depth*.27))
        camera.global_position=house.to_global(Vector3(stair_x,1.55,stair_start_z+depth*.08))
        camera.look_at(house.to_global(Vector3(stair_x,height*.50+.65,stair_end_z-depth*.10)),Vector3.UP)
        camera.fov=66.0
        await _save("res://artifacts/architecture_house_stairwell_clearance.png")
        var upper_y:=float(house.get_meta("upper_floor_y",height*.5))
        camera.global_position=house.to_global(Vector3(stair_x,upper_y+1.35,(stair_start_z+stair_end_z)*.5))
        camera.look_at(house.to_global(Vector3(stair_x,upper_y-.25,(stair_start_z+stair_end_z)*.5)),house.global_basis.z.normalized())
        camera.fov=62.0
        await _save("res://artifacts/architecture_house_stair_opening_overhead.png")
        camera.global_position=house.to_global(Vector3(-width*.08,upper_y+2.1,depth*.24))
        camera.look_at(house.to_global(Vector3(-width*.18,upper_y+1.3,-depth*.25)),Vector3.UP)
        camera.fov=70.0
        await _save("res://artifacts/architecture_house_upper_floor.png")
    var active_profile:Dictionary=main.get("_active_profile")
    var preview_builder:RefCounted=main.get("_preview_builder")
    var terrain_result:Dictionary=main.get("_world_result")
    for farm_site_value in active_profile.get("town_sites",[]):
        var farm_site:Dictionary=farm_site_value
        if farm_site.get("capital",false):continue
        var farm_center:Vector2=farm_site.get("position",Vector2.ZERO)
        var radius:float=farm_site.get("radius",140.0)
        var road_info:Dictionary=preview_builder.call("_nearest_corridor_segment",farm_center,active_profile.get("road_corridors",[]))
        if road_info.is_empty():continue
        var direction:Vector2=road_info.get("direction",Vector2(0,1)).normalized()
        var normal:=Vector2(-direction.y,direction.x)
        var field_center:=farm_center-direction*radius*.86+normal*radius*.60
        var field_ground:Vector3=terrain_result.terrain_height_sampler.call(field_center.x,field_center.y)
        camera.global_position=field_ground+Vector3(normal.x*44.0,22.0,normal.y*44.0)+Vector3(direction.x*28.0,0,direction.y*28.0)
        camera.look_at(field_ground+Vector3.UP*.8,Vector3.UP)
        camera.fov=56.0
        await _save("res://artifacts/architecture_cultivated_field.png")
        break
    var capital:Dictionary={}
    for site in active_profile.get("town_sites",[]):
        if site.get("capital",false):capital=site;break
    var castle_center:Vector2=capital.get("position",Vector2.ZERO)+Vector2(0,-92)
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
