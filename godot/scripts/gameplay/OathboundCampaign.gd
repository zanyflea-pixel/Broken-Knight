extends Node3D

## A playable lore quest that turns the Five Civic Oaths into world actions.
## The sites are layered onto the existing world and use its roads, settlements,
## fort, windmill, and capital approach instead of building a separate level.

const CAMPAIGN_TITLE := "The Oaths We Keep"
const ARCHIVIST_POINT := Vector2(-374.0, 112.0)
const ROAD_SHRINE_POINT := Vector2(-1337.0, -128.0)
const GREYWATCH_POINT := Vector2(-1669.0, 1720.0)
const HIGHFIELD_MILL_POINT := Vector2(-435.0, 1590.0)
const MERCY_SHRINE_POINT := Vector2(1168.0, 545.0)
const RAMPART_POINT := Vector2(-160.0, -1920.0)
const HOLLOW_GUARD_ENCOUNTER := "oathbound_hollow_guard"
const HOLLOW_GUARD_GOAL := 5

var director
var player
var profile: Dictionary = {}
var stage := 0
var hollow_guards_defeated := 0
var reward_claimed := false
var oaths_kept: Dictionary = {
    "road": false,
    "witness": false,
    "hearth": false,
    "mercy": false,
    "rampart": false,
}
var unlocked_lore: Dictionary = {}
var discovered: Dictionary = {"riverwatch_archive": true}
var _story_interactions: Array[Dictionary] = []
var _archivist_marker: Label3D
var _windmill_rotor: Node3D


func configure(gameplay_director, hero, world_profile: Dictionary) -> void:
    director = gameplay_director
    player = hero
    profile = world_profile
    name = "OathboundCampaign"
    set_meta("always_streamed", true)
    _build_archivist()
    _build_road_oath_site()
    _build_witness_site()
    _build_hearth_site()
    _build_mercy_site()
    _build_rampart_site()
    _register_interactions()
    _windmill_rotor = director.get_parent().find_child("Windmill Rotor", true, false) as Node3D
    _set_windmill_running(false)
    _sync_interaction_states()


func _process(_delta: float) -> void:
    if not is_instance_valid(player):
        return
    var point := Vector2(player.global_position.x, player.global_position.z)
    if point.distance_to(ROAD_SHRINE_POINT) < 90.0:
        discovered["west_road_shrine"] = true
    if point.distance_to(GREYWATCH_POINT) < 130.0:
        discovered["greywatch"] = true
    if point.distance_to(HIGHFIELD_MILL_POINT) < 120.0:
        discovered["highfield_mill"] = true
    if point.distance_to(MERCY_SHRINE_POINT) < 90.0:
        discovered["east_wayside"] = true
    if point.distance_to(RAMPART_POINT) < 120.0:
        discovered["crownspire_approach"] = true


