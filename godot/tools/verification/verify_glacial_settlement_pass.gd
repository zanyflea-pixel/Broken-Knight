extends SceneTree

const MAIN_SCENE:PackedScene=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _count_architecture(root:Node,architecture_set:String)->int:
    var count:=0
    if str(root.get_meta("architecture_set",""))==architecture_set:count+=1
    for child in root.get_children():count+=_count_architecture(child,architecture_set)
    return count


func _run()->void:
    var failures:Array[String]=[]
    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_glacial_region_loaded()
    main._prepare_gameplay_region_for_position(-15000.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame

    var context:Dictionary=main.get("_region_contexts").get("glacial_range",{})
    var region_root:Node3D=context.get("root")
    var town_root:=region_root.get_node("TownRoot") if is_instance_valid(region_root) else null
    var icewatch:=town_root.get_node_or_null("Icewatch Hold") if is_instance_valid(town_root) else null
    var rimegate:=town_root.get_node_or_null("Rimegate") if is_instance_valid(town_root) else null
    if icewatch==null:failures.append("Icewatch Hold architecture is missing")
    if rimegate==null:failures.append("Rimegate architecture is missing")
    var icewatch_houses:=_count_architecture(icewatch,"icewatch_hold") if icewatch!=null else 0
    var rimegate_houses:=_count_architecture(rimegate,"rimegate_lodge") if rimegate!=null else 0
    if icewatch_houses<12:failures.append("Icewatch has too few authored houses: %d"%icewatch_houses)
    if rimegate_houses<12:failures.append("Rimegate has too few authored houses: %d"%rimegate_houses)

    var gameplay:=main.get_node("GameplayDirector")
    var vendor_names:Array[String]=[]
    for vendor in gameplay.get("_vendors"):
        if is_instance_valid(vendor):vendor_names.append(str(vendor.name))
    if not vendor_names.any(func(value:String):return value.begins_with("Icewatch Hold")):
        failures.append("Icewatch vendors are missing")
    if not vendor_names.any(func(value:String):return value.begins_with("Rimegate")):
        failures.append("Rimegate vendors are missing")
    var crafting_count:=0
    var campfire_count:=0
    for interaction in gameplay.get("_interactables"):
        if str(interaction.get("action",""))=="craft":crafting_count+=1
        if str(interaction.get("action",""))=="campfire":campfire_count+=1
    if crafting_count<2:failures.append("Glacial crafting yards are missing")
    if campfire_count<4:failures.append("Glacial expedition camps are not functional: %d"%campfire_count)

    var props_root:=region_root.get_node("PropsRoot") if is_instance_valid(region_root) else null
    for required_name in ["GlacierTerminus","GlacierTongue","IceSpire","MoraineCluster","FrozenDeadfall","FrozenObservatory","FrostlineRefuge","SurveyShelter"]:
        if props_root==null or props_root.find_child(required_name,true,false)==null:
            failures.append("Missing glacial environment asset: %s"%required_name)

    print("GLACIAL_SETTLEMENT_PASS|icewatch_houses=%d|rimegate_houses=%d|vendors=%d|crafting=%d|campfires=%d|failures=%d"%[
        icewatch_houses,rimegate_houses,vendor_names.size(),crafting_count,campfire_count,failures.size(),
    ])
    for failure in failures:push_error(failure)
    quit(0 if failures.is_empty() else 1)
