extends SceneTree


func _initialize()->void:
    call_deferred("_run")


func _capture(camera:Camera3D,label:String)->void:
    for _frame in range(4):
        await process_frame
        await RenderingServer.frame_post_draw
    var path:=ProjectSettings.globalize_path("res://artifacts/bug_sweep_%s.png"%label)
    var error:=root.get_texture().get_image().save_png(path)
    print("WORLD_BUG_SWEEP|label=%s|path=%s|error=%d|draw_calls=%d|objects=%d"%[
        label,path,error,
        int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
        int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
    ])


func _review(camera:Camera3D,sampler:Callable,label:String,target2:Vector2,offset:Vector3,look_height:float=2.0)->void:
    var target:Vector3=sampler.call(target2.x,target2.y)
    camera.global_position=target+offset
    camera.look_at(target+Vector3.UP*look_height,Vector3.UP)
    await _capture(camera,label)


func _safe_label(value:String)->String:
    return value.to_lower().replace(" ","_").replace("'","").replace("-","_")


func _run()->void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps=60
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    main.get_node("UI").visible=false
    var result:Dictionary=main.get("_world_result")
    var profile:Dictionary=main.get("_active_profile")
    var sampler:Callable=result.get("terrain_height_sampler",result.height_sampler)
    var camera:=Camera3D.new()
    camera.fov=56.0;camera.near=.14;camera.far=5200.0
    main.add_child(camera);camera.current=true
    var requested:=OS.get_environment("BROKEN_KNIGHT_BUG_SWEEP_TARGET")

    for site_value in main.get("_terrain_builder").get("_bridge_sites_cache"):
        var site:Dictionary=site_value
        var label:="bridge_"+_safe_label(str(site.get("name","crossing")))
        if not requested.is_empty() and requested!=label:continue
        var center:Vector2=site.get("position",Vector2.ZERO)
        var direction:Vector2=site.get("direction",Vector2(0,1)).normalized()
        var normal:=Vector2(-direction.y,direction.x)
        await _review(camera,sampler,label,center,Vector3(-direction.x*72.0+normal.x*42.0,23.0,-direction.y*72.0+normal.y*42.0),2.0)

    var sites:Array=[profile.get("spawn_site",{})]
    sites.append_array(profile.get("town_sites",[]))
    for site_value in sites:
        var site:Dictionary=site_value
        var label:="town_"+_safe_label(str(site.get("name","settlement")))
        if not requested.is_empty() and requested!=label:continue
        var center:Vector2=site.get("position",Vector2.ZERO)
        var radius:=float(site.get("radius",100.0))
        await _review(camera,sampler,label,center,Vector3(radius*.54,clampf(radius*.18,20.0,62.0),radius*.68),6.0)

    var route_reviews:Array[Dictionary]=[
        {"label":"route_southbank_bridge","point":Vector2(-449,-146),"offset":Vector3(34,10,48)},
        {"label":"route_south_ford","point":Vector2(659,-495),"offset":Vector3(-38,11,50)},
        {"label":"route_west_cavern","point":Vector2(-2695,1563),"offset":Vector3(46,14,55)},
        {"label":"route_redstone","point":Vector2(2558,-1505),"offset":Vector3(-48,14,52)},
        {"label":"route_north_tarn","point":Vector2(-730,2890),"offset":Vector3(42,13,55)},
        {"label":"route_willow","point":Vector2(-720,1180),"offset":Vector3(42,11,52)},
    ]
    for review in route_reviews:
        if not requested.is_empty() and requested!=str(review.label):continue
        await _review(camera,sampler,str(review.label),review.point,review.offset,2.0)

    for corridor_value in profile.get("river_corridors",[]):
        var corridor:Dictionary=corridor_value
        var points:Array=corridor.get("points",[])
        if points.size()<2:continue
        for endpoint_index in [0,points.size()-1]:
            var suffix:="source" if endpoint_index==0 else "mouth"
            var label:="river_%s_%s"%[_safe_label(str(corridor.get("name","river"))),suffix]
            if not requested.is_empty() and requested!=label:continue
            var point:Vector2=points[endpoint_index]
            var neighbor:Vector2=points[1] if endpoint_index==0 else points[points.size()-2]
            var direction:=(point-neighbor).normalized()
            var normal:=Vector2(-direction.y,direction.x)
            await _review(camera,sampler,label,point,Vector3(-direction.x*72.0+normal.x*34.0,21.0,-direction.y*72.0+normal.y*34.0),1.5)

    main.queue_free();await process_frame;quit(0)