func activate(data: Dictionary) -> void:
    var story_id := str(data.get("story_id", ""))
    match story_id:
        "archivist":
            if stage == 0:
                stage = 1
                unlocked_lore["five_oaths"] = true
                player.give_xp(12)
                director._notify("ARCHIVIST VALE — The crown did not make Valedorn. Five promises did. Begin with the west road shrine.", Color(1.0, .82, .42))
            elif stage == 7 and not reward_claimed:
                if not player.add_bag_item({
                    "id": "fivefold_oath_signet",
                    "name": "Fivefold Oath Signet",
                    "slot": "relic",
                    "icon": 10,
                    "power": 5,
                    "armor": 5,
                    "hp": 15,
                    "mana": 10,
                    "description": "Ordinary silver joined around five separate fragments. It remembers promises freely kept, but carries no command.",
                }):
                    director._notify("Your bag is full — make room for the Fivefold Oath Signet, then speak with Vale again.", Color(1.0, .48, .24))
                    return
                stage = 8
                reward_claimed = true
                unlocked_lore["hollow_king"] = true
                player.hero_gold += 140
                player.give_xp(240)
                player.add_material("crystal", 2)
                director._notify("QUEST COMPLETE — The Fivefold testimony is restored. Vale gives you the Oathkeepers' signet.", Color(1.0, .74, .20))
            elif stage >= 8:
                director._notify("Archivist Vale: Keep the fragments separate. A promise shared is stronger than a command imposed.", Color(.84, .88, .72))
            elif stage == 6:
                director._notify("Archivist Vale: The black seal must be answered at Crownspire, not here.", Color(.84, .88, .72))
            else:
                director._notify("Archivist Vale: The old oath sites preserve deeds more faithfully than the royal archive preserves words.", Color(.84, .88, .72))
        "road_shrine":
            if stage != 1:
                return
            oaths_kept["road"] = true
            unlocked_lore["road_oath"] = true
            discovered["west_road_shrine"] = true
            stage = 2
            player.give_xp(24)
            director._burst(data.get("position", Vector3.ZERO), Color(.88, .70, .24), 2.4)
            director._notify("ROAD OATH RESTORED — Passage belongs to peaceful travelers, not to the crown alone. Seek Greywatch's erased roll.", Color(1.0, .78, .28))
        "witness_roll":
            if stage != 2:
                return
            if not player.add_bag_item({
                "id": "greywatch_survivor_roll",
                "name": "Greywatch Survivor Roll",
                "slot": "quest",
                "icon": 10,
                "power": 0,
                "armor": 0,
                "hp": 0,
                "mana": 0,
                "description": "A smoke-stained list proving civilians escaped Greywatch through the postern the Broken Knight opened.",
            }):
                director._notify("Your bag is full — make room for the Greywatch survivor roll.", Color(1.0, .48, .24))
                return
            oaths_kept["witness"] = true
            unlocked_lore["witness_oath"] = true
            discovered["greywatch"] = true
            stage = 3
            player.give_xp(36)
            director._notify("WITNESS OATH RESTORED — The erased names survive. Highfield's silent mill holds the Hearth testimony.", Color(1.0, .78, .28))
        "mill_brake":
            if stage != 3:
                return
            oaths_kept["hearth"] = true
            unlocked_lore["hearth_oath"] = true
            discovered["highfield_mill"] = true
            stage = 4
            _set_windmill_running(true)
            player.give_xp(34)
            player.add_material("logs", 3)
            director._notify("HEARTH OATH RESTORED — Grain moves without a royal depot. The mill turns again, and Highfield shares its timber.", Color(1.0, .78, .28))
        "wounded_pilgrim":
            if stage != 4:
                return
            oaths_kept["mercy"] = true
            unlocked_lore["mercy_oath"] = true
            discovered["east_wayside"] = true
            stage = 5
            player.give_xp(34)
            player.health_potions += 1
            director._notify("MERCY OATH RESTORED — The wounded are treated before rank is named. Carry the four testimonies to Crownspire's approach.", Color(1.0, .78, .28))
        "crown_seal":
            if stage != 5:
                return
            oaths_kept["rampart"] = true
            unlocked_lore["rampart_oath"] = true
            unlocked_lore["crownstone"] = true
            discovered["crownspire_approach"] = true
            stage = 6
            hollow_guards_defeated = 0
            _spawn_hollow_guardians()
            director._burst(data.get("position", Vector3.ZERO), Color(.58, .18, .08), 4.2)
            director._notify("RAMPART OATH RESTORED — Walls protect people, not rulers. The whole-crown seal answers by raising its Hollow guards.", Color(1.0, .42, .18))
    _sync_interaction_states()
    if story_id in ["archivist", "road_shrine", "witness_roll", "mill_brake", "wounded_pilgrim", "crown_seal"]:
        _save_checkpoint()


