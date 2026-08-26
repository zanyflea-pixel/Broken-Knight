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
    var player:=main.get_node("Player")
    player.global_position=main._sample_global_height(8100.0,455.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(455.0,8100.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame

    var gameplay:=main.get_node("GameplayDirector")
    if str(main.get("_active_zone_id"))!="east_marches":failures.append("Eastern Marches gameplay profile did not activate")

    var hostile_counts:Dictionary={}
    var basilisk_pivots_valid:=false
    for enemy in gameplay.get("minions"):
        var kind:=str(enemy.get("kind","unknown"))
        hostile_counts[kind]=int(hostile_counts.get(kind,0))+1
        if kind!="ashscale_basilisk":continue
        var model:Node3D=enemy.get("node").get_node_or_null("AshscaleBasiliskModel")
        if is_instance_valid(model):
            basilisk_pivots_valid=\
                model.find_child("JawPivot",true,false)!=null and \
                model.find_child("LegPivot_LF",true,false)!=null and \
                model.find_child("TailPivot_1",true,false)!=null
    if int(hostile_counts.get("ashscale_basilisk",0))<5:failures.append("Cinderwatch did not spawn its five Ashscale Basilisks")
    if not basilisk_pivots_valid:failures.append("Ashscale Basilisk animation pivots are missing after GLB import")

    var vendor_types:Array[String]=[]
    for vendor in gameplay.get("_vendors"):
        if not is_instance_valid(vendor) or not vendor.has_meta("vendor_data"):continue
        vendor_types.append(str(vendor.get_meta("vendor_data").get("type_name","")))
    for required_vendor in ["Dawnford Caravan Factor","March Keep Warden Stores","Cinderwatch Signal Forge","Amberfield Grain Exchange","Saltwatch Meadow Trade"]:
        if required_vendor not in vendor_types:failures.append("Regional vendor %s is missing"%required_vendor)
    if gameplay.get_map_service_markers().size()<8:failures.append("Eastern map exposes fewer than eight settlement services")

    for entry in ["dawnford_ledger","ember_span_oath","cinderwatch_record"]:
        var lore_text:=str(gameplay._lore_entry_text(entry))
        if lore_text.begins_with("Weather and war"):failures.append("%s still uses fallback lore"%entry)

    var claimed:Dictionary=gameplay.get("_quest_claimed")
    claimed["road_imps"]=true
    gameplay.set("_quest_claimed",claimed)
    gameplay.get_quest_state()
    var counters:Dictionary=gameplay.get("_gathered_counts")
    counters["marcher_threats"]=10
    gameplay.set("_gathered_counts",counters)
    gameplay._check_quest_rewards()
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("marcher_beacon",false)):failures.append("Ash Beneath the Beacon did not complete at ten Eastern hostiles")

    gameplay.get_quest_state()
    var eastern_caches:Array[Dictionary]=[]
    for interaction in gameplay.get("_interactables"):
        if str(interaction.get("action",""))!="hidden_cache":continue
        if str(interaction.get("loot_table","")) in ["marcher_supplies","marcher_relics"]:
            eastern_caches.append(interaction)
    if eastern_caches.size()<2:
        failures.append("Fewer than two Eastern oath caches were built")
    else:
        gameplay._open_hidden_cache(eastern_caches[0])
        gameplay._open_hidden_cache(eastern_caches[1])
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("marcher_oath",false)):failures.append("What Ember Span Swore did not complete from two Eastern caches")
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("id",""))=="emberglass_reward_oath_band"):
        failures.append("Eastern oath quest did not award the Emberglass Oath Band")
    var witness_drop_found:=false
    for dropped in gameplay.get("loot"):
        if str(dropped.get("reward",{}).get("id",""))=="barrow_witness_band":witness_drop_found=true
    if not witness_drop_found:failures.append("Amber Barrow cache did not drop the authored Witness Band")

    player.add_material("ore",11)
    player.add_material("leather",6)
    player.add_material("cloth",3)
    var craft_result:String=gameplay.craft_recipe("marchwarden_lamellar")
    if not craft_result.begins_with("Crafted "):failures.append("Marchwarden Lamellar recipe failed: %s"%craft_result)
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("name",""))=="Marchwarden Lamellar"):
        failures.append("Crafted Marchwarden Lamellar was not placed in the bag")

    print("EASTERN_GAMEPLAY_PASS|hostiles=%d|types=%d|basilisks=%d|pivots=%s|vendors=%d|services=%d|beacon=%s|oath=%s|crafted=%s|failures=%d"%[
        gameplay.get("minions").size(),hostile_counts.size(),int(hostile_counts.get("ashscale_basilisk",0)),
        str(basilisk_pivots_valid).to_lower(),vendor_types.size(),gameplay.get_map_service_markers().size(),
        str(bool(claimed.get("marcher_beacon",false))).to_lower(),str(bool(claimed.get("marcher_oath",false))).to_lower(),
        str(craft_result.begins_with("Crafted ")).to_lower(),failures.size(),
    ])
    for failure in failures:push_error("EASTERN_GAMEPLAY_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
