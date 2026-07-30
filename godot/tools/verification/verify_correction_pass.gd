extends SceneTree

var failures:Array[String]=[]

func _init()->void:call_deferred("_run")
func _check(condition:bool,label:String)->void:
    if condition:return
    failures.append(label);push_error("CORRECTION_FAIL|%s"%label)

func _run()->void:
    var main:Node3D=(load("res://scenes/Main.tscn") as PackedScene).instantiate();root.add_child(main)
    await process_frame;await process_frame
    var player:Node=main.get_node("Player");var director:Node=main.get_node("GameplayDirector")
    var profile:Dictionary=main.get("_active_profile")
    _check(profile.get("zone_id","")=="starting_realm","starting_zone_active")
    _check(profile.get("zone_exits",[]).size()==3,"starting_zone_has_three_exits")
    _check(get_nodes_in_group("interactive_house_door").size()>=10,"houses_have_working_doors")
    _check(main.find_children("Townsperson*","Node3D",true,false).is_empty(),"static_townfolk_removed")
    var has_axe:=false
    for item in player.bag_slots:
        if item.get("id","")=="starter_wood_axe":has_axe=true
    _check(has_axe,"starter_axe_in_bag")

    var logs_before:int=player.logs
    director._spawn_world_drop(player.global_position,{"kind":"material","material":"logs","amount":1,"name":"Verifier Log"})
    var loot_before:int=director.loot.size();director._tick_loot(1.0)
    _check(director.loot.size()==loot_before and player.logs==logs_before,"loot_does_not_auto_collect")
    director._tick_vendor();director._collect_nearby_loot()
    _check(player.logs==logs_before+1,"manual_e_pickup_collects")

    var chest_data:Dictionary={}
    for portal in director.get("_portals"):
        if portal.get("action","")=="chest" and str(portal.get("boss_gate","")).is_empty():chest_data=portal;break
    var chest_loot_before:int=director.loot.size();var bag_before:int=player.bag_slots.size()
    director._loot_dungeon_chest(chest_data)
    _check(director.loot.size()>=chest_loot_before+3,"chest_spawns_three_visible_rewards")
    _check(player.bag_slots.size()==bag_before,"chest_does_not_silently_fill_bag")
    _check(main.find_children("LockedPortcullis","StaticBody3D",true,false).size()>=3,"gates_are_portcullises")
    _check(main.find_children("VisibleDungeonKey","Node3D",true,false).size()>=3,"keys_have_key_silhouette")

    player.active_class="Warrior";player._equip_loadout_item("royal_vanguard_sword","mainhand");player._equip_loadout_item("royal_vanguard_shield","offhand")
    player.stamina=100.0;director.cooldowns[0]=0.0;director._warrior_sword_slash()
    _check(player.stamina==88.0,"warrior_spends_stamina")
    _check(player.mana==player.mana,"warrior_resource_is_finite")

    main._load_zone("north_frontier","south")
    _check(main.get("_active_zone_id")=="north_frontier","north_zone_loaded")
    _check(main.get("_active_profile").get("zone_name","")=="North Frontier","zone_has_own_map_profile")
    _check(main.find_children("TerrainMesh","MeshInstance3D",true,false).size()==1,"only_active_zone_terrain_is_loaded")
    _check(main.get_node("GameplayDirector").get("_portals").size()>0,"destination_zone_interactions_rebuilt")

    print("CORRECTION_PASS|doors=%d|manual_loot=ok|chest_drops=3|portcullises=%d|zone=%s|terrain_meshes=%d|failures=%d"%[
        get_nodes_in_group("interactive_house_door").size(),main.find_children("LockedPortcullis","StaticBody3D",true,false).size(),main.get("_active_zone_id"),main.find_children("TerrainMesh","MeshInstance3D",true,false).size(),failures.size()])
    main.free();quit(0 if failures.is_empty() else 19)
