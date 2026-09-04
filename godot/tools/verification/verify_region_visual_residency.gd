extends SceneTree


func _initialize()->void:call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_streamed_region_loaded("north_frontier")
    var starter_town:=main.get_node("WorldRoot/TownRoot") as Node3D
    var north_root:=main.get_node("WorldRoot/StreamedRegions/NorthFrontier") as Node3D
    var starter_registry:Variant=starter_town.get_meta("harvestable_tree_registry",[])
    main.set("_active_zone_id","north_frontier")
    main._update_region_visual_residency(0.0,-7200.0)
    if starter_town.visible:failures.append("far starter population stayed visible")
    if starter_town.process_mode!=Node.PROCESS_MODE_DISABLED:failures.append("far starter population stayed active")
    if not north_root.visible:failures.append("active north region was hidden")
    if starter_town.get_meta("harvestable_tree_registry",[])!=starter_registry:failures.append("sleeping starter region lost authored state")
    main.set("_active_zone_id","starting_realm")
    main._update_region_visual_residency(0.0,0.0)
    if not starter_town.visible:failures.append("returning did not wake starter population")
    if north_root.visible:failures.append("far north region stayed visible after returning")
    print("REGION_VISUAL_RESIDENCY|starter_returned=%s|north_slept=%s|state_preserved=%s|failures=%d"%[
        str(starter_town.visible),str(not north_root.visible),str(starter_town.get_meta("harvestable_tree_registry",[])==starter_registry),failures.size(),
    ])
    for failure in failures:push_error("REGION_VISUAL_RESIDENCY_FAILURE|%s"%failure)
    main.free()
    for _cleanup in range(4):await process_frame
    quit(0 if failures.is_empty() else 1)
