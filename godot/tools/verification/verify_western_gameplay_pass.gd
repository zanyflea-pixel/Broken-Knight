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
    var player:=main.get_node("Player")
    player.global_position=main._sample_global_height(-4750.0,-180.0)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-180.0,-4750.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame

    var gameplay:=main.get_node("GameplayDirector")
    if str(main.get("_active_zone_id"))!="western_reaches":failures.append("Western gameplay profile did not activate")

    var hostile_counts:Dictionary={}
    for enemy in gameplay.get("minions"):
        var kind:=str(enemy.get("kind","unknown"))
        hostile_counts[kind]=int(hostile_counts.get(kind,0))+1
    for required_kind in ["ashfang","bramble_wraith","imp"]:
        if not hostile_counts.has(required_kind):failures.append("Western encounter roster lacks %s"%required_kind)
    if not hostile_counts.keys().any(func(kind:String)->bool:return kind.begins_with("zombie_")):
        failures.append("Western encounter roster lacks Gravebound")

    var vendor_types:Array[String]=[]
    for vendor in gameplay.get("_vendors"):
        if not is_instance_valid(vendor) or not vendor.has_meta("vendor_data"):continue
        vendor_types.append(str(vendor.get_meta("vendor_data").get("type_name","")))
    for required_vendor in ["Oakrest Woodwright","Rainhaven River Trade","Stonecross Masonry"]:
        if required_vendor not in vendor_types:failures.append("Regional vendor %s is missing"%required_vendor)
    if gameplay.get_map_service_markers().size()<6:failures.append("Western map exposes fewer than six settlement services")

    for entry in ["oakrest_ledger","rainward_abbey","galehorn_watch"]:
        var lore_text:=str(gameplay._lore_entry_text(entry))
        if lore_text.begins_with("Weather and war"):failures.append("%s still uses fallback lore"%entry)

    var claimed:Dictionary=gameplay.get("_quest_claimed")
    claimed["road_imps"]=true
    gameplay.set("_quest_claimed",claimed)
    gameplay.get_quest_state()
    var counters:Dictionary=gameplay.get("_gathered_counts")
    counters["rainward_threats"]=8
    gameplay.set("_gathered_counts",counters)
    gameplay._check_quest_rewards()
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("rainward_patrol",false)):failures.append("Bells in the Rain did not complete at eight Western hostiles")

    # Revealing the second chapter establishes a zero baseline before opening
    # a real authored Western cache.
    gameplay.get_quest_state()
    var relic_cache:Dictionary={}
    for interaction in gameplay.get("_interactables"):
        if str(interaction.get("action",""))=="hidden_cache" and str(interaction.get("loot_table",""))=="rainward_relics":
            relic_cache=interaction
            break
    if relic_cache.is_empty():
        failures.append("Abbot's Flooded Reliquary interactable was not built")
    else:
        gameplay._open_hidden_cache(relic_cache)
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("rainward_reliquary",false)):failures.append("Abbot's Last Crossing did not complete from a Western secret")
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("id",""))=="rainward_patrol_signet"):
        failures.append("Rainward reliquary quest did not award its patrol signet")
    var tideglass_drop_found:=false
    for dropped in gameplay.get("loot"):
        if str(dropped.get("reward",{}).get("id",""))=="abbots_tideglass_signet":tideglass_drop_found=true
    if not tideglass_drop_found:failures.append("Abbot's cache did not drop the authored Tideglass Signet")

    player.add_material("cloth",5)
    player.add_material("resin",3)
    player.add_material("leather",2)
    var craft_result:String=gameplay.craft_recipe("rainward_cloak")
    if not craft_result.begins_with("Crafted "):failures.append("Rainward Waxed Cloak recipe failed: %s"%craft_result)
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("name",""))=="Rainward Waxed Cloak"):
        failures.append("Crafted Rainward cloak was not placed in the bag")

    print("WESTERN_GAMEPLAY_PASS|hostiles=%d|types=%d|vendors=%d|services=%d|patrol=%s|reliquary=%s|crafted=%s|failures=%d"%[
        gameplay.get("minions").size(),hostile_counts.size(),vendor_types.size(),gameplay.get_map_service_markers().size(),
        str(bool(claimed.get("rainward_patrol",false))).to_lower(),str(bool(claimed.get("rainward_reliquary",false))).to_lower(),
        str(craft_result.begins_with("Crafted ")).to_lower(),failures.size(),
    ])
    for failure in failures:push_error("WESTERN_GAMEPLAY_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
