extends SceneTree


func _init()->void:
    call_deferred("_run")


func _run()->void:
    OS.set_environment("BROKEN_KNIGHT_DISABLE_MAP_CACHE","1")
    var failures:Array[String]=[]
    var map_script:=load("res://scripts/WorldMap.gd") as Script
    if map_script==null:
        push_error("WORLD_MAP_FAILURE|WorldMap.gd did not compile")
        quit(1)
        return
    var profile_builder:RefCounted=load("res://scripts/world/WorldProfile.gd").new()
    var profile:Dictionary=profile_builder.make_zone_profile("starting_realm")
    if profile.get("map_sites",[]).size()<7:failures.append("complete landmark survey is missing")
    for forest in profile.get("forest_regions",[]):
        if str(forest.get("name",""))=="":failures.append("unnamed forest remains on royal survey");break
    for chain in profile.get("mountain_chains",[]):
        if str(chain.get("name",""))=="":failures.append("unnamed mountain range remains on royal survey");break

    var world_map:=map_script.new() as Control
    world_map.size=Vector2(1280,720)
    var player:=Node3D.new();player.position=Vector3(-420,0,70)
    root.add_child(player)
    root.add_child(world_map)
    var sampler:=func(x:float,z:float)->Vector3:return Vector3(x,sin(x*.004)*8.0+cos(z*.003)*6.0,z)
    world_map.configure(profile,player,null,sampler)
    # Headless frames can advance far faster than the map worker thread. Give
    # the asynchronous survey real wall-clock time instead of 120 near-zero
    # duration frames.
    var survey_deadline_usec:=Time.get_ticks_usec()+8_000_000
    while world_map.get("_terrain_texture")==null and Time.get_ticks_usec()<survey_deadline_usec:
        await create_timer(.01).timeout
    if world_map.get("_terrain_texture")==null:failures.append("high-resolution terrain survey did not finish")
    else:
        var texture:ImageTexture=world_map.get("_terrain_texture")
        if texture.get_width()!=512:failures.append("terrain survey is not 512px")
    var panel:Rect2=world_map.call("_map_panel")
    if panel.size.distance_to(Vector2(1280,720))>.01:failures.append("world map does not fill the available screen")
    world_map.queue_redraw()
    await process_frame
    var features:Array=world_map.get("_map_features")
    if features.size()<70:failures.append("complete survey exposes too few authored features")
    print("WORLD_MAP_PASS|resolution=%d|fills_screen=%s|features=%d|map_sites=%d|forests=%d|mountains=%d|failures=%d"%[
        0 if world_map.get("_terrain_texture")==null else (world_map.get("_terrain_texture") as ImageTexture).get_width(),
        panel.size.distance_to(Vector2(1280,720))<=.01,
        features.size(),profile.get("map_sites",[]).size(),profile.get("forest_regions",[]).size(),profile.get("mountain_chains",[]).size(),failures.size(),
    ])
    for failure in failures:push_error("WORLD_MAP_FAILURE|%s"%failure)
    world_map.free();player.free()
    quit(1 if not failures.is_empty() else 0)
