extends SceneTree

const MAIN_SCENE=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    var player:Node3D=main.get_node("Player")
    var player_id:=player.get_instance_id()
    var original_hp:float=float(player.get("hp"))
    await main._ensure_north_region_loaded()
    var region_root:=main.get_node_or_null("WorldRoot/StreamedRegions/NorthFrontier")
    if region_root==null:failures.append("north region root was not created")
    elif region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:failures.append("north terrain mesh was not populated")
    elif not (region_root.get_node("TerrainRoot/TerrainMesh/TerrainMesh_StaticBody/TerrainMeshCollision") as CollisionShape3D).shape is HeightMapShape3D:
        failures.append("north terrain did not use the travel-optimized heightmap collision")
    if not bool(main.get("_north_region_ready")):failures.append("north region never became ready")

    var south_edge:Vector3=main._sample_global_terrain_height(360.0,-3599.9)
    var north_edge:Vector3=main._sample_global_terrain_height(360.0,-3600.1)
    if absf(south_edge.y-north_edge.y)>.20:failures.append("runtime terrain sampler jumps at the seam")
    if not main._sample_global_walkable(360.0,-3600.0):failures.append("the pass road is blocked at the seam")
    await physics_frame
    var collision_probe:=PhysicsRayQueryParameters3D.create(
        Vector3(260.0,160.0,-4040.0),Vector3(260.0,-160.0,-4040.0),1
    )
    var terrain_hit:Dictionary=main.get_world_3d().direct_space_state.intersect_ray(collision_probe)
    if terrain_hit.is_empty():failures.append("north terrain heightmap has no physical ground")
    elif absf(float(terrain_hit.position.y)-main._sample_global_terrain_height(260.0,-4040.0).y)>1.2:
        failures.append("north physical ground does not match its visible height")

    var horses:Array[Node]=main.get_tree().get_nodes_in_group("rideable_horse")
    var mounted_horse:Node3D=null
    if horses.is_empty():
        failures.append("no rideable horse was available for the northbound regression")
    else:
        mounted_horse=horses[0] as Node3D
        if not player.mount_horse(mounted_horse):failures.append("test horse could not be mounted")
    main._prepare_gameplay_region_for_position(-3400.0)
    while bool(main.get("_region_gameplay_transition_busy")):
        await process_frame
    if str(main.get("_active_zone_id"))!="north_frontier":failures.append("gameplay region did not activate")
    if player.get_instance_id()!=player_id:failures.append("player node was replaced during region activation")
    if not is_equal_approx(float(player.get("hp")),original_hp):failures.append("player state changed during region activation")
    if mounted_horse!=null and not player.is_mounted():failures.append("northbound region activation dismounted the player")
    if mounted_horse!=null and mounted_horse.get_parent()!=player:failures.append("mounted horse was detached during region activation")
    var map_profile:Dictionary=main.get_node("UI/WorldMap").get("_profile")
    if Vector2(map_profile.get("map_extent",Vector2.ZERO)).distance_to(Vector2(21600,21600))>.1:
        failures.append("world map did not expose the planned seven-region atlas")
    var atlas_regions:Array=map_profile.get("region_summaries",[])
    for expected_region in ["starting_realm","north_frontier","glacial_range","western_reaches","stormbreak_highlands","skeld_coast","east_marches"]:
        var found_region:=false
        for region_data in atlas_regions:
            if str((region_data as Dictionary).get("zone_id",""))==expected_region:
                found_region=true
                break
        if not found_region:failures.append("world atlas is missing %s"%expected_region)
    var gate:=main.find_child("ZoneGate_North",true,false)
    if gate!=null:failures.append("a hard north portal is still visible")

    print("NORTH_RUNTIME|ready=%s|height_delta=%.3f|walkable=%s|player_persistent=%s|mounted=%s|failures=%d"%[
        str(main.get("_north_region_ready")),absf(south_edge.y-north_edge.y),
        str(main._sample_global_walkable(360.0,-3600.0)),str(player.get_instance_id()==player_id),
        str(player.is_mounted()),failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