func enemy_defeated(enemy: Dictionary) -> void:
    if stage != 6 or str(enemy.get("encounter_id", "")) != HOLLOW_GUARD_ENCOUNTER:
        return
    hollow_guards_defeated = mini(HOLLOW_GUARD_GOAL, hollow_guards_defeated + 1)
    if hollow_guards_defeated < HOLLOW_GUARD_GOAL:
        director._notify("Hollow guard broken  %d / %d" % [hollow_guards_defeated, HOLLOW_GUARD_GOAL], Color(.86, .70, .42))
        _save_checkpoint()
        return
    stage = 7
    player.give_xp(90)
    director._notify("THE WHOLE-CROWN SEAL IS SILENT — Return the five restored testimonies to Archivist Vale.", Color(1.0, .74, .22))
    _sync_interaction_states()
    _save_checkpoint()


func get_active_state() -> Dictionary:
    var descriptions := [
        "Speak with Archivist Vale beside Riverwatch's archive table.",
        "Follow the west road and turn the old wayside shrine back toward travelers.",
        "Climb to Greywatch Hill Fort and recover the erased survivor roll.",
        "Release the sabotaged brake at Highfield Windmill.",
        "Aid the nameless wounded pilgrim at the East Road wayside shrine.",
        "Carry the four testimonies to the black seal on Crownspire's northern approach.",
        "Defeat the five Hollow guards raised by the whole-crown seal.",
        "Return the restored Fivefold testimony to Archivist Vale in Riverwatch.",
        "The Five Civic Oaths have living witnesses again.",
    ]
    var current := 0
    var goal := 1
    if stage == 6:
        current = hollow_guards_defeated
        goal = HOLLOW_GUARD_GOAL
    elif stage >= 8:
        current = 1
    return {
        "id": "oathbound_campaign",
        "chapter": "LORE",
        "giver": "Archivist Vale, Riverwatch",
        "title": CAMPAIGN_TITLE,
        "story": "Five practical promises once divided the first crown's power. Veyne's agents are turning their surviving sites into monuments to obedience.",
        "description": descriptions[clampi(stage, 0, descriptions.size() - 1)],
        "current": current,
        "goal": goal,
        "available": true,
        "complete": stage >= 8,
        "claimed": reward_claimed,
        "reward": "140 gold, experience, two crystals, and the Fivefold Oath Signet",
        "objective_position": _objective_position(),
    }


func get_map_markers() -> Array[Dictionary]:
    var markers: Array[Dictionary] = [
        {"kind": "lore_site", "name": "West Road Oath Shrine", "position": _marker_position(ROAD_SHRINE_POINT), "discovered": discovered.get("west_road_shrine", false)},
        {"kind": "ruin", "name": "Greywatch Witness Roll", "position": _marker_position(GREYWATCH_POINT), "discovered": discovered.get("greywatch", false)},
        {"kind": "lore_site", "name": "Highfield Hearth Mill", "position": _marker_position(HIGHFIELD_MILL_POINT), "discovered": discovered.get("highfield_mill", false)},
        {"kind": "lore_site", "name": "East Wayside Mercy Shrine", "position": _marker_position(MERCY_SHRINE_POINT), "discovered": discovered.get("east_wayside", false)},
        {"kind": "lore_site", "name": "Crownspire Rampart Seal", "position": _marker_position(RAMPART_POINT), "discovered": discovered.get("crownspire_approach", false)},
    ]
    if stage < 8:
        var objective := _objective_position()
        markers.append({"kind": "story_objective", "name": get_active_state().description, "position": Vector3(objective.x, 0.0, objective.y), "discovered": true})
    return markers


