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
    await main._ensure_stormbreak_region_loaded()
    var player:=main.get_node("Player")
    player.global_position=main._sample_global_height(-7420,-7540)+Vector3.UP*.08
    main._prepare_gameplay_region_for_position(-7540,-7420)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    var gameplay:=main.get_node("GameplayDirector")
    if str(main.get("_active_zone_id"))!="stormbreak_highlands":failures.append("Stormbreak gameplay profile did not activate")

    var hostile_counts:Dictionary={}
    for enemy in gameplay.get("minions"):
        var kind:=str(enemy.get("kind","unknown"))
        hostile_counts[kind]=int(hostile_counts.get(kind,0))+1
    for required_kind in ["ashfang","bramble_wraith","imp","frost_troll"]:
        if not hostile_counts.has(required_kind):failures.append("Stormbreak encounter roster lacks %s"%required_kind)
    if not hostile_counts.keys().any(func(kind:String)->bool:return kind.begins_with("zombie_")):
        failures.append("Stormbreak encounter roster lacks Gravebound")

    var vendor_types:Array[String]=[]
    for vendor in gameplay.get("_vendors"):
        if not is_instance_valid(vendor) or not vendor.has_meta("vendor_data"):continue
        vendor_types.append(str(vendor.get_meta("vendor_data").get("type_name","")))
    for required_vendor in ["Stormbreak Warden Stores","Stormbreak Highland Forge","Moorwatch Peat & Wool","Cairnstead Drover Market"]:
        if required_vendor not in vendor_types:failures.append("Regional vendor %s is missing"%required_vendor)
    if gameplay.get_map_service_markers().size()<7:failures.append("Stormbreak map exposes fewer than seven settlement services")

    for entry in ["stormward_compact","shattered_choir","blacktarn_notes"]:
        var lore_text:=str(gameplay._lore_entry_text(entry))
        if lore_text.begins_with("Weather and war"):failures.append("%s still uses fallback lore"%entry)

    var claimed:Dictionary=gameplay.get("_quest_claimed")
    claimed["rainward_patrol"]=true
    gameplay.set("_quest_claimed",claimed)
    gameplay.get_quest_state()
    var counters:Dictionary=gameplay.get("_gathered_counts")
    counters["stormbreak_threats"]=10
    gameplay.set("_gathered_counts",counters)
    gameplay._check_quest_rewards()
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("stormbreak_beacon",false)):failures.append("Fire on Stormscar did not complete at ten highland hostiles")

    gameplay.get_quest_state()
    var opened_tables:Array[String]=[]
    var interactions:Array=gameplay.get("_interactables").duplicate()
    for interaction in interactions:
        var table:=str(interaction.get("loot_table",""))
        if str(interaction.get("action",""))!="hidden_cache" or table not in ["stormbreak_beacon","stormbreak_relics"]:continue
        gameplay._open_hidden_cache(interaction)
        opened_tables.append(table)
    if opened_tables.size()!=2:failures.append("Only %d of two authored Stormbreak quest caches were built"%opened_tables.size())
    claimed=gameplay.get("_quest_claimed")
    if not bool(claimed.get("stormbreak_choir",false)):failures.append("The Hymn Beneath Thunder did not complete from two highland secrets")
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("id",""))=="tempest_choir_reward_band"):
        failures.append("Stormbreak secret quest did not award the Tempest Choir Band")
    var relic_drop_found:=false
    for dropped in gameplay.get("loot"):
        if str(dropped.get("reward",{}).get("id",""))=="tempest_choir_band":relic_drop_found=true
    if not relic_drop_found:failures.append("Shattered Choir cache did not drop its authored relic")

    player.add_material("cloth",6)
    player.add_material("leather",4)
    player.add_material("resin",3)
    player.add_material("ore",2)
    var craft_result:String=gameplay.craft_recipe("stormward_mantle")
    if not craft_result.begins_with("Crafted "):failures.append("Stormward Mantle recipe failed: %s"%craft_result)
    if not player.bag_slots.any(func(item:Dictionary)->bool:return str(item.get("name",""))=="Stormward Mantle"):
        failures.append("Crafted Stormward Mantle was not placed in the bag")

    print("STORMBREAK_GAMEPLAY_PASS|hostiles=%d|types=%d|vendors=%d|services=%d|beacon=%s|choir=%s|crafted=%s|failures=%d"%[
        gameplay.get("minions").size(),hostile_counts.size(),vendor_types.size(),gameplay.get_map_service_markers().size(),
        str(bool(claimed.get("stormbreak_beacon",false))).to_lower(),str(bool(claimed.get("stormbreak_choir",false))).to_lower(),
        str(craft_result.begins_with("Crafted ")).to_lower(),failures.size(),
    ])
    for failure in failures:push_error("STORMBREAK_GAMEPLAY_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
