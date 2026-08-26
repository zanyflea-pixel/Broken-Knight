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
    await main._ensure_east_region_loaded()

    var contexts:Dictionary=main.get("_region_contexts")
    var starting:Dictionary=contexts.get("starting_realm",{})
    var east:Dictionary=contexts.get("east_marches",{})
    if east.is_empty():failures.append("Eastern Marches context was not registered")
    if not bool(main.get("_east_region_ready")):failures.append("Eastern Marches never became ready")
    var region_root:Node3D=east.get("root")
    if not is_instance_valid(region_root) or region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:
        failures.append("Eastern Marches terrain was not populated")

    var start_result:Dictionary=starting.get("result",{})
    var east_result:Dictionary=east.get("result",{})
    var maximum_gap:=0.0
    if not start_result.is_empty() and not east_result.is_empty():
        for sample_index in range(193):
            var z:=lerpf(-3600.0,3600.0,float(sample_index)/192.0)
            var start_height:float=start_result.terrain_height_sampler.call(3600.0,z).y
            var east_height:float=east_result.terrain_height_sampler.call(-3600.0,z).y
            maximum_gap=maxf(maximum_gap,absf(start_height-east_height))
    else:
        maximum_gap=INF
    if maximum_gap>.015:failures.append("Runtime eastern boundary has a %.4fm terrain crack"%maximum_gap)

    var crossing_point:=Vector2(3600,1050)
    if not bool(main._sample_global_walkable(crossing_point.x,crossing_point.y)):
        failures.append("Eastern realmroad seam still has an invisible traversal wall")

    var east_profile:Dictionary=east.get("local_profile",{})
    var bridge_root:=region_root.get_node_or_null("BridgeRoot") if is_instance_valid(region_root) else null
    var bridge_count:=bridge_root.get_child_count() if bridge_root!=null else 0
    var authored_bridge_count:int=east_profile.get("ford_sites",[]).size()
    if bridge_count!=authored_bridge_count:
        var bridge_names:Array[String]=[]
        if bridge_root!=null:
            for child in bridge_root.get_children():bridge_names.append(str(child.name))
        failures.append("Eastern Marches built %d bridges for %d authored crossings: %s"%[bridge_count,authored_bridge_count,", ".join(bridge_names)])
    var town_root:=region_root.get_node_or_null("TownRoot") if is_instance_valid(region_root) else null
    var marcher_houses:=0
    if town_root==null:
        failures.append("Eastern town root is absent")
    else:
        for town_name in ["Dawnford","Amberfield","March Keep","Saltwatch"]:
            if town_root.find_child(town_name,true,false)==null:
                failures.append("%s architecture was not built"%town_name)
        for house in town_root.find_children("House_*","Node3D",true,false):
            if str(house.get_meta("architecture_set","")) in ["marcher_timber","marcher_stone"]:
                marcher_houses+=1
        if marcher_houses<40:failures.append("Only %d marcher houses were built"%marcher_houses)
    var river_root:=region_root.get_node_or_null("RiverRoot") if is_instance_valid(region_root) else null
    if river_root==null or river_root.get_child_count()<3:
        failures.append("Eastern watershed did not instantiate all three corridors")
    var road_root:=region_root.get_node_or_null("RoadRoot") if is_instance_valid(region_root) else null
    if road_root==null or road_root.get_child_count()<3:
        failures.append("Eastern road hierarchy did not instantiate all three routes")

    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    # A headless world boot intentionally omits the optional town horse. A
    # lightweight mount node still verifies the transition contract itself:
    # streamed outdoor region swaps must preserve the player's active mount.
    var horse:Node3D=Node3D.new()
    horse.name="EasternTransitionTestHorse"
    main.add_child(horse)
    var mounted_before:bool=player.mount_horse(horse)
    if not mounted_before:failures.append("Could not enter a mounted state for seamless-crossing verification")

    player.global_position=main._sample_global_height(4500.0,1000.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(1000.0,4500.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="east_marches":failures.append("Eastern gameplay profile did not activate")
    if mounted_before and not player.is_mounted():failures.append("Eastern streaming transition dismounted the player")
    var director:=main.get_node("GameplayDirector")
    if director.minions.size()<20:failures.append("Eastern regional encounters did not populate")
    var regional_vendors:Array=director.get("_vendors")
    if regional_vendors.size()<4:failures.append("Eastern settlement services did not populate")
    var state_before:Dictionary=director.get_zone_transition_state()

    player.global_position=main._sample_global_height(3000.0,1000.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(1000.0,3000.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="starting_realm":failures.append("Starting gameplay profile did not reactivate on return")
    if mounted_before and not player.is_mounted():failures.append("Eastern return transition dismounted the player")
    var state_after:Dictionary=director.get_zone_transition_state()
    if state_before.get("quest_claimed",{})!=state_after.get("quest_claimed",{}):
        failures.append("Quest state changed during the Eastern Marches round trip")

    var atlas:Dictionary=main.get("_world_atlas_profile")
    var summaries:Array=atlas.get("region_summaries",[])
    var east_summaries:=0
    for summary in summaries:
        if str(summary.get("zone_id",""))=="east_marches":east_summaries+=1
    if east_summaries!=1:failures.append("Eastern Marches appears %d times in atlas summaries"%east_summaries)
    var extent:Vector2=atlas.get("map_extent",Vector2.ZERO)
    var center:Vector2=atlas.get("map_center",Vector2.ZERO)
    if extent.distance_to(Vector2(21600,21600))>.1:failures.append("Seven-region atlas extent is not 21600 x 21600")
    if center.distance_to(Vector2(0,-7200))>.1:failures.append("Seven-region atlas center is incorrect")

    print("EASTERN_MARCHES_RUNTIME|ready=%s|seam_gap=%.5f|walkable=%s|houses=%d|bridges=%d|river_meshes=%d|road_meshes=%d|active_return=%s|mounted=%s|encounters=%d|vendors=%d|atlas_regions=%d|failures=%d"%[
        str(bool(main.get("_east_region_ready"))).to_lower(),maximum_gap,
        str(bool(main._sample_global_walkable(crossing_point.x,crossing_point.y))).to_lower(),marcher_houses,
        bridge_count,river_root.get_child_count() if river_root!=null else 0,road_root.get_child_count() if road_root!=null else 0,
        str(main.get("_active_zone_id")),str(player.is_mounted()).to_lower(),director.minions.size(),regional_vendors.size(),summaries.size(),failures.size(),
    ])
    for failure in failures:push_error("EASTERN_MARCHES_RUNTIME_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
