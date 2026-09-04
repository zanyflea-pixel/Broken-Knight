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
    await main._ensure_glacial_region_loaded()
    var region_root:=main.get_node_or_null("WorldRoot/StreamedRegions/GlacialRange")
    if region_root==null:failures.append("glacial streamed root was not created")
    elif region_root.get_node_or_null("TerrainRoot/TerrainMesh")==null:failures.append("glacial terrain was not populated")
    if not bool(main.get("_glacial_region_ready")):failures.append("glacial region never became ready")

    var south_edge:Vector3=main._sample_global_terrain_height(180.0,-10799.9)
    var north_edge:Vector3=main._sample_global_terrain_height(180.0,-10800.1)
    if absf(south_edge.y-north_edge.y)>.20:failures.append("runtime sampler jumps at glacial seam")
    if not main._sample_global_walkable(-520.0,-10800.0):failures.append("Icebound pass is blocked at the seam")

    main._prepare_gameplay_region_for_position(-11200.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    if str(main.get("_active_zone_id"))!="glacial_range":failures.append("glacial gameplay profile did not activate")
    if player.get_instance_id()!=player_id:failures.append("player was replaced at the second streaming seam")
    var director:Node=main.get_node("GameplayDirector")
    var trolls:=0
    var wildlife:=0
    for minion in director.get("minions"):
        var kind:=str(minion.get("kind",""))
        if kind=="frost_troll":trolls+=1
        elif kind.begins_with("wildlife_"):wildlife+=1
    if trolls<5:failures.append("authored Frost Troll encounters did not spawn")
    if wildlife<12:failures.append("glacial wildlife population is incomplete")
    var interaction_actions:Dictionary={}
    for interaction in director.get("_interactables"):
        var action:=str(interaction.get("action",""))
        interaction_actions[action]=int(interaction_actions.get(action,0))+1
    if int(interaction_actions.get("read_lore",0))<2:failures.append("glacial lore sites are unavailable")
    if int(interaction_actions.get("hidden_cache",0))<2:failures.append("glacial secrets are unavailable")
    var map_profile:Dictionary=main.get_node("UI/WorldMap").get("_profile")
    if Vector2(map_profile.get("map_extent",Vector2.ZERO)).distance_to(Vector2(21600,21600))>.1:
        failures.append("runtime atlas does not cover the planned seven-region world")

    print("GLACIAL_RUNTIME|ready=%s|height_delta=%.3f|walkable=%s|trolls=%d|wildlife=%d|discoveries=%s|failures=%d"%[
        str(main.get("_glacial_region_ready")),absf(south_edge.y-north_edge.y),
        str(main._sample_global_walkable(-520.0,-10800.0)),trolls,wildlife,str(interaction_actions),failures.size(),
    ])
    for failure in failures:push_error("GLACIAL_RUNTIME_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