func get_lore_entries() -> Array[Dictionary]:
    var definitions := [
        {"id": "five_oaths", "title": "The Five Civic Oaths", "text": "Road, Mercy, Hearth, Rampart, and Witness were public duties before the crown turned them into royal virtues. Their power comes from repeated service freely given."},
        {"id": "road_oath", "title": "The Road Oath", "text": "Passage must remain open to those who travel in peace. A road is not a favor granted by a ruler; it is work held in trust by everyone who keeps it usable."},
        {"id": "witness_oath", "title": "The Witness Oath", "text": "The names of the dead and the truth of events must not be erased. Greywatch's survivor roll proves the Broken Knight saved civilians rather than betraying the fort."},
        {"id": "hearth_oath", "title": "The Hearth Oath", "text": "No community may be deliberately starved into obedience. Highfield's mill was stopped so grain would pass only through army-controlled depots."},
        {"id": "mercy_oath", "title": "The Mercy Oath", "text": "Wounds are treated before rank is considered. Mercy given without reward leaves a stronger oath than any command pressed into metal."},
        {"id": "rampart_oath", "title": "The Rampart Oath", "text": "Walls and weapons exist to protect people, not merely rulers. A fort that sacrifices those outside its gate has already broken its purpose."},
        {"id": "crownstone", "title": "Crownstone", "text": "The warm black star-metal stores intense intention but cannot judge truth. It remembers terror as easily as courage, which makes commands impressed upon it powerful and dangerous."},
        {"id": "hollow_king", "title": "The Hollow King", "text": "Malrec survives beneath Crownspire as a king, a crown, and centuries of stored commands fused together. He cannot accept refusal because the whole crown preserved demand after relationship died."},
    ]
    var result: Array[Dictionary] = []
    for entry in definitions:
        if bool(unlocked_lore.get(entry.id, false)):
            result.append(entry.duplicate(true))
    return result


func get_save_state() -> Dictionary:
    return {
        "version": 1,
        "stage": stage,
        "guards_defeated": hollow_guards_defeated,
        "reward_claimed": reward_claimed,
        "oaths": oaths_kept.duplicate(true),
        "lore": unlocked_lore.duplicate(true),
        "discovered": discovered.duplicate(true),
    }


func load_save_state(data: Dictionary) -> void:
    stage = clampi(int(data.get("stage", 0)), 0, 8)
    hollow_guards_defeated = clampi(int(data.get("guards_defeated", 0)), 0, HOLLOW_GUARD_GOAL)
    reward_claimed = bool(data.get("reward_claimed", false)) or stage >= 8
    oaths_kept = {"road": false, "witness": false, "hearth": false, "mercy": false, "rampart": false}
    oaths_kept.merge(data.get("oaths", {}), true)
    unlocked_lore = {}
    unlocked_lore.merge(data.get("lore", {}), true)
    discovered = {"riverwatch_archive": true}
    discovered.merge(data.get("discovered", {}), true)
    _set_windmill_running(stage >= 4)
    if stage == 6 and not _has_living_guardians():
        # Enemy health is intentionally not serialized. Restart the encounter
        # and its counter together so a mid-fight desktop restart cannot leave
        # an impossible 3/5 objective with five newly spawned guards.
        hollow_guards_defeated = 0
        _spawn_hollow_guardians()
    _sync_interaction_states()


func _register_interactions() -> void:
    _register_story("archivist", _ground(ARCHIVIST_POINT), 4.2, "Speak with Archivist Vale")
    _register_story("road_shrine", _ground(ROAD_SHRINE_POINT), 4.5, "Turn the shrine toward the road")
    _register_story("witness_roll", _ground(GREYWATCH_POINT + Vector2(10.0, -5.0)), 4.2, "Recover the Greywatch survivor roll")
    _register_story("mill_brake", _ground(HIGHFIELD_MILL_POINT + Vector2(8.0, 4.0)), 4.2, "Release the windmill brake")
    _register_story("wounded_pilgrim", _ground(MERCY_SHRINE_POINT + Vector2(6.0, -5.0)), 4.5, "Treat the wounded pilgrim")
    _register_story("crown_seal", _ground(RAMPART_POINT), 5.0, "Break the whole-crown command seal")


func _register_story(action_id: String, position: Vector3, radius: float, label: String) -> Dictionary:
    var interaction: Dictionary = {
        "action": "oathbound_story",
        "story_id": action_id,
        "position": position,
        "radius": radius,
        "label": label,
        "active": true,
    }
    _story_interactions.append(interaction)
    director._interactables.append(interaction)
    return interaction


