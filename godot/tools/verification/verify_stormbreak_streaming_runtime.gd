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
    await main._ensure_north_region_loaded()
    await main._ensure_stormbreak_region_loaded()

    var contexts:Dictionary=main.get("_region_contexts")
    var storm:Dictionary=contexts.get("stormbreak_highlands",{})
    if storm.is_empty():failures.append("Stormbreak context was not registered")
    if not bool(main.get("_stormbreak_region_ready")):failures.append("Stormbreak never became ready")
    var region_root:Node3D=storm.get("root")
    var highland_houses:=0
    if not is_instance_valid(region_root) or region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:
        failures.append("Stormbreak terrain was not populated")
    if is_instance_valid(region_root):
        var bridge_root:=region_root.get_node_or_null("BridgeRoot")
        if bridge_root==null or bridge_root.get_child_count()!=1:
            failures.append("Stormbreak should build exactly one intentional bridge")
        for landmark_name in ["StormbreakBeacon","StormbreakShelter","ShatteredChoir"]:
            if region_root.find_child(landmark_name,true,false)==null:
                failures.append("Stormbreak Blender landmark %s was not instantiated"%landmark_name)
        var town_root:=region_root.get_node_or_null("TownRoot")
        if town_root==null:
            failures.append("Stormbreak town root is absent")
        else:
            for town_name in ["Stormbreak Hold","Cairnstead","Moorwatch"]:
                if town_root.get_node_or_null(town_name)==null:failures.append("%s architecture was not built"%town_name)
            for house in town_root.find_children("House_*","Node3D",true,false):
                if str(house.get_meta("architecture_set",""))=="stormbreak_highland":highland_houses+=1
            if highland_houses<42:failures.append("Only %d Stormbreak houses were built"%highland_houses)
            if town_root.find_child("*Drovers Shelter",true,false)==null:
                failures.append("Stormbreak settlement wind shelters are missing")

    var south_crossing:=Vector2(-4480,-3600)
    var east_crossing:=Vector2(-3600,-8520)
    if not bool(main._sample_global_walkable(south_crossing.x,south_crossing.y)):
        failures.append("Galehorn high road still has an invisible wall at the Western seam")
    if not bool(main._sample_global_walkable(east_crossing.x,east_crossing.y)):
        failures.append("Greyfen high road still has an invisible wall at the Frontier seam")

    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    player.global_position=main._sample_global_height(-7200,-7200)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-7200,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="stormbreak_highlands":failures.append("Stormbreak gameplay profile did not activate")
    var director:=main.get_node("GameplayDirector")
    if director.minions.size()<20:failures.append("Stormbreak regional encounters did not populate")
    var regional_vendors:Array=director.get("_vendors")
    if regional_vendors.size()<3:failures.append("Stormbreak town services did not populate")

    player.global_position=main._sample_global_height(-3000,-7200)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-7200,-3000)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="north_frontier":failures.append("North Frontier did not reactivate east of Stormbreak")
    player.global_position=main._sample_global_height(-7200,-7200)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-7200,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="stormbreak_highlands":failures.append("Stormbreak did not reactivate on the east-road return")
    player.global_position=main._sample_global_height(-7200,-3000)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-3000,-7200)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="western_reaches":failures.append("Western Reaches did not reactivate south of Stormbreak")

    var atlas:Dictionary=main.get("_world_atlas_profile")
    var summaries:Array=atlas.get("region_summaries",[])
    var storm_summaries:=0
    for summary in summaries:
        if str(summary.get("zone_id",""))=="stormbreak_highlands":storm_summaries+=1
    if storm_summaries!=1:failures.append("Stormbreak appears %d times in atlas summaries"%storm_summaries)
    var extent:Vector2=atlas.get("map_extent",Vector2.ZERO)
    var center:Vector2=atlas.get("map_center",Vector2.ZERO)
    if extent.distance_to(Vector2(14400,21600))>.1:failures.append("Five-region atlas extent is not 14400 x 21600")
    if center.distance_to(Vector2(-3600,-7200))>.1:failures.append("Five-region atlas center is incorrect")

    print("STORMBREAK_STREAMING_RUNTIME|ready=%s|houses=%d|walkable=%s/%s|active=%s|encounters=%d|vendors=%d|atlas_regions=%d|failures=%d"%[
        str(bool(main.get("_stormbreak_region_ready"))).to_lower(),highland_houses,
        str(bool(main._sample_global_walkable(south_crossing.x,south_crossing.y))).to_lower(),
        str(bool(main._sample_global_walkable(east_crossing.x,east_crossing.y))).to_lower(),
        str(main.get("_active_zone_id")),director.minions.size(),regional_vendors.size(),summaries.size(),failures.size(),
    ])
    for failure in failures:push_error("STORMBREAK_STREAM_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
