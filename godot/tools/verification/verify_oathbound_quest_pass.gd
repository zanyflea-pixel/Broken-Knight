extends SceneTree

var failures: Array[String] = []


func _init() -> void:
    call_deferred("_run")


func _check(condition: bool, label: String) -> void:
    if condition:
        return
    failures.append(label)
    push_error("OATHBOUND_FAIL|%s" % label)


func _interaction(campaign: Node, story_id: String, index := -1) -> Dictionary:
    for interaction in campaign.get("_story_interactions"):
        if str(interaction.get("story_id", "")) != story_id:
            continue
        if index >= 0 and int(interaction.get("index", -1)) != index:
            continue
        return interaction
    return {}


func _quest_by_id(director: Node, quest_id: String) -> Dictionary:
    for quest in director.get_quest_state():
        if str(quest.get("id", "")) == quest_id:
            return quest
    return {}


func _living_encounter(director: Node, encounter_id: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for enemy in director.minions:
        if str(enemy.get("encounter_id", "")) == encounter_id and is_instance_valid(enemy.get("node")) and not bool(enemy.get("dead", false)):
            result.append(enemy)
    return result


func _has_bag_item(player: Node, item_id: String) -> bool:
    for item in player.bag_slots:
        if str(item.get("id", "")) == item_id:
            return true
    return false


func _remove_encounter(director: Node, encounter_id: String) -> void:
    for index in range(director.minions.size() - 1, -1, -1):
        var enemy: Dictionary = director.minions[index]
        if str(enemy.get("encounter_id", "")) != encounter_id:
            continue
        var enemy_node := enemy.get("node") as Node
        if is_instance_valid(enemy_node):
            enemy_node.queue_free()
        director.minions.remove_at(index)


func _run() -> void:
    var main: Node3D = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
    root.add_child(main)
    await main.boot_completed
    var player: Node = main.get_node("Player")
    var director: Node = main.get_node("GameplayDirector")
    var campaign: Node = director.get("_oathbound_campaign")
    var gravebound: Node = director.get("_gravebound_campaign")

    _check(is_instance_valid(campaign), "oathbound_campaign_created")
    _check(int(campaign.stage) == 0, "fresh_lore_quest_opening")
    _check(not _quest_by_id(director, "oathbound_campaign").is_empty(), "lore_quest_is_in_journal")
    _check(_interaction(campaign, "archivist").get("active", false), "archivist_interaction_active")

    campaign.activate(_interaction(campaign, "archivist"))
    _check(int(campaign.stage) == 1 and campaign.get_lore_entries().size() == 1, "archivist_starts_five_oaths")
    campaign.activate(_interaction(campaign, "road_shrine"))
    _check(int(campaign.stage) == 2 and bool(campaign.oaths_kept.road), "road_oath_restored")
    campaign.activate(_interaction(campaign, "witness_roll"))
    _check(int(campaign.stage) == 3 and bool(campaign.oaths_kept.witness), "witness_oath_restored")
    _check(_has_bag_item(player, "greywatch_survivor_roll"), "greywatch_roll_becomes_quest_item")
    campaign.activate(_interaction(campaign, "mill_brake"))
    _check(int(campaign.stage) == 4 and bool(campaign.oaths_kept.hearth), "hearth_oath_restored")
    var rotor := main.find_child("Windmill Rotor", true, false)
    _check(is_instance_valid(rotor) and is_equal_approx(float(rotor.get("turn_speed")), .12), "windmill_visibly_restarted")
    campaign.activate(_interaction(campaign, "wounded_pilgrim"))
    _check(int(campaign.stage) == 5 and bool(campaign.oaths_kept.mercy), "mercy_oath_restored")
    campaign.activate(_interaction(campaign, "crown_seal"))
    _check(int(campaign.stage) == 6 and bool(campaign.oaths_kept.rampart), "rampart_oath_restored")
    var guardians := _living_encounter(director, campaign.HOLLOW_GUARD_ENCOUNTER)
    _check(guardians.size() == campaign.HOLLOW_GUARD_GOAL, "five_hollow_guardians_spawn")
    for guardian in guardians:
        director._damage(guardian, 100000.0)
    await process_frame
    _check(int(campaign.stage) == 7 and int(campaign.hollow_guards_defeated) == 5, "guardian_combat_advances_story")
    campaign.activate(_interaction(campaign, "archivist"))
    _check(int(campaign.stage) == 8 and bool(campaign.reward_claimed), "fivefold_testimony_returned")
    _check(_has_bag_item(player, "fivefold_oath_signet"), "lore_quest_reward_added")
    _check(director.get_lore_entries().size() == 8, "all_lore_entries_unlocked")
    var saved_oathbound: Dictionary = campaign.get_save_state()
    campaign.stage = 0
    campaign.reward_claimed = false
    campaign.load_save_state(saved_oathbound)
    _check(int(campaign.stage) == 8 and bool(campaign.reward_claimed), "oathbound_save_round_trip")
    var transition_state: Dictionary = director.get_zone_transition_state()
    campaign.stage = 0
    campaign.reward_claimed = false
    director.load_zone_transition_state(transition_state)
    _check(int(campaign.stage) == 8 and bool(campaign.reward_claimed), "story_progress_survives_zone_transition")

    # The opening counter quest used to pay once in _check_quest_rewards and a
    # second time in _damage. It also allowed pre-gathered items to instantly
    # finish newly unlocked chapters.
    director._quest_claimed = {}
    director._quest_baselines = {"road_imps": 0}
    director._gathered_counts["herbs"] = 12
    player.enemies_defeated = 7
    player.hero_gold = 0
    player.health_potions = 0
    director._spawn_minion(24.0, 0.0)
    var opening_enemy: Dictionary = director.minions.back()
    director._damage(opening_enemy, 100000.0)
    _check(bool(director._quest_claimed.get("road_imps", false)), "opening_counter_quest_completes")
    _check(player.hero_gold == 35 and player.health_potions == 1, "opening_quest_reward_paid_once")
    var medicine := _quest_by_id(director, "field_medicine")
    _check(not bool(director._quest_claimed.get("field_medicine", false)) and int(medicine.current) == 0, "locked_work_does_not_autocomplete_next_quest")
    director._gathered_counts["herbs"] = 13
    medicine = _quest_by_id(director, "field_medicine")
    _check(int(medicine.current) == 1, "newly_unlocked_quest_counts_new_work")

    # Persist the exact seal identity, not merely a count. Previously restoring
    # seal 2 and loading marked seal 0 complete instead.
    gravebound.stage = 4
    gravebound.completed_seals.clear()
    gravebound.seals_cleansed = 0
    gravebound._sync_interaction_states()
    gravebound.activate(_interaction(gravebound, "grave_seal", 2))
    var seal_save: Dictionary = gravebound.get_save_state()
    gravebound.completed_seals.clear()
    gravebound.seals_cleansed = 0
    gravebound.load_save_state(seal_save)
    _check(gravebound.completed_seals == [2] and int(gravebound.seals_cleansed) == 1, "grave_seal_identity_survives_load")
    _check(not _interaction(gravebound, "grave_seal", 2).active and _interaction(gravebound, "grave_seal", 0).active, "correct_grave_seal_interactions_restore")

    # Loading during the courier ambush must rebuild its unsaved enemy state.
    _remove_encounter(director, "courier_ambush")
    gravebound.stage = 2
    gravebound.load_save_state(gravebound.get_save_state())
    _check(_living_encounter(director, "courier_ambush").size() == 5, "courier_ambush_respawns_on_midfight_load")

    # Repeatable contracts likewise restart both enemies and progress together.
    _remove_encounter(director, "contract_mirecroft_sweep")
    var contract_save: Dictionary = gravebound.get_save_state()
    contract_save.merge({"stage": 9, "contract_active": "mirecroft_sweep", "contract_goal": 4, "contract_kills": 2}, true)
    gravebound.load_save_state(contract_save)
    _check(int(gravebound.contract_kills) == 0 and _living_encounter(director, "contract_mirecroft_sweep").size() == 4, "contract_reload_counter_matches_respawn")

    print("OATHBOUND_QUEST_PASS|stage=%d|lore=%d|guardians=%d|quests=%d|failures=%d" % [
        campaign.stage,
        director.get_lore_entries().size(),
        guardians.size(),
        director.get_quest_state().size(),
        failures.size(),
    ])
    main.queue_free()
    await process_frame
    quit(0 if failures.is_empty() else 19)