func _sync_interaction_states() -> void:
    for interaction in _story_interactions:
        match str(interaction.story_id):
            "archivist": interaction.active = stage in [0, 7, 8]
            "road_shrine": interaction.active = stage == 1
            "witness_roll": interaction.active = stage == 2
            "mill_brake": interaction.active = stage == 3
            "wounded_pilgrim": interaction.active = stage == 4
            "crown_seal": interaction.active = stage == 5
    if is_instance_valid(_archivist_marker):
        if stage == 0:
            _archivist_marker.text = "ARCHIVIST VALE\nE — LORE QUEST"
        elif stage == 7:
            _archivist_marker.text = "ARCHIVIST VALE\nE — RETURN TESTIMONIES"
        else:
            _archivist_marker.text = "ARCHIVIST VALE"


func _spawn_hollow_guardians() -> void:
    if _has_living_guardians():
        return
    var offsets := [Vector2(-9.0, -3.0), Vector2(-4.0, 8.0), Vector2(5.0, 9.0), Vector2(10.0, 0.0), Vector2(2.0, -10.0)]
    var variants := ["graveguard", "shambler", "runner", "graveguard", "carrier"]
    for index in range(offsets.size()):
        director._spawn_zombie(RAMPART_POINT + offsets[index], variants[index], HOLLOW_GUARD_ENCOUNTER)


func _has_living_guardians() -> bool:
    for enemy in director.minions:
        if str(enemy.get("encounter_id", "")) == HOLLOW_GUARD_ENCOUNTER and is_instance_valid(enemy.get("node")) and not bool(enemy.get("dead", false)):
            return true
    return false


func _save_checkpoint() -> void:
    if OS.get_environment("BROKEN_KNIGHT_TEST_MODE") != "1":
        director._save_game()


func _set_windmill_running(running: bool) -> void:
    if not is_instance_valid(_windmill_rotor):
        _windmill_rotor = director.get_parent().find_child("Windmill Rotor", true, false) as Node3D
    if is_instance_valid(_windmill_rotor):
        _windmill_rotor.set("turn_speed", .12 if running else 0.0)


func _objective_position() -> Vector2:
    match stage:
        0, 7: return ARCHIVIST_POINT
        1: return ROAD_SHRINE_POINT
        2: return GREYWATCH_POINT
        3: return HIGHFIELD_MILL_POINT
        4: return MERCY_SHRINE_POINT
        5, 6: return RAMPART_POINT
        _: return ARCHIVIST_POINT


func _marker_position(point: Vector2) -> Vector3:
    return Vector3(point.x, 0.0, point.y)


func _ground(point: Vector2) -> Vector3:
    return director._ground(Vector3(point.x, 0.0, point.y))


func _new_surface_root(name_value: String, point: Vector2) -> Node3D:
    var root := Node3D.new()
    root.name = name_value
    director.add_child(root)
    root.global_position = _ground(point)
    return root


func _label(root: Node3D, text_value: String, position: Vector3, color: Color, range_end := 90.0) -> Label3D:
    var label := Label3D.new()
    label.text = text_value
    label.position = position
    label.font_size = 28
    label.pixel_size = .010
    label.modulate = color
    label.outline_size = 7
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.visibility_range_end = range_end
    root.add_child(label)
    return label


func _build_archivist() -> void:
    var root := _new_surface_root("ArchivistVale", ARCHIVIST_POINT)
    director._add_service_person(root, Color(.26, .20, .38), false)
    director._service_box(root, Vector3(0, 1.33, .27), Vector3(.35, .52, .04), Color(.70, .58, .22))
    _archivist_marker = _label(root, "ARCHIVIST VALE\nE — LORE QUEST", Vector3(0, 2.72, 0), Color(1.0, .80, .32), 95.0)
    var table := _new_surface_root("ValeArchiveTable", ARCHIVIST_POINT + Vector2(4.0, 1.0))
    director._service_solid_box(table, Vector3(0, .72, 0), Vector3(3.2, .18, 1.5), Color(.31, .17, .07))
    for x in [-1.25, 1.25]:
        director._service_solid_box(table, Vector3(x, .35, 0), Vector3(.16, .70, .16), Color(.20, .10, .04))
    director._service_box(table, Vector3(0, .89, 0), Vector3(.52, .10, .34), Color(.07, .065, .06))


