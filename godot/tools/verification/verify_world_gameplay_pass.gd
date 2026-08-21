extends SceneTree

var failures: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func _check(condition: bool, label: String) -> void:
    if not condition:
        failures.append(label)
        push_error("WORLD_PASS_FAIL|%s" % label)


func _run() -> void:
    var scene_resource := load("res://scenes/Main.tscn") as PackedScene
    var main := scene_resource.instantiate()
    main.set("auto_boot_enabled",false)
    root.add_child(main)
    await main.boot_world(Callable(),false,true)

    var player: Node = main.get_node("Player")
    var director: Node = main.get_node("GameplayDirector")

    main._set_map_open(true)
    _check(paused, "map_pauses_world")
    _check(not player._input_enabled, "map_disables_player_input")
    main._set_hero_menu(true)
    main._set_map_open(false)
    _check(paused, "closing_one_of_two_menus_keeps_pause")
    main._set_hero_menu(false)
    _check(not paused, "closing_last_menu_resumes")

    main._set_admin_menu(true)
    _check(paused, "admin_menu_pauses")
    main._set_admin_menu(false)
    main._set_menu_open(true)
    _check(paused, "escape_menu_pauses")
    main._set_menu_open(false)
    main._open_vendor_menu(director._vendor_catalog("provisioner", "Test"))
    _check(paused, "vendor_menu_pauses")
    main._close_vendor_menu()
    main._open_collection_menu(main.get_node("UI/SkillsMenu"))
    _check(paused, "skills_menu_pauses")
    main._close_collection_menu()
    main._open_collection_menu(main.get_node("UI/QuestMenu"))
    _check(paused, "quest_menu_pauses")
    main._close_collection_menu()
    _check(not paused, "collection_close_resumes")

    director._clear_minions()
    player.equip_item_id("royal_vanguard_staff")
    _check(player.has_magic_staff_equipped(), "staff_equipped_for_skill_test")
    player.mana = 999.0
    director.skill_levels[0] = 5
    director.cooldowns[0] = 0.0
    director._cast_spark()
    _check(director.projectiles.size() == 2, "spark_level_5_twin_spread")
    for projectile in director.projectiles:
        if is_instance_valid(projectile.node):
            projectile.node.queue_free()
    director.projectiles.clear()
    player.mana = 999.0
    director.skill_levels[0] = 10
    director.cooldowns[0] = 0.0
    director._cast_spark()
    _check(director.projectiles.size() == 3, "spark_level_10_triple_spread")
    if not director.projectiles.is_empty():
        _check(int(director.projectiles[0].pierce) == 1, "spark_level_10_pierces")
    for projectile in director.projectiles:
        if is_instance_valid(projectile.node):
            projectile.node.queue_free()
    director.projectiles.clear()
    player.mana = 999.0
    director.skill_levels[3] = 10
    director.cooldowns[3] = 0.0
    director._cast_orb()
    _check(director.projectiles.size() == 1, "orb_level_10_casts")
    if not director.projectiles.is_empty():
        _check(int(director.projectiles[0].pierce) == 2, "orb_level_10_pierces")
        _check(float(director.projectiles[0].burst_radius) > 7.0, "orb_level_10_bursts")

    var bridge_sites: Array = main._terrain_builder._bridge_sites_cache
    _check(bridge_sites.size() >= 6, "all_bridge_sites_cached")
    for site in bridge_sites:
        var center: Vector2 = site.position
        var direction: Vector2 = site.direction
        var road_width: float = site.road_width
        var river_width: float = site.river_width
        var deck_half := maxf(river_width + 10.0, road_width * 2.15) * .5
        var outer := center + direction * (deck_half + 10.0)
        var raw_y: float = main._world_result.terrain_height_sampler.call(outer.x, outer.y).y
        var walk_y: float = main._world_result.height_sampler.call(outer.x, outer.y).y
        print("BRIDGE_SAMPLE|%s|raw=%.4f|walk=%.4f|lift=%.4f" % [site.get("name", "bridge"), raw_y, walk_y, walk_y - raw_y])
        _check(walk_y + .01 >= raw_y + .15, "bridge_outer_ramp_matches_%s" % site.get("name", "bridge"))
        _check(main._world_result.walkable_sampler.call(center.x, center.y), "bridge_center_walkable_%s" % site.get("name", "bridge"))

    var decks := main.find_children("ContinuousBridgeDeck", "MeshInstance3D", true, false)
    var ramps := main.find_children("TaperedBridgeApproach*", "MeshInstance3D", true, false)
    _check(decks.size() >= bridge_sites.size(), "bridge_decks_exist")
    _check(ramps.size() >= decks.size() * 2, "both_bridge_approaches_exist")
    for ramp in ramps:
        _check(ramp.find_children("*", "StaticBody3D", true, false).size() > 0, "approach_has_collision")

    print("WORLD_PASS|menus=ok|spark5=2|spark10=3|bridges=%d|ramps=%d|failures=%d" % [bridge_sites.size(), ramps.size(), failures.size()])
    main.free()
    quit(0 if failures.is_empty() else 12)
