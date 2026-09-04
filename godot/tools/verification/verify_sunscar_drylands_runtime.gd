extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    # Population of the starter bake is irrelevant to this seam test. Enter
    # immediately, then build only the new neighbor in the normal streaming
    # pipeline so the runtime path remains representative and reasonably fast.
    await main.boot_world(Callable(),false,false)
    await main._ensure_southern_region_loaded()

    var contexts:Dictionary=main.get("_region_contexts")
    var starting:Dictionary=contexts.get("starting_realm",{})
    var south:Dictionary=contexts.get("sunscar_drylands",{})
    if south.is_empty():failures.append("Sunscar context was not registered")
    if not bool(main.get("_southern_region_ready")):failures.append("Sunscar never became ready")
    var region_root:Node3D=south.get("root")
    if not is_instance_valid(region_root) or region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:
        failures.append("Sunscar terrain was not installed")

    var start_result:Dictionary=starting.get("result",{})
    var south_result:Dictionary=south.get("result",{})
    var maximum_gap:=0.0
    if not start_result.is_empty() and not south_result.is_empty():
        for sample_index in range(193):
            var x:=lerpf(-3600.0,3600.0,float(sample_index)/192.0)
            var start_height:float=start_result.terrain_height_sampler.call(x,3600.0).y
            var south_height:float=south_result.terrain_height_sampler.call(x,-3600.0).y
            maximum_gap=maxf(maximum_gap,absf(start_height-south_height))
    else:maximum_gap=INF
    if maximum_gap>.02:failures.append("Runtime southern boundary has a %.4fm terrain crack"%maximum_gap)

    var crossing_point:=Vector2(-420,3600)
    var crossing_walkable:=bool(main._sample_global_walkable(crossing_point.x,crossing_point.y))
    if not crossing_walkable:failures.append("Sunward Realmroad seam has an invisible traversal wall")

    var local_profile:Dictionary=south.get("local_profile",{})
    var bridge_root:=region_root.get_node_or_null("BridgeRoot") if is_instance_valid(region_root) else null
    var bridge_count:=bridge_root.get_child_count() if bridge_root!=null else 0
    if bridge_count!=local_profile.get("ford_sites",[]).size():failures.append("Sunscar bridge population disagrees with authored crossings")
    var river_root:=region_root.get_node_or_null("RiverRoot") if is_instance_valid(region_root) else null
    if river_root==null or river_root.get_child_count()<2:failures.append("Sunscar watershed was not instantiated")
    var road_root:=region_root.get_node_or_null("RoadRoot") if is_instance_valid(region_root) else null
    if road_root==null or road_root.get_child_count()<3:failures.append("Sunscar road hierarchy was not instantiated")
    var town_root:=region_root.get_node_or_null("TownRoot") if is_instance_valid(region_root) else null
    if town_root==null:
        failures.append("Sunscar town root is absent")
    else:
        for town_name in ["Sundown Gate","Emberwell","Red Mesa Hold","Copper Hollow"]:
            if town_root.find_child(town_name,true,false)==null:failures.append("%s was not built"%town_name)

    var player:CharacterBody3D=main.get_node("Player")
    player.set_input_enabled(false)
    var horse:=Node3D.new();horse.name="SunscarTransitionTestHorse";main.add_child(horse)
    var mounted_before:bool=player.mount_horse(horse)
    if not mounted_before:failures.append("Could not mount for southern transition test")
    player.global_position=main._sample_global_height(-500.0,4500.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(4500.0,-500.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="sunscar_drylands":failures.append("Sunscar gameplay profile did not activate")
    if mounted_before and not player.is_mounted():failures.append("Southern transition dismounted the player")
    var director:=main.get_node("GameplayDirector")
    if director.minions.size()<16:failures.append("Sunscar regional encounters did not populate")
    var vendors:Array=director.get("_vendors")
    if vendors.size()<4:failures.append("Sunscar settlement services did not populate")

    player.global_position=main._sample_global_height(-500.0,3000.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(3000.0,-500.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="starting_realm":failures.append("Starting realm did not reactivate on northern return")
    if mounted_before and not player.is_mounted():failures.append("Southern return transition dismounted the player")

    var atlas:Dictionary=main.get("_world_atlas_profile")
    var summaries:Array=atlas.get("region_summaries",[])
    var south_summaries:=0
    for summary in summaries:
        if str(summary.get("zone_id",""))=="sunscar_drylands":south_summaries+=1
    if south_summaries!=1:failures.append("Sunscar appears %d times in atlas summaries"%south_summaries)
    if Vector2(atlas.get("map_extent",Vector2.ZERO)).distance_to(Vector2(21600,28800))>.1:
        failures.append("Runtime atlas did not expand south")

    print("SUNSCAR_DRYLANDS_RUNTIME|ready=%s|seam_gap=%.5f|walkable=%s|bridges=%d|river_meshes=%d|road_meshes=%d|active_return=%s|mounted=%s|encounters=%d|vendors=%d|atlas_regions=%d|failures=%d"%[
        str(bool(main.get("_southern_region_ready"))).to_lower(),maximum_gap,str(crossing_walkable).to_lower(),bridge_count,
        river_root.get_child_count() if river_root!=null else 0,road_root.get_child_count() if road_root!=null else 0,
        str(main.get("_active_zone_id")),str(player.is_mounted()).to_lower(),director.minions.size(),vendors.size(),summaries.size(),failures.size(),
    ])
    for failure in failures:push_error("SUNSCAR_DRYLANDS_RUNTIME_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