func _build_road_oath_site() -> void:
    var root := _new_surface_root("WestRoadOathTablet", ROAD_SHRINE_POINT)
    director._service_solid_box(root, Vector3(0, .35, 0), Vector3(3.6, .70, 2.6), Color(.34, .32, .26))
    director._service_solid_box(root, Vector3(0, 1.85, 0), Vector3(2.4, 2.8, .38), Color(.42, .40, .34))
    for index in range(5):
        director._service_box(root, Vector3(-.72 + float(index) * .36, 1.85, -.23), Vector3(.19, .66, .10), Color(.65, .49, .15))
    _label(root, "WEST ROAD OATH SHRINE\nE — RESTORE", Vector3(0, 3.45, 0), Color(.94, .76, .34), 95.0)


func _build_witness_site() -> void:
    var root := _new_surface_root("GreywatchWitnessChest", GREYWATCH_POINT + Vector2(10.0, -5.0))
    director._service_solid_box(root, Vector3(0, .48, 0), Vector3(2.8, .96, 1.8), Color(.28, .14, .05))
    director._service_box(root, Vector3(0, 1.05, -.08), Vector3(2.9, .22, 1.82), Color(.39, .22, .08))
    director._service_box(root, Vector3(0, 1.25, -.92), Vector3(1.0, .62, .12), Color(.68, .57, .32))
    _label(root, "GREYWATCH SURVIVOR ROLL\nE — RECOVER", Vector3(0, 2.55, 0), Color(.92, .80, .51), 110.0)


func _build_hearth_site() -> void:
    var root := _new_surface_root("HighfieldMillBrake", HIGHFIELD_MILL_POINT + Vector2(8.0, 4.0))
    director._service_solid_box(root, Vector3(0, .62, 0), Vector3(1.2, 1.24, 1.2), Color(.30, .27, .20))
    var lever: MeshInstance3D = director._service_box(root, Vector3(0, 1.35, 0), Vector3(.18, 1.3, .18), Color(.37, .18, .06))
    lever.rotation.z = -.58
    director._service_box(root, Vector3(.36, 1.88, 0), Vector3(.42, .24, .24), Color(.58, .43, .16))
    _label(root, "HIGHFIELD MILL BRAKE\nE — RELEASE", Vector3(0, 2.85, 0), Color(.96, .74, .26), 85.0)


func _build_mercy_site() -> void:
    var root := _new_surface_root("EastWaysidePilgrim", MERCY_SHRINE_POINT + Vector2(6.0, -5.0))
    var pilgrim := Node3D.new()
    pilgrim.name = "WoundedPilgrim"
    root.add_child(pilgrim)
    director._add_service_person(pilgrim, Color(.30, .25, .16), false)
    pilgrim.rotation.z = 1.12
    pilgrim.position = Vector3(0, .12, 0)
    director._service_box(root, Vector3(0, .08, 0), Vector3(2.8, .12, 1.1), Color(.35, .22, .10))
    _label(root, "WOUNDED PILGRIM\nE — GIVE AID", Vector3(0, 2.20, 0), Color(.82, 1.0, .66), 80.0)


func _build_rampart_site() -> void:
    var root := _new_surface_root("CrownspireWholeCrownSeal", RAMPART_POINT)
    director._service_solid_box(root, Vector3(0, .55, 0), Vector3(5.2, 1.1, 4.2), Color(.30, .29, .25))
    director._service_solid_box(root, Vector3(0, 2.30, 0), Vector3(2.3, 3.5, .55), Color(.045, .042, .04))
    for index in range(5):
        var angle := float(index) * TAU / 5.0 - PI * .5
        director._service_box(root, Vector3(cos(angle) * .66, 2.32, -.32 + sin(angle) * .66), Vector3(.18, .18, .12), Color(.72, .16, .05))
    _label(root, "WHOLE-CROWN COMMAND SEAL\nE — DEFY", Vector3(0, 4.65, 0), Color(1.0, .42, .18), 115.0)
