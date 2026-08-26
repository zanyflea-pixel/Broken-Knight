extends SceneTree

const MAIN_SCENE=preload("res://scenes/Main.tscn")


func _initialize()->void:
    call_deferred("_run")


func _run()->void:
    var failures:Array[String]=[]
    var profile_builder:RefCounted=load("res://scripts/world/WorldProfile.gd").new()
    var north:Dictionary=profile_builder.make_zone_profile("north_frontier")
    if str(north.get("biome_id",""))!="alpine_frontier":failures.append("north biome identity is missing")
    if float(north.get("snow_strength",0.0))<=0.0:failures.append("north has no snow-cap terrain rule")
    if north.get("wildlife_sites",[]).size()<3:failures.append("north wildlife ranges are incomplete")
    if north.get("encounter_sites",[]).size()<4:failures.append("north encounter variety is incomplete")
    if north.get("secret_sites",[]).is_empty():failures.append("north has no authored secrets")
    var rivers:Array=north.get("river_corridors",[])
    if rivers.is_empty():failures.append("north has no river system")
    else:
        var river:Dictionary=rivers[0]
        if not str(river.get("source_kind","")).begins_with("snowmelt"):failures.append("north river does not originate as snowmelt")
        if float(river.get("source_width",99.0))>=float(river.get("mouth_width",0.0)):failures.append("north river does not widen downstream")

    for asset_path in [
        "res://assets/animals/highland_deer_v1.glb",
        "res://assets/animals/highland_hare_v1.glb",
        "res://assets/animals/highland_grouse_v1.glb",
        "res://assets/animals/venison_cut_v1.glb",
    ]:
        var scene:=load(asset_path) as PackedScene
        if scene==null:
            failures.append("wildlife asset failed to import: %s"%asset_path)
            continue
        var instance:=scene.instantiate()
        if instance.get_child_count()==0:failures.append("wildlife asset is visually empty: %s"%asset_path)
        instance.free()

    var main:=MAIN_SCENE.instantiate()
    main.auto_boot_enabled=false
    root.add_child(main)
    await main.boot_world(Callable(),false,true)
    await main._ensure_north_region_loaded()
    main._prepare_gameplay_region_for_position(-4300.0)
    while bool(main.get("_region_gameplay_transition_busy")):await process_frame
    var director:Node=main.get_node("GameplayDirector")
    var species:Dictionary={}
    for minion in director.get("minions"):
        var kind:=str(minion.get("kind",""))
        if kind.begins_with("wildlife_"):species[kind]=int(species.get(kind,0))+1
    for expected in ["wildlife_deer","wildlife_hare","wildlife_grouse"]:
        if int(species.get(expected,0))<=0:failures.append("runtime did not spawn %s"%expected)
    var townfolk:Array=director.get("_townfolk")
    if townfolk.size()<8:failures.append("regional settlements have no scheduled population")
    director.call("_tick_townfolk",.10)
    var interaction_actions:Dictionary={}
    for interaction in director.get("_interactables"):
        interaction_actions[str(interaction.get("action",""))]=int(interaction_actions.get(str(interaction.get("action","")),0))+1
    if int(interaction_actions.get("read_lore",0))<2:failures.append("north readable lore sites were not built")
    if int(interaction_actions.get("hidden_cache",0))<2:failures.append("north hidden caches were not built")

    var hero:Node=main.get_node("Player")
    var slots:Dictionary=hero.get("equipment_slots")
    if not slots.has("ring_left") or not slots.has("ring_right"):failures.append("two ring equipment slots are unavailable")
    hero.add_bag_item({"id":"test_iron_sword","slot":"mainhand","name":"Test Sword","power":5})
    var item:Dictionary=hero.get("bag_slots")[-1]
    if not item.has("durability") or not item.has("max_durability"):failures.append("ordinary equipment has no durability state")
    hero.get("equipment_slots")["ring_left"]={"id":"test_wayfarer","slot":"ring_left","effect":"windstep","durability":50.0,"max_durability":50.0}
    if not hero.has_equipment_effect("windstep"):failures.append("equipped ring utility effect is inactive")
    var recipes:Array=director.get_recipes()
    if not recipes.any(func(recipe:Dictionary)->bool:return str(recipe.get("id",""))=="hunter_venison"):
        failures.append("hunted meat has no cooking recipe")

    var world_map:Control=main.get_node("UI/WorldMap")
    world_map.call("_set_map_scale",0)
    var local_extent:Vector2=world_map.call("_map_extent")
    world_map.call("_set_map_scale",1)
    var region_extent:Vector2=world_map.call("_map_extent")
    world_map.call("_set_map_scale",2)
    var world_extent:Vector2=world_map.call("_map_extent")
    if not (local_extent.x*local_extent.y<region_extent.x*region_extent.y and region_extent.x*region_extent.y<world_extent.x*world_extent.y):failures.append("map scales do not reveal progressively more world")

    print("EXPANSION_FOUNDATION|wildlife=%s|townfolk=%d|discoveries=%s|local=%.0f|region=%.0f|world=%.0f|failures=%d"%[
        str(species),townfolk.size(),str(interaction_actions),local_extent.x,region_extent.x,world_extent.x,failures.size(),
    ])
    for failure in failures:push_error("EXPANSION_FOUNDATION_FAILURE|%s"%failure)
    quit(0 if failures.is_empty() else 1)
