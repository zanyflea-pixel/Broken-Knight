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
    await main._ensure_glacial_region_loaded()
    await main._ensure_stormbreak_region_loaded()
    await main._ensure_skeld_region_loaded()

    var contexts:Dictionary=main.get("_region_contexts")
    var coast:Dictionary=contexts.get("skeld_coast",{})
    if coast.is_empty():failures.append("Skeld Coast context was not registered")
    if not bool(main.get("_skeld_region_ready")):failures.append("Skeld Coast never became ready")
    var region_root:Node3D=coast.get("root")
    var coastal_houses:=0
    if not is_instance_valid(region_root) or region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:
        failures.append("Skeld Coast terrain was not populated")
    if is_instance_valid(region_root):
        var river_root:=region_root.get_node_or_null("RiverRoot")
        if river_root==null or river_root.find_child("The Grey Sea_Water",true,false)==null:
            failures.append("The Grey Sea surface was not built")
        var bridge_root:=region_root.get_node_or_null("BridgeRoot")
        if bridge_root==null or bridge_root.get_child_count()!=1:
            failures.append("Skeld Coast should build exactly one intentional bridge")
        for landmark_name in ["CapeKeldLighthouse","FrostharborDock","WhaleboneChapel"]:
            if region_root.find_child(landmark_name,true,false)==null:
                failures.append("Skeld Blender landmark %s was not instantiated"%landmark_name)
        for boat_name in ["Frostharbor Tide Cutter","Kelpwick Netter"]:
            if region_root.find_child(boat_name,true,false)==null:
                failures.append("Skeld working boat %s was not instantiated"%boat_name)
        var longhouses:=region_root.find_children("*Hall","MeshInstance3D",true,false)
        if longhouses.size()!=3:failures.append("Expected three regional longhouses, found %d"%longhouses.size())
        var town_root:=region_root.get_node_or_null("TownRoot")
        if town_root==null:
            failures.append("Skeld town root is absent")
        else:
            for town_name in ["Frostharbor","Vardholm","Kelpwick"]:
                if town_root.get_node_or_null(town_name)==null:failures.append("%s architecture was not built"%town_name)
            for house in town_root.find_children("House_*","Node3D",true,false):
                if str(house.get_meta("architecture_set",""))=="skeld_coast":coastal_houses+=1
            if coastal_houses<42:failures.append("Only %d Skeld coastal houses were built"%coastal_houses)
            if town_root.find_child("*Fish and Net Yard",true,false)==null:
                failures.append("Skeld settlement working yards are missing")

    var south_crossing:=Vector2(-8400,-10800)
    var east_crossing:=Vector2(-3600,-13500)
    var open_sea:=Vector2(-9700,-14400)
    if not bool(main._sample_global_walkable(south_crossing.x,south_crossing.y)):
        failures.append("Skeld Pass has an invisible wall at the Stormbreak seam")
    if not bool(main._sample_global_walkable(east_crossing.x,east_crossing.y)):
        failures.append("Skeld Ice Road has an invisible wall at the Glacial seam")
    if bool(main._sample_global_walkable(open_sea.x,open_sea.y)):
        failures.append("The deep Grey Sea is incorrectly walkable")

    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    player.global_position=main._sample_global_height(-7200,-14400)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-14400,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="skeld_coast":failures.append("Skeld Coast gameplay profile did not activate")
    var director:=main.get_node("GameplayDirector")
    if director.minions.size()<20:failures.append("Skeld regional encounters did not populate")
    var regional_vendors:Array=director.get("_vendors")
    if regional_vendors.size()<3:failures.append("Skeld town services did not populate")

    player.global_position=main._sample_global_height(-3000,-14400)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-14400,-3000)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="glacial_range":failures.append("Glacial Range did not reactivate east of Skeld")
    player.global_position=main._sample_global_height(-7200,-14400)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-14400,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="skeld_coast":failures.append("Skeld Coast did not reactivate on the ice-road return")
    player.global_position=main._sample_global_height(-7200,-10400)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-10400,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="stormbreak_highlands":failures.append("Stormbreak did not reactivate south of Skeld")

    var atlas:Dictionary=main.get("_world_atlas_profile")
    var summaries:Array=atlas.get("region_summaries",[])
    var coast_summaries:=0
    for summary in summaries:
        if str(summary.get("zone_id",""))=="skeld_coast":coast_summaries+=1
    if coast_summaries!=1:failures.append("Skeld Coast appears %d times in atlas summaries"%coast_summaries)
    var extent:Vector2=atlas.get("map_extent",Vector2.ZERO)
    var center:Vector2=atlas.get("map_center",Vector2.ZERO)
    if extent.distance_to(Vector2(14400,21600))>.1:failures.append("Six-region atlas extent is not 14400 x 21600")
    if center.distance_to(Vector2(-3600,-7200))>.1:failures.append("Six-region atlas center is incorrect")

    print("SKELD_COAST_STREAMING_RUNTIME|ready=%s|houses=%d|walkable=%s/%s|sea_blocked=%s|active=%s|encounters=%d|vendors=%d|atlas_regions=%d|failures=%d"%[
        str(bool(main.get("_skeld_region_ready"))).to_lower(),coastal_houses,
        str(bool(main._sample_global_walkable(south_crossing.x,south_crossing.y))).to_lower(),
        str(bool(main._sample_global_walkable(east_crossing.x,east_crossing.y))).to_lower(),
        str(not bool(main._sample_global_walkable(open_sea.x,open_sea.y))).to_lower(),
        str(main.get("_active_zone_id")),director.minions.size(),regional_vendors.size(),summaries.size(),failures.size(),
    ])
    for failure in failures:push_error("SKELD_COAST_STREAM_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
