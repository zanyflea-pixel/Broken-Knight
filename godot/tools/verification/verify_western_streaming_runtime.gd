extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_western_region_loaded()

    var contexts:Dictionary=main.get("_region_contexts")
    var western:Dictionary=contexts.get("western_reaches",{})
    if western.is_empty():failures.append("Western Reaches context was not registered")
    if not bool(main.get("_western_region_ready")):failures.append("Western Reaches never became ready")
    var region_root:Node3D=western.get("root")
    if not is_instance_valid(region_root) or region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:
        failures.append("Western Reaches terrain was not populated")

    var starting:Dictionary=contexts.get("starting_realm",{})
    var start_result:Dictionary=starting.get("result",{})
    var west_result:Dictionary=western.get("result",{})
    var maximum_gap:=0.0
    for sample_index in range(129):
        var z:=lerpf(-3600.0,3600.0,float(sample_index)/128.0)
        var start_height:float=start_result.terrain_height_sampler.call(-3600.0,z).y
        var west_height:float=west_result.terrain_height_sampler.call(3600.0,z).y
        maximum_gap=maxf(maximum_gap,absf(start_height-west_height))
    if maximum_gap>.015:failures.append("Runtime western boundary has a %.4fm terrain crack"%maximum_gap)
    var crossing_point:=Vector2(-3600.0,-400.0)
    if not bool(main._sample_global_walkable(crossing_point.x,crossing_point.y)):failures.append("Western road crossing still has an invisible traversal wall")
    var start_road:Dictionary={}
    for road in starting.get("local_profile",{}).get("road_corridors",[]):
        if str(road.get("name",""))=="Western Reach Road":start_road=road;break
    var west_road:Dictionary={}
    for road in western.get("local_profile",{}).get("road_corridors",[]):
        if str(road.get("name",""))=="Rainward Realmway":west_road=road;break
    var road_gap:=INF
    if not start_road.is_empty() and not west_road.is_empty():
        road_gap=Vector2(start_road.points[-1]).distance_to(Vector2(west_road.points[0])+Vector2(-7200,0))
    if road_gap>.01:failures.append("Westward realm road has a %.2fm endpoint gap"%road_gap)

    var west_profile:Dictionary=western.get("local_profile",{})
    var rain_rivers:Array=west_profile.get("river_corridors",[])
    if rain_rivers.size()!=1:
        failures.append("Western watershed should expose one coherent main river")
    else:
        var rainfall:Dictionary=rain_rivers[0]
        var river_points:Array=rainfall.get("points",[])
        if river_points.size()<24:failures.append("Rainfall River is not smoothly sampled")
        elif absf(Vector2(river_points[-1]).x+3600.0)>.01:failures.append("Rainfall River does not continue through the western world edge")
        if float(rainfall.get("source_height",0.0))<=float(rainfall.get("mouth_height",0.0)):
            failures.append("Rainfall River does not descend from source to mouth")
        var water_lift:float=float(west_profile.get("river_water_lift",1.35))
        for sample_index in range(1,river_points.size()-1,12):
            var point:Vector2=river_points[sample_index]
            var water_top:float=west_result.river_height_sampler.call(point.x,point.y).y+water_lift
            var terrain_y:float=west_result.terrain_height_sampler.call(point.x,point.y).y
            if terrain_y>water_top+.08:failures.append("Rainfall terrain protrudes %.2fm through water near %s"%[terrain_y-water_top,point]);break
            if terrain_y<water_top-3.2:failures.append("Rainfall water floats %.2fm above its bed near %s"%[water_top-terrain_y,point]);break
    var bridge_site:=Vector2(1120,-40)
    var road_info:=_nearest_corridor(bridge_site,west_profile.get("road_corridors",[]))
    var river_info:=_nearest_corridor(bridge_site,rain_rivers)
    if float(road_info.get("distance",INF))>.2 or float(river_info.get("distance",INF))>.2:
        failures.append("Warden's Span is not centered on both road and river")
    elif absf(Vector2(road_info.direction).dot(Vector2(river_info.direction)))>.30:
        failures.append("Warden's Span approaches the river at an unsafe shallow angle")
    var bridge_root:=region_root.get_node_or_null("BridgeRoot") if is_instance_valid(region_root) else null
    if bridge_root==null or bridge_root.get_child_count()!=1:
        failures.append("Western Reaches should build exactly one intentional bridge")
    if is_instance_valid(region_root):
        for landmark_name in ["GalehornWatch","RainwardWaystation","OldRainwardAbbey"]:
            if region_root.find_child(landmark_name,true,false)==null:
                failures.append("Authored Western landmark %s was not instantiated"%landmark_name)
        var town_root:=region_root.get_node_or_null("TownRoot")
        var rainward_house_count:=0
        if town_root==null:
            failures.append("Western town root is absent")
        else:
            for town_name in ["Oakrest","Rainhaven","Stonecross"]:
                if town_root.get_node_or_null(town_name)==null:failures.append("%s architecture was not built"%town_name)
            for house in town_root.find_children("House_*","Node3D",true,false):
                if str(house.get_meta("architecture_set","")) in ["rainward_timber","rainward_stone"]:rainward_house_count+=1
            if rainward_house_count<42:failures.append("Only %d rainward houses were built"%rainward_house_count)
            if town_root.find_child("*Timber Yard",true,false)==null:failures.append("Rainward timber-yard identity is missing")
            if town_root.find_child("Stonecross Quarry Derrick",true,false)==null:failures.append("Stonecross quarry identity is missing")
    var approach_samples:Array[String]=[]
    for point in [Vector2(1380,100),Vector2(1300,57),Vector2(1220,14),Vector2(1160,-18),Vector2(1120,-40),Vector2(1080,-62),Vector2(1000,-105),Vector2(920,-148),Vector2(860,-180)]:
        approach_samples.append("%.0f:%.0f=%.2f/%.2f"%[
            point.x,point.y,
            west_result.terrain_height_sampler.call(point.x,point.y).y,
            west_result.height_sampler.call(point.x,point.y).y,
        ])

    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    player.global_position=main._sample_global_height(-4300.0,0.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(0.0,-4300.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="western_reaches":failures.append("Western gameplay profile did not activate")
    var state_before:Dictionary=main.get_node("GameplayDirector").get_zone_transition_state()
    player.global_position=main._sample_global_height(-3000.0,0.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(0.0,-3000.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="starting_realm":failures.append("Starting gameplay profile did not reactivate on return")
    var state_after:Dictionary=main.get_node("GameplayDirector").get_zone_transition_state()
    if state_before.get("quest_claimed",{})!=state_after.get("quest_claimed",{}):failures.append("Quest state changed during the lateral region round trip")

    var atlas:Dictionary=main.get("_world_atlas_profile")
    var extent:Vector2=atlas.get("map_extent",Vector2.ZERO)
    var center:Vector2=atlas.get("map_center",Vector2.ZERO)
    if extent.distance_to(Vector2(14400,21600))>.1:failures.append("Four-region atlas extent is not 14400 x 21600")
    if center.distance_to(Vector2(-3600,-7200))>.1:failures.append("Four-region atlas center is incorrect")
    var region_ids:Array=[]
    for summary in atlas.get("region_summaries",[]):region_ids.append(str(summary.get("zone_id","")))
    if "western_reaches" not in region_ids:failures.append("Western Reaches is absent from map region summaries")
    var oakrest_count:int=atlas.get("town_sites",[]).filter(func(site:Dictionary)->bool:return str(site.get("name",""))=="Oakrest").size()
    if oakrest_count!=1:failures.append("Oakrest appears %d times in the world map settlement layer"%oakrest_count)

    print("WESTERN_STREAMING_RUNTIME|ready=%s|gap=%.5f|road_gap=%.3f|walkable=%s|active_return=%s|atlas=%dx%d|failures=%d"%[
        str(bool(main.get("_western_region_ready"))).to_lower(),maximum_gap,
        road_gap,str(bool(main._sample_global_walkable(crossing_point.x,crossing_point.y))).to_lower(),str(main.get("_active_zone_id")),
        roundi(extent.x),roundi(extent.y),failures.size(),
    ])
    print("WESTERN_BRIDGE_GRADE|terrain_height="+"|".join(approach_samples))
    for failure in failures:push_error("WESTERN_STREAM_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)


func _nearest_corridor(point:Vector2,corridors:Array)->Dictionary:
    var nearest:Dictionary={}
    var best:=INF
    for corridor in corridors:
        var points:Array=corridor.get("points",[])
        for index in range(points.size()-1):
            var a:Vector2=points[index]
            var b:Vector2=points[index+1]
            var segment:=b-a
            if segment.length_squared()<=.0001:continue
            var t:=clampf((point-a).dot(segment)/segment.length_squared(),0.0,1.0)
            var closest:=a+segment*t
            var distance:=point.distance_to(closest)
            if distance<best:
                best=distance
                nearest={"distance":distance,"direction":segment.normalized(),"closest":closest}
    return nearest
